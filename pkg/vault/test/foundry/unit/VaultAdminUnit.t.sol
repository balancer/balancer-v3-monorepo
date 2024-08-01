// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
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

    function testAddLiquidityToBufferBaseTokenChanged() public {
        vm.startPrank(bob);
        router.addLiquidityToBuffer(waDAI, liquidityAmount, liquidityAmount, bob);

        // Changes the wrapped token asset. The function `addLiquidityToBuffer` should revert, since the buffer was
        // initialized already with another underlying asset.
        waDAI.setAsset(usdc);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongWrappedTokenAsset.selector, address(waDAI)));
        router.addLiquidityToBuffer(waDAI, liquidityAmount, liquidityAmount, bob);
        vm.stopPrank();
    }

    function testRemoveLiquidityFromBufferNotEnoughShares() public {
        vm.startPrank(bob);
        uint256 shares = router.addLiquidityToBuffer(waDAI, liquidityAmount, liquidityAmount, bob);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));
        vm.expectRevert(IVaultErrors.NotEnoughBufferShares.selector);
        // The call should revert since bob is trying to withdraw more shares than he has.
        router.removeLiquidityFromBuffer(waDAI, shares + 1);
        vm.stopPrank();
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
