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
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultAdminUnitTest is BaseVaultTest {
    // This pool address was not registered and initialized and should be used only to test internal functions that
    // don't require access to pool information.
    address internal constant TEST_POOL = address(0x123);
    uint256 internal constant UNDERLYING_TOKENS_TO_DEPOSIT = 2e18;
    uint256 internal constant LIQUIDITY_AMOUNT = 1e18;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Authorize admin to pause and unpause vault
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVault.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.unpauseVault.selector), admin);
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
        uint256 shares = bufferRouter.initializeBuffer(waDAI, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, 0);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));
        vm.expectRevert(IVaultErrors.NotEnoughBufferShares.selector);
        // The call should revert since bob is trying to withdraw more shares than he has.
        vault.removeLiquidityFromBuffer(waDAI, shares + 1, 0, 0);
        vm.stopPrank();
    }

    /********************************************************************************
                                    Initialize Buffers
    ********************************************************************************/

    function testInitializeBufferTwice() public {
        vault.forceUnlock();
        vault.initializeBuffer(waDAI, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, 0, bob);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferAlreadyInitialized.selector, waDAI));
        vault.initializeBuffer(waDAI, 1, 1, 0, bob);
    }

    function testInitializeBufferAddressZero() public {
        vault.forceUnlock();
        waDAI.setAsset(IERC20(address(0)));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidUnderlyingToken.selector, waDAI));
        vault.initializeBuffer(waDAI, LIQUIDITY_AMOUNT, LIQUIDITY_AMOUNT, 0, bob);
    }

    function testInitializeBufferBelowMinimumShares() public {
        uint256 underlyingAmount = 1;
        uint256 wrappedAmount = 2;
        uint256 bufferInvariantDelta = underlyingAmount + _vaultPreviewRedeem(waDAI, wrappedAmount);

        vault.forceUnlock();
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferTotalSupplyTooLow.selector, bufferInvariantDelta));
        vault.initializeBuffer(waDAI, underlyingAmount, wrappedAmount, 0, bob);
    }

    function testInitializeBuffer() public {
        waDAI.mockRate(2e18);

        vault.forceUnlock();
        uint256 underlyingAmount = LIQUIDITY_AMOUNT * 2;
        uint256 wrappedAmount = LIQUIDITY_AMOUNT;

        // Get issued shares to match the event. The actual shares amount will be validated below.
        uint256 preInitSnap = vm.snapshot();
        uint256 issuedShares = vault.initializeBuffer(waDAI, underlyingAmount, wrappedAmount, 0, bob);
        vm.revertTo(preInitSnap);

        // Try to initialize below minimum
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferTotalSupplyTooLow.selector, 0));
        vault.initializeBuffer(waDAI, 0, 0, 0, bob);

        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, address(0), BUFFER_MINIMUM_TOTAL_SUPPLY);
        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, bob, issuedShares);
        vm.expectEmit();
        emit IVaultEvents.LiquidityAddedToBuffer(
            waDAI,
            underlyingAmount,
            wrappedAmount,
            PackedTokenBalance.toPackedBalance(underlyingAmount, wrappedAmount)
        );
        issuedShares = vault.initializeBuffer(waDAI, underlyingAmount, wrappedAmount, 0, bob);

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
            underlyingAmount + wrappedAmount * 2 - BUFFER_MINIMUM_TOTAL_SUPPLY - 2,
            2,
            "Wrong issued shares"
        );

        assertEq(vault.getBufferOwnerShares(waDAI, bob), issuedShares, "Wrong bob shares");
        assertEq(vault.getBufferOwnerShares(waDAI, address(0)), BUFFER_MINIMUM_TOTAL_SUPPLY, "Wrong burned shares");
        assertEq(vault.getBufferTotalShares(waDAI), issuedShares + BUFFER_MINIMUM_TOTAL_SUPPLY, "Wrong total shares");
    }

    function testMintMinimumBufferSupplyReserve() public {
        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, address(0), BUFFER_MINIMUM_TOTAL_SUPPLY);
        vault.manualMintMinimumBufferSupplyReserve(waDAI);

        assertEq(
            vault.getBufferOwnerShares(waDAI, address(0)),
            BUFFER_MINIMUM_TOTAL_SUPPLY,
            "address(0): wrong shares"
        );
        assertEq(vault.getBufferTotalShares(waDAI), BUFFER_MINIMUM_TOTAL_SUPPLY, "Wrong total buffer shares");
    }

    function testMintBufferShares() public {
        // 1st  mint
        uint256 amountToMint = BUFFER_MINIMUM_TOTAL_SUPPLY;
        uint256 totalMinted = amountToMint;

        vm.expectEmit();
        emit IVaultEvents.BufferSharesMinted(waDAI, bob, amountToMint);
        vault.manualMintBufferShares(waDAI, bob, amountToMint);

        assertEq(vault.getBufferOwnerShares(waDAI, bob), amountToMint, "Bob: Incorrect buffer shares (1)");
        assertEq(vault.getBufferTotalShares(waDAI), amountToMint, "Wrong total buffer shares (1)");

        // 2nd mint
        amountToMint = BUFFER_MINIMUM_TOTAL_SUPPLY + 12345;
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
            BUFFER_MINIMUM_TOTAL_SUPPLY + amountToMint,
            "Bob: Incorrect buffer shares (2)"
        );
        assertEq(vault.getBufferTotalShares(waDAI), totalMinted, "Wrong total buffer shares (3)");
    }

    function testMintBufferSharesBelowMinimumTotalSupply() public {
        uint256 supplyBelowMin = BUFFER_MINIMUM_TOTAL_SUPPLY - 1;
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferTotalSupplyTooLow.selector, supplyBelowMin));
        vault.manualMintBufferShares(waDAI, bob, supplyBelowMin);
    }

    function testMintBufferSharesInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferSharesInvalidReceiver.selector));
        vault.manualMintBufferShares(waDAI, address(0), BUFFER_MINIMUM_TOTAL_SUPPLY);
    }

    function testBurnBufferSharesInvalidOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferSharesInvalidOwner.selector));
        vault.manualBurnBufferShares(waDAI, address(0), BUFFER_MINIMUM_TOTAL_SUPPLY);
    }

    function testDisableQuery() public {
        bytes32 disableQueryRole = vault.getActionId(IVaultAdmin.disableQuery.selector);
        authorizer.grantRole(disableQueryRole, admin);

        vm.expectEmit();
        emit IVaultEvents.VaultQueriesDisabled();

        vm.prank(admin);
        vault.disableQuery();

        assertTrue(vault.isQueryDisabled(), "Query not disabled");
        assertFalse(vault.isQueryDisabledPermanently(), "Query is disabled permanently");

        // Calling twice is fine
        vm.prank(admin);
        vault.disableQuery();

        assertTrue(vault.isQueryDisabled(), "Query not disabled");
        assertFalse(vault.isQueryDisabledPermanently(), "Query is disabled permanently");
    }

    function testDisableQueryPermanently() public {
        bytes32 disableQueryRole = vault.getActionId(IVaultAdmin.disableQueryPermanently.selector);
        authorizer.grantRole(disableQueryRole, admin);

        vm.expectEmit();
        emit IVaultEvents.VaultQueriesDisabled();

        vm.prank(admin);
        vault.disableQueryPermanently();

        assertTrue(vault.isQueryDisabled(), "Query not disabled");
        assertTrue(vault.isQueryDisabledPermanently(), "Query is disabled permanently");

        // Calling twice is fine
        vm.prank(admin);
        vault.disableQueryPermanently();

        assertTrue(vault.isQueryDisabled(), "Query not disabled");
        assertTrue(vault.isQueryDisabledPermanently(), "Query is disabled permanently");
    }

    function testEnableQuery() public {
        testDisableQuery();

        bytes32 enableQueryRole = vault.getActionId(IVaultAdmin.enableQuery.selector);
        authorizer.grantRole(enableQueryRole, admin);

        vm.prank(admin);
        vault.enableQuery();

        assertFalse(vault.isQueryDisabled(), "Query disabled");
        assertFalse(vault.isQueryDisabledPermanently(), "Query is disabled permanently");

        // Calling twice is fine
        vm.prank(admin);
        vault.enableQuery();

        assertFalse(vault.isQueryDisabled(), "Query disabled");
        assertFalse(vault.isQueryDisabledPermanently(), "Query is disabled permanently");
    }

    function testEnableQueryIfDisabledPermanently() public {
        testDisableQueryPermanently();

        bytes32 enableQueryRole = vault.getActionId(IVaultAdmin.enableQuery.selector);
        authorizer.grantRole(enableQueryRole, admin);

        vm.expectRevert(IVaultErrors.QueriesDisabledPermanently.selector);
        vm.prank(admin);
        vault.enableQuery();
    }

    function testDisableQueryPermanentlyWhenDisabled() public {
        testDisableQuery();
        testDisableQueryPermanently();
    }
}
