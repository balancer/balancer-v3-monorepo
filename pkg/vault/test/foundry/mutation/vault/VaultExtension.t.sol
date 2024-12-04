// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract VaultExtensionMutationTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testIsUnlockedWhenNotVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.NotVaultDelegateCall.selector));
        vaultExtension.isUnlocked();
    }

    function testGetNonzeroDeltaCountWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getNonzeroDeltaCount();
    }

    function testGetTokenDeltaWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getTokenDelta(dai);
    }

    function testGetReservesOfWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getReservesOf(dai);
    }

    function testRegisterPoolWhenNotVault() public {
        TokenConfig[] memory config;
        PoolRoleAccounts memory roles;
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.registerPool(pool, config, 0, 0, false, roles, address(0), liquidityManagement);
    }

    function testRegisterPoolReentrancy() public {
        TokenConfig[] memory config;
        PoolRoleAccounts memory roles;
        LiquidityManagement memory liquidityManagement;

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualRegisterPoolReentrancy(pool, config, 0, 0, false, roles, address(0), liquidityManagement);
    }

    function testIsPoolRegisteredWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.isPoolRegistered(pool);
    }

    function testInitializeWhenNotVault() public {
        IERC20[] memory tokens;
        uint256[] memory exactAmountsIn;

        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.initialize(pool, address(0), tokens, exactAmountsIn, 0, bytes(""));
    }

    function testInitializeReentrancy() public {
        IERC20[] memory tokens;
        uint256[] memory exactAmountsIn;

        vault.forceUnlock();

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vault.manualInitializePoolReentrancy(pool, address(0), tokens, exactAmountsIn, 0, bytes(""));
    }

    function testIsPoolInitializedWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.isPoolInitialized(pool);
    }

    function testGetPoolConfigWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getPoolConfig(pool);
    }

    function testGetHooksConfigWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getHooksConfig(pool);
    }

    function testGetPoolTokensWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getPoolTokens(pool);
    }

    function testGetPoolTokenRatesWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getPoolTokenRates(pool);
    }

    function testGetPoolDataWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getPoolData(pool);
    }

    function testGetPoolTokenInfoWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getPoolTokenInfo(pool);
    }

    function testGetCurrentLiveBalancesWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getCurrentLiveBalances(pool);
    }

    function testComputeDynamicSwapFeePercentageWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        PoolSwapParams memory swapParams;
        vaultExtension.computeDynamicSwapFeePercentage(pool, swapParams);
    }

    function testComputeDynamicSwapFeePercentageWhenNotInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, address(0xbeef)));
        PoolSwapParams memory swapParams;
        vault.computeDynamicSwapFeePercentage(address(0xbeef), swapParams);
    }

    function testGetProtocolFeeControllerWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getProtocolFeeController();
    }

    function testGetBptRateWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getBptRate(pool);
    }

    function testTotalSupplyWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.totalSupply(address(dai));
    }

    function testBalanceOfWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.balanceOf(address(dai), address(0));
    }

    function testAllowanceWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.allowance(address(dai), address(1), address(2));
    }

    function testApproveWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.approve(address(0), address(1), 0);
    }

    function testIsPoolPausedWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.isPoolPaused(pool);
    }

    function testGetPoolPausedStateWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getPoolPausedState(pool);
    }

    function testGetAggregateSwapFeeAmountWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getAggregateSwapFeeAmount(pool, dai);
    }

    function testGetAggregateYieldFeeAmountWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getAggregateYieldFeeAmount(pool, dai);
    }

    function testGetStaticSwapFeePercentageWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getStaticSwapFeePercentage(pool);
    }

    function testGetPoolRoleAccountsWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getPoolRoleAccounts(pool);
    }

    function testIsPoolInRecoveryModeWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.isPoolInRecoveryMode(pool);
    }

    function testRemoveLiquidityRecoveryWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.removeLiquidityRecovery(pool, address(1), 0, new uint256[](2));
    }

    function testQuoteWhenNotVault() public {
        _prankStaticCall();
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.quote(bytes(""));
    }

    function testQuoteWhenNotStaticCall() public {
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        vaultExtension.quote(bytes(""));
    }

    function testQuoteAndRevertWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        _prankStaticCall();
        vaultExtension.quoteAndRevert(bytes(""));
    }

    function testQuoteAndRevertWhenNotStaticCall() public {
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        vaultExtension.quoteAndRevert(bytes(""));
    }

    function testIsQueryDisabledWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.isQueryDisabled();
    }

    function testEmitAuxiliaryEventWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.emitAuxiliaryEvent("", bytes(""));
    }

    function testEmitAuxiliaryEventWhenNotRegisteredPool() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(this)));
        vault.emitAuxiliaryEvent("", bytes(""));
    }

    function testIsERC4626BufferInitializedWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.isERC4626BufferInitialized(IERC4626(address(1)));
    }

    function testGetERC4626BufferAssetWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getERC4626BufferAsset(IERC4626(address(1)));
    }

    function testGetAuthorizerWhenNotVault() public {
        vm.expectRevert(IVaultErrors.NotVaultDelegateCall.selector);
        vaultExtension.getAuthorizer();
    }
}
