// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    HooksConfig,
    LiquidityManagement,
    PoolConfig,
    PoolRoleAccounts,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { DirectionalFeeHookExample } from "../../contracts/DirectionalFeeHookExample.sol";

contract DirectionalHookExampleTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    StablePoolFactory internal stablePoolFactory;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        // Create the factory here, because it needs to be created after vault is created, but before hook is created.
        stablePoolFactory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        address directionalFeeHook = address(
            new DirectionalFeeHookExample(IVault(address(vault))),
            address(stablePoolFactory)
        );
        vm.label(directionalFeeHook, "Exit Fee Hook");
        return directionalFeeHook;
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolRoleAccounts memory roleAccounts;

        stablePool = StablePool(
            factory.create(
                "Stable Pool Test",
                "STABLETEST",
                inputHelpersMock.sortTokenConfig(tokens),
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                MIN_SWAP_FEE,
                poolHooksContract,
                false, // Does not allow donations
                ZERO_BYTES32
            )
        );
        vm.label(newPool, label);
        return address(stablePool);
    }

    function testRegistryWithWrongFactory() public {
        address exitFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        //        vm.expectRevert(ExitFeeHookExample.PoolDoesNotSupportDonation.selector);
        _registerPoolWithHook(exitFeePool, tokenConfig, false);
    }

    //    function testSuccessfulRegistry() public {
    //        address exitFeePool = _createPoolToRegister();
    //        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
    //            [address(dai), address(usdc)].toMemoryArray().asIERC20()
    //        );
    //
    //        _registerPoolWithHook(exitFeePool, tokenConfig, true);
    //
    //        PoolConfig memory poolConfig = vault.getPoolConfig(exitFeePool);
    //        HooksConfig memory hooksConfig = vault.getHooksConfig(exitFeePool);
    //
    //        assertEq(poolConfig.liquidityManagement.enableDonation, true, "pool's enableDonation is wrong");
    //        assertEq(
    //            poolConfig.liquidityManagement.disableUnbalancedLiquidity,
    //            true,
    //            "pool's disableUnbalancedLiquidity is wrong"
    //        );
    //        assertEq(hooksConfig.hooksContract, poolHooksContract, "pool's hooks contract is wrong");
    //        assertEq(hooksConfig.enableHookAdjustedAmounts, true, "hook's enableHookAdjustedAmounts is wrong");
    //    }
    //
    //    // Exit fee returns to LPs
    //    function testExitFeeReturnToLPs() public {
    //        // 10% exit fee
    //        uint64 exitFeePercentage = 1e17;
    //        vm.prank(lp);
    //        DirectionalFeeHookExample(poolHooksContract).setRemoveLiquidityHookFeePercentage(exitFeePercentage);
    //        uint256 amountOut = poolInitAmount / 2;
    //        uint256 hookFee = amountOut.mulDown(exitFeePercentage);
    //        uint256[] memory minAmountsOut = [amountOut - hookFee, amountOut - hookFee].toMemoryArray();
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(address(lp));
    //
    //        vm.prank(lp);
    //        router.removeLiquidityProportional(pool, 2 * amountOut, minAmountsOut, false, bytes(""));
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(address(lp));
    //
    //        // LP gets original liquidity minus hook fee
    //        assertEq(
    //            balancesAfter.lpTokens[daiIdx] - balancesBefore.lpTokens[daiIdx],
    //            amountOut - hookFee,
    //            "LP's DAI amount is wrong"
    //        );
    //        assertEq(
    //            balancesAfter.lpTokens[usdcIdx] - balancesBefore.lpTokens[usdcIdx],
    //            amountOut - hookFee,
    //            "LP's USDC amount is wrong"
    //        );
    //        assertEq(balancesBefore.lpBpt - balancesAfter.lpBpt, 2 * amountOut, "LP's BPT amount is wrong");
    //
    //        // Pool balances decrease by amountOut, and receive hook fee
    //        assertEq(
    //            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
    //            amountOut - hookFee,
    //            "Pool's DAI amount is wrong"
    //        );
    //        assertEq(
    //            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
    //            amountOut - hookFee,
    //            "Pool's USDC amount is wrong"
    //        );
    //        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, 2 * amountOut, "BPT supply amount is wrong");
    //
    //        // Same happens with Vault balances: decrease by amountOut, keep hook fee
    //        assertEq(
    //            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
    //            amountOut - hookFee,
    //            "Vault's DAI amount is wrong"
    //        );
    //        assertEq(
    //            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
    //            amountOut - hookFee,
    //            "Vault's USDC amount is wrong"
    //        );
    //
    //        // Hook balances remain unchanged
    //        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
    //        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");
    //        assertEq(balancesBefore.hookBpt, balancesAfter.hookBpt, "Hook's BPT amount is wrong");
    //    }

    // Registry tests require a new pool, because an existent pool may be already registered
    function _createPoolToRegister() private returns (address newPool) {
        newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));
        vm.label(newPool, "Exit Fee Pool");
    }

    function _registerPoolWithHook(address exitFeePool, TokenConfig[] memory tokenConfig, bool enableDonation) private {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = address(lp);

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;
        liquidityManagement.enableDonation = enableDonation;

        factoryMock.registerPool(exitFeePool, tokenConfig, roleAccounts, poolHooksContract, liquidityManagement);
    }
}
