// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IERC20MultiTokenErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiTokenErrors.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultAdminUnitTest is BaseVaultTest {
    // This pool address was not registered and initialized and should be used only to test internal functions that
    // don't require access to pool information.
    address internal constant TEST_POOL = address(0x123);
    uint256 internal constant underlyingTokensToDeposit = 2e18;
    uint256 internal constant liquidityAmount = 1e18;
    uint256 internal constant _MINIMUM_TOTAL_SUPPLY = 1e6;

    ERC4626TestToken internal waDAI;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Authorize admin to pause and unpause vault
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVault.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.unpauseVault.selector), admin);

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        _initializeBob();
    }

    // withValidPercentage
    function testWithValidPercentage() public view {
        // Any percentage below 100% is valid. This test expects not to be reverted.
        vault.mockWithValidPercentage(0.5e18);
    }

    function testWithValidPercentageRevert() public {
        // Any percentage above 100% is not valid and modifier should revert.
        vm.expectRevert(IVaultErrors.ProtocolFeesExceedTotalCollected.selector);
        vault.mockWithValidPercentage(FixedPoint.ONE + 1);
    }

    // _setVaultPaused
    function testPauseVaultWhenVaultIsPaused() public {
        // Pause vault
        vm.prank(admin);
        vault.pauseVault();
        assertTrue(vault.isVaultPaused(), "Vault is not paused");

        // Vault is already paused and we're trying to pause again.
        vm.expectRevert(IVaultErrors.VaultPaused.selector);
        vault.manualPauseVault();
    }

    function testUnpauseVaultWhenVaultIsUnpaused() public {
        assertFalse(vault.isVaultPaused(), "Vault is paused");

        // Vault is already unpaused and we're trying to unpause again.
        vm.expectRevert(IVaultErrors.VaultNotPaused.selector);
        vault.manualUnpauseVault();
    }

    function testPauseWithExpiredWindow() public {
        uint32 pauseTime = vault.getPauseWindowEndTime();
        assertFalse(vault.isVaultPaused(), "Vault is paused");

        // Changes block.timestamp to something greater than _pauseWindowEndTime
        vm.warp(pauseTime + 10);

        // Vault is not paused and we're trying to pause it, but the pause window has expired.
        vm.expectRevert(IVaultErrors.VaultPauseWindowExpired.selector);
        vault.manualPauseVault();
    }

    // _setPoolPaused
    function testPausePoolWhenPoolIsPaused() public {
        // Pause pool
        PoolConfig memory poolConfig;
        poolConfig.isPoolPaused = true;
        // Pause window cannot be expired
        poolConfig.pauseWindowEndTime = uint32(block.timestamp + 10);
        vault.manualSetPoolConfig(TEST_POOL, poolConfig);

        // Pool is already paused and we're trying to pause again.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPaused.selector, TEST_POOL));
        vault.manualPausePool(TEST_POOL);
    }

    function testUnpausePoolWhenPoolIsUnpaused() public {
        // Pool is already unpaused and we're trying to unpause again.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotPaused.selector, TEST_POOL));
        vault.manualUnpausePool(TEST_POOL);
    }

    // _ensurePoolNotInRecoveryMode
    function testEnsurePoolNotInRecoveryMode() public view {
        // Should not revert because pool is not in recovery mode
        vault.mockEnsurePoolNotInRecoveryMode(TEST_POOL);
    }

    function testEnsurePoolNotInRecoveryModeRevert() public {
        // Set recovery mode flag
        PoolConfig memory poolConfig;
        poolConfig.isPoolInRecoveryMode = true;
        vault.manualSetPoolConfig(TEST_POOL, poolConfig);

        // Should not revert because pool is not in recovery mode
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolInRecoveryMode.selector, TEST_POOL));
        vault.mockEnsurePoolNotInRecoveryMode(TEST_POOL);
    }

    function testRemoveLiquidityFromBufferNotEnoughShares() public {
        vm.startPrank(bob);
        uint256 shares = router.initializeBuffer(waDAI, liquidityAmount, liquidityAmount);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));
        vm.expectRevert(IVaultErrors.NotEnoughBufferShares.selector);
        // The call should revert since bob is trying to withdraw more shares than he has.
        vault.removeLiquidityFromBuffer(waDAI, shares + 1);
        vm.stopPrank();
    }

    /********************************************************************************
                                    Initialize Buffers
    ********************************************************************************/

    function testInitializeBufferTwice() public {
        vault.manualSetIsUnlocked(true);
        vault.initializeBuffer(waDAI, liquidityAmount, liquidityAmount, bob);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferAlreadyInitialized.selector, waDAI));
        vault.initializeBuffer(waDAI, 1, 1, bob);
    }

    function testInitializeBufferAddressZero() public {
        vault.manualSetIsUnlocked(true);
        waDAI.setAsset(IERC20(address(0)));

        vm.expectRevert(IVaultErrors.InvalidUnderlyingToken.selector);
        vault.initializeBuffer(waDAI, liquidityAmount, liquidityAmount, bob);
    }

    function testInitializeBufferBelowMinimumShares() public {
        vault.manualSetIsUnlocked(true);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20MultiTokenErrors.TotalSupplyTooLow.selector, 3, _MINIMUM_TOTAL_SUPPLY)
        );
        vault.initializeBuffer(waDAI, 1, 2, bob);
    }

    function testInitializeBuffer() public {
        dai.mint(address(waDAI), underlyingTokensToDeposit); // This will make the rate = 2

        vault.manualSetIsUnlocked(true);
        uint256 underlyingAmount = liquidityAmount * 2;
        uint256 wrappedAmount = liquidityAmount;

        // Get issued shares to match the event. The actual shares amount will be validated below.
        uint256 preInitSnap = vm.snapshot();
        uint256 issuedShares = vault.initializeBuffer(waDAI, underlyingAmount, wrappedAmount, bob);
        vm.revertTo(preInitSnap);

        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, bob, issuedShares);
        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, address(0), _MINIMUM_TOTAL_SUPPLY);
        vm.expectEmit();
        emit IVaultEvents.LiquidityAddedToBuffer(waDAI, underlyingAmount, wrappedAmount);
        issuedShares = vault.initializeBuffer(waDAI, underlyingAmount, wrappedAmount, bob);

        assertEq(vault.getBufferAsset(waDAI), address(dai), "Wrong underlying asset");

        // Initialize takes debt, which is a positive delta.
        assertEq(uint256(vault.getTokenDelta(dai)), underlyingAmount, "Wrong underlying delta");
        assertEq(uint256(vault.getTokenDelta(waDAI)), wrappedAmount, "Wrong wrapped delta");

        // Balances
        (uint256 underlyingBufferBalance, uint256 wrappedBufferBalance) = vault.getBufferBalance(waDAI);
        assertEq(underlyingBufferBalance, underlyingAmount, "Wrong buffer underlying balance");
        assertEq(wrappedBufferBalance, wrappedAmount, "Wrong buffer wrapped balance");

        // Shares (wrapped rate is ~2; allow rounding error)
        assertApproxEqAbs(
            issuedShares,
            underlyingAmount + wrappedAmount * 2 - _MINIMUM_TOTAL_SUPPLY,
            1,
            "Wrong issued shares"
        );

        assertEq(vault.getBufferOwnerShares(waDAI, bob), issuedShares, "Wrong bob shares");
        assertEq(vault.getBufferOwnerShares(waDAI, address(0)), _MINIMUM_TOTAL_SUPPLY, "Wrong burnt shares");
        assertEq(vault.getBufferTotalShares(waDAI), issuedShares + _MINIMUM_TOTAL_SUPPLY, "Wrong total shares");
    }

    function testMintMinimumBufferSupplyReserve() public {
        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, address(0), _MINIMUM_TOTAL_SUPPLY);
        vault.manualMintMinimumBufferSupplyReserve(waDAI);

        assertEq(vault.getBufferOwnerShares(waDAI, address(0)), _MINIMUM_TOTAL_SUPPLY, "address(0): wrong shares");
        assertEq(vault.getBufferTotalShares(waDAI), _MINIMUM_TOTAL_SUPPLY, "Wrong total buffer shares");
    }

    function testMintBufferShares() public {
        // 1st  mint
        uint256 amountToMint = _MINIMUM_TOTAL_SUPPLY;
        uint256 totalMinted = amountToMint;

        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, bob, amountToMint);
        vault.manualMintBufferShares(waDAI, bob, amountToMint);

        assertEq(vault.getBufferOwnerShares(waDAI, bob), amountToMint, "Bob: Incorrect buffer shares (1)");
        assertEq(vault.getBufferTotalShares(waDAI), amountToMint, "Wrong total buffer shares (1)");

        // 2nd mint
        amountToMint = _MINIMUM_TOTAL_SUPPLY + 12345;
        totalMinted += amountToMint;

        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, alice, amountToMint);
        vault.manualMintBufferShares(waDAI, alice, amountToMint);

        assertEq(vault.getBufferOwnerShares(waDAI, alice), amountToMint, "Alice: Incorrect buffer shares");
        assertEq(vault.getBufferTotalShares(waDAI), totalMinted, "Wrong total buffer shares (2)");

        // 3rd mint
        amountToMint = 4321;
        totalMinted += amountToMint;

        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, bob, amountToMint);
        vault.manualMintBufferShares(waDAI, bob, amountToMint);
        assertEq(
            vault.getBufferOwnerShares(waDAI, bob),
            _MINIMUM_TOTAL_SUPPLY + amountToMint,
            "Bob: Incorrect buffer shares (2)"
        );
        assertEq(vault.getBufferTotalShares(waDAI), totalMinted, "Wrong total buffer shares (3)");
    }

    function testMintBufferSharesBelowMinimumTotalSupply() public {
        uint256 supplyBelowMin = _MINIMUM_TOTAL_SUPPLY - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20MultiTokenErrors.TotalSupplyTooLow.selector,
                supplyBelowMin,
                _MINIMUM_TOTAL_SUPPLY
            )
        );
        vault.manualMintBufferShares(waDAI, bob, supplyBelowMin);
    }

    function testMintBufferSharesIInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferSharesInvalidReceiver.selector, address(0)));
        vault.manualMintBufferShares(waDAI, address(0), _MINIMUM_TOTAL_SUPPLY);
    }

    function _initializeBob() private {
        vm.startPrank(bob);
        dai.approve(address(waDAI), underlyingTokensToDeposit);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);

        // Deposit some DAI to mint waDAI to bob, so he can add liquidity to the buffer.
        waDAI.deposit(underlyingTokensToDeposit, bob);
        vm.stopPrank();
    }
}
