// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

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

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { MeasureBalancesHelper } from "@balancer-labs/v3-vault/test/foundry/utils/MeasureBalancesHelper.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { ExitFeePaidToLPsHookExample } from "../../contracts/ExitFeePaidToLPsHookExample.sol";

contract ExitFeePaidToLPsHookExampleTest is BaseVaultTest, MeasureBalancesHelper {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();
        MeasureBalancesHelper.prepareMeasurement(dai, usdc, pool, poolHooksContract, address(bob), address(lp), vault);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        address exitFeeHook = address(new ExitFeePaidToLPsHookExample(IVault(address(vault))));
        vm.label(exitFeeHook, "Exit Fee Hook");
        return exitFeeHook;
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity and enables donation)
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = address(lp);

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;
        liquidityManagement.enableDonation = true;

        factoryMock.registerPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        return address(newPool);
    }

    function testRegistryWithWrongDonationFlag() public {
        address exitFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        vm.expectRevert(ExitFeePaidToLPsHookExample.PoolDoesNotSupportDonation.selector);
        _registerPoolWithHook(exitFeePool, tokenConfig, false);
    }

    function testSuccessfulRegistry() public {
        address exitFeePool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        _registerPoolWithHook(exitFeePool, tokenConfig, true);

        PoolConfig memory poolConfig = vault.getPoolConfig(exitFeePool);
        HooksConfig memory hooksConfig = vault.getHooksConfig(exitFeePool);

        assertEq(poolConfig.liquidityManagement.enableDonation, true, "pool's enableDonation is wrong");
        assertEq(
            poolConfig.liquidityManagement.disableUnbalancedLiquidity,
            true,
            "pool's disableUnbalancedLiquidity is wrong"
        );
        assertEq(hooksConfig.enableHookAdjustedAmounts, true, "hook's enableHookAdjustedAmounts is wrong");
    }

    // Exit fee returns to LPs
    function testExitFeeReturnToLPs() public {
        // 10% exit fee
        uint64 exitFeePercentage = 1e17;
        vm.prank(lp);
        ExitFeePaidToLPsHookExample(poolHooksContract).setRemoveLiquidityHookFeePercentage(exitFeePercentage);
        uint256 amountOut = poolInitAmount / 2;
        uint256 hookFee = amountOut.mulDown(exitFeePercentage);
        uint256[] memory minAmountsOut = [amountOut - hookFee, amountOut - hookFee].toMemoryArray();

        HookTestLocals memory vars = _measureBalancesBeforeOperation();

        vm.prank(lp);
        router.removeLiquidityProportional(pool, 2 * amountOut, minAmountsOut, false, bytes(""));

        _measureBalancesAfterOperation(vars);

        // LP gets original liquidity minus hook fee
        assertEq(vars.lp.daiAfter - vars.lp.daiBefore, amountOut - hookFee, "LP's DAI amount is wrong");
        assertEq(vars.lp.usdcAfter - vars.lp.usdcBefore, amountOut - hookFee, "LP's USDC amount is wrong");
        assertEq(vars.lp.bptBefore - vars.lp.bptAfter, 2 * amountOut, "LP's BPT amount is wrong");

        // Pool balances decrease by amountOut, and receive hook fee
        assertEq(vars.poolBefore[daiIdx] - vars.poolAfter[daiIdx], amountOut - hookFee, "Pool's DAI amount is wrong");
        assertEq(
            vars.poolBefore[usdcIdx] - vars.poolAfter[usdcIdx],
            amountOut - hookFee,
            "Pool's USDC amount is wrong"
        );
        assertEq(vars.bptSupplyBefore - vars.bptSupplyAfter, 2 * amountOut, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut, keep hook fee
        assertEq(vars.vault.daiBefore - vars.vault.daiAfter, amountOut - hookFee, "Vault's DAI amount is wrong");
        assertEq(vars.vault.usdcBefore - vars.vault.usdcAfter, amountOut - hookFee, "Vault's USDC amount is wrong");

        // Hook balances remain unchanged
        assertEq(vars.hook.daiBefore, vars.hook.daiAfter, "Hook's DAI amount is wrong");
        assertEq(vars.hook.usdcBefore, vars.hook.usdcAfter, "Hook's USDC amount is wrong");
        assertEq(vars.hook.bptBefore, vars.hook.bptAfter, "Hook's BPT amount is wrong");
    }

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
