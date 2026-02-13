// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";

/**
 * @notice #4: "exploit-like" join->swap->exit sequences searching for value extraction.
 *
 * Security property (single-asset round-trip):
 * - Attacker mints exact BPT out using token A (single-asset join),
 * - performs a swap to manipulate pool state,
 * - then burns the same BPT to withdraw token A (single-asset exit),
 * - and must NOT end with more token A than they paid in.
 *
 * @dev We use `assert(...)` so any profit shows up as a Medusa failure (panic code 0x01).
 *      We also set swap fee to 0 via `manualUnsafeSetStaticSwapFeePercentage` (worst-case, no fees to mask rounding).
 */
contract JoinSwapExitProfitWeightedMedusaTest is BaseMedusaTest {
    using FixedPoint for uint256;

    uint256 private constant DEFAULT_SWAP_FEE = 1e16;

    uint256 private constant _WEIGHT1 = 33e16;
    uint256 private constant _WEIGHT2 = 33e16;

    // Align with other Medusa suites to avoid dust-induced invalid cases.
    uint256 private constant MIN_AMOUNT = 1e6;
    uint256 private constant MAX_IN_RATIO = 0.3e18;

    constructor() BaseMedusaTest() {
        // Worst-case: remove fees so any rounding exploit isn't masked.
        vault.manualUnsafeSetStaticSwapFeePercentage(address(pool), 0);
    }

    function createPool(IERC20[] memory tokens, uint256[] memory initialBalances) internal override returns (address) {
        uint256[] memory weights = new uint256[](3);
        weights[0] = _WEIGHT1;
        weights[1] = _WEIGHT2;
        weights[2] = 100e16 - (weights[0] + weights[1]);

        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        WeightedPool newPool = WeightedPool(
            factory.create(
                "Weighted Pool (join/swap/exit)",
                "WP-JSE",
                vault.buildTokenConfig(tokens),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE,
                address(0),
                false, // donation off
                false, // unbalanced allowed
                bytes32(poolCreationNonce++)
            )
        );

        // Keep consistent with other Weighted Medusa suites: set pool creator to lp on the Vault mock.
        vault.manualSetPoolCreator(address(newPool), lp);

        // Initialize liquidity.
        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        return address(newPool);
    }

    /**
     * @notice Single-asset join -> swap -> single-asset exit must not yield profit in the join token.
     * @dev To make "no profit in token A" meaningful without portfolio accounting, we force the swap input to be token A.
     *      This way, all costs are measured in the same token we check for profit.
     */
    function computeJoinSwapExitNoProfit(
        uint256 tokenJoinExitIndexRaw,
        uint256 bptOutRaw,
        uint256 swapTokenOutIndexRaw,
        uint256 swapAmountInRaw
    ) public {
        uint256 numTokens = vault.getPoolTokens(address(pool)).length;
        if (numTokens < 2) revert();

        uint256 tokenJoinExitIndex = bound(tokenJoinExitIndexRaw, 0, numTokens - 1);

        // Bound BPT out to something the attacker can realistically round-trip without hitting unrelated limits.
        uint256 bptOut;
        {
            uint256 maxBptOut = BalancerPoolToken(address(pool)).totalSupply() / 20;
            if (maxBptOut < MIN_AMOUNT) revert();
            bptOut = bound(bptOutRaw, MIN_AMOUNT, maxBptOut);
        }

        // Pull tokens once. Load balances only when needed to keep stack usage low.
        IERC20[] memory tokens = vault.getPoolTokens(address(pool));

        // --- Step 0: pick swap pair ---
        // Force swap input to be the join/exit token so profit is measured in a single asset (token A).
        uint256 swapTokenInIndex = tokenJoinExitIndex;
        uint256 swapTokenOutIndex = bound(swapTokenOutIndexRaw, 0, numTokens - 1);
        if (swapTokenOutIndex == tokenJoinExitIndex) swapTokenOutIndex = (swapTokenOutIndex + 1) % numTokens;

        IERC20 joinToken = tokens[tokenJoinExitIndex];

        // --- Step 1: attacker joins single-asset to mint exact BPT ---
        uint256 attackerBalanceBefore = joinToken.balanceOf(alice);
        uint256 attackerBptBefore = IERC20(address(pool)).balanceOf(alice);

        {
            medusa.prank(alice);
            uint256 tokenAmountIn = router.addLiquiditySingleTokenExactOut(
                address(pool),
                joinToken,
                type(uint128).max,
                bptOut,
                false,
                bytes("")
            );

            // If rounding/limits made this nonsensical, discard.
            if (tokenAmountIn < MIN_AMOUNT) revert();
        }

        // --- Step 2: attacker manipulates pool state with a swap ---
        // Bound swap amount after the join so the caller can always pay it and so we avoid systematic reverts.
        uint256 swapAmountIn;
        {
            (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));

            uint256 maxSwapAmountByPool = balancesRaw[swapTokenInIndex].mulDown(MAX_IN_RATIO);
            uint256 attackerBalanceAfterJoin = joinToken.balanceOf(alice);
            uint256 maxSwapAmountIn = maxSwapAmountByPool < attackerBalanceAfterJoin
                ? maxSwapAmountByPool
                : attackerBalanceAfterJoin;
            if (maxSwapAmountIn < MIN_AMOUNT) revert();
            swapAmountIn = bound(swapAmountInRaw, MIN_AMOUNT, maxSwapAmountIn);
        }

        medusa.prank(alice);
        router.swapSingleTokenExactIn(
            address(pool),
            tokens[swapTokenInIndex],
            tokens[swapTokenOutIndex],
            swapAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        // --- Step 3: attacker exits single-asset burning the same BPT, receiving token A ---
        medusa.prank(alice);
        uint256 tokenAmountOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptOut,
            joinToken,
            0,
            false,
            bytes("")
        );

        // --- Assertion: no profit in the join/exit token ---
        uint256 attackerBalanceAfter = joinToken.balanceOf(alice);
        // All costs in token A are accounted for (join + swap both spend token A; exit returns token A).
        // With 0 fees, rounding should still favor the pool; ending with more token A indicates value extraction.
        assert(attackerBalanceAfter <= attackerBalanceBefore);

        // BPT round-trip sanity: attacker should end with the same BPT balance they started with.
        uint256 attackerBptAfter = IERC20(address(pool)).balanceOf(alice);
        assert(attackerBptAfter == attackerBptBefore);

        // Avoid unused-variable warnings and ensure the exit leg actually executed.
        assert(tokenAmountOut > 0);
    }
}
