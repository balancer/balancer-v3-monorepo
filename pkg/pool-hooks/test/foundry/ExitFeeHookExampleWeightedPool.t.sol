// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ExitFeeHookExample } from "../../contracts/ExitFeeHookExample.sol";

contract ExitFeeHookExampleWeightedPoolTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Exit fee of 10%
    uint64 public constant exitFeePercentage = 10e16;
    // The minimum swap fee for a Weighted Pool is 0.0001%.
    uint256 MIN_WEIGHTED_SWAP_FEE = 1e12;

    WeightedPoolFactory internal weightedPoolFactory;
    uint256[] internal weights;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        // LP will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        address exitFeeHook = address(new ExitFeeHookExample(IVault(address(vault))));
        vm.label(exitFeeHook, "Exit Fee Hook");
        return exitFeeHook;
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity and enables donation).
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        weightedPoolFactory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        address newPool = weightedPoolFactory.create(
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig(tokens.asIERC20()),
            weights,
            roleAccounts,
            MIN_WEIGHTED_SWAP_FEE,
            poolHooksContract,
            true, // supports donation
            true, // does not support unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(address(newPool), label);

        return address(newPool);
    }

    // Exit fee returns to LPs.
    function testExitFeeReturnToLPs() public {
        vm.expectEmit();
        emit ExitFeeHookExample.ExitFeePercentageChanged(poolHooksContract, exitFeePercentage);

        vm.prank(lp);
        ExitFeeHookExample(poolHooksContract).setExitFeePercentage(exitFeePercentage);

        uint256 bptAmountIn = IERC20(pool).totalSupply() / 100;
        // The weighted pool total supply is not exact and amountsOut will be rounded down, so we remove 1 wei from
        // expected amounts out.
        uint256 expectedAmountOutNoFees = poolInitAmount / 100 - 1;
        uint256 expectedHookFee = expectedAmountOutNoFees.mulDown(exitFeePercentage);

        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(lp);

        vm.expectEmit();
        emit ExitFeeHookExample.ExitFeeCharged(pool, IERC20(dai), expectedHookFee);

        vm.expectEmit();
        emit ExitFeeHookExample.ExitFeeCharged(pool, IERC20(usdc), expectedHookFee);

        vm.prank(lp);
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            pool,
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp);

        // amountsOut must be the expectedAmountsOut minus hook fees (which will stay in the pool, similar to lp fees).
        assertEq(amountsOut[daiIdx], expectedAmountOutNoFees - expectedHookFee, "DAI amount out is wrong");
        assertEq(amountsOut[usdcIdx], expectedAmountOutNoFees - expectedHookFee, "USDC amount out is wrong");

        // LP gets original liquidity minus hook fee.
        assertEq(
            balancesAfter.lpTokens[daiIdx] - balancesBefore.lpTokens[daiIdx],
            expectedAmountOutNoFees - expectedHookFee,
            "LP's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.lpTokens[usdcIdx] - balancesBefore.lpTokens[usdcIdx],
            expectedAmountOutNoFees - expectedHookFee,
            "LP's USDC amount is wrong"
        );
        assertEq(balancesBefore.lpBpt - balancesAfter.lpBpt, bptAmountIn, "LP's BPT amount is wrong");

        // Pool balances decrease by amountOut, and receive hook fee.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            expectedAmountOutNoFees - expectedHookFee,
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            expectedAmountOutNoFees - expectedHookFee,
            "Pool's USDC amount is wrong"
        );
        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, bptAmountIn, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut, keep hook fee.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            expectedAmountOutNoFees - expectedHookFee,
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            expectedAmountOutNoFees - expectedHookFee,
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");
        assertEq(balancesBefore.hookBpt, balancesAfter.hookBpt, "Hook's BPT amount is wrong");
    }
}
