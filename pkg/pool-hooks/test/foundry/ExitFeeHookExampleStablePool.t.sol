// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ExitFeeHookExample } from "../../contracts/ExitFeeHookExample.sol";

contract ExitFeeHookExampleStablePoolTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Maximum exit fee of 10%
    uint64 public constant MAX_EXIT_FEE_PERCENTAGE = 10e16;

    StablePoolFactory internal stablePoolFactory;
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

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
        stablePoolFactory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        address newPool = stablePoolFactory.create(
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            MAX_EXIT_FEE_PERCENTAGE,
            address(0),
            true, // supports donation
            true, // does not support unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(address(newPool), label);

        return address(newPool);
    }

    // Exit fee returns to LPs.
    function testExitFeeReturnToLPs() public {
        vm.prank(lp);
        ExitFeeHookExample(poolHooksContract).setExitFeePercentage(MAX_EXIT_FEE_PERCENTAGE);
        uint256 amountOut = poolInitAmount / 100;
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        BaseVaultTest.Balances memory balancesBefore = getBalances(lp);

        vm.prank(lp);
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            pool,
            2 * amountOut,
            minAmountsOut,
            false,
            bytes("")
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp);

        // LP gets original liquidity minus hook fee.
        assertEq(
            balancesAfter.lpTokens[daiIdx] - balancesBefore.lpTokens[daiIdx],
            amountsOut[daiIdx],
            "LP's DAI amount is wrong"
        );
        assertEq(
            balancesAfter.lpTokens[usdcIdx] - balancesBefore.lpTokens[usdcIdx],
            amountsOut[usdcIdx],
            "LP's USDC amount is wrong"
        );
        assertEq(balancesBefore.lpBpt - balancesAfter.lpBpt, 2 * amountOut, "LP's BPT amount is wrong");

        // Pool balances decrease by amountOut, and receive hook fee.
        assertEq(
            balancesBefore.poolTokens[daiIdx] - balancesAfter.poolTokens[daiIdx],
            amountsOut[daiIdx],
            "Pool's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            amountsOut[usdcIdx],
            "Pool's USDC amount is wrong"
        );
        assertEq(balancesBefore.poolSupply - balancesAfter.poolSupply, 2 * amountOut, "BPT supply amount is wrong");

        // Same happens with Vault balances: decrease by amountOut, keep hook fee.
        assertEq(
            balancesBefore.vaultTokens[daiIdx] - balancesAfter.vaultTokens[daiIdx],
            amountsOut[daiIdx],
            "Vault's DAI amount is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            amountsOut[usdcIdx],
            "Vault's USDC amount is wrong"
        );

        // Hook balances remain unchanged.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook's DAI amount is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook's USDC amount is wrong");
        assertEq(balancesBefore.hookBpt, balancesAfter.hookBpt, "Hook's BPT amount is wrong");
    }
}
