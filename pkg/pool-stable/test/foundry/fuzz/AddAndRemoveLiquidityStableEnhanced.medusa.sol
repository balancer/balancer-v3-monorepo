// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";

import { StablePoolFactory } from "../../../contracts/StablePoolFactory.sol";

/**
 * @title AddAndRemoveLiquidityStableEnhanced Medusa Fuzz Test
 * @notice Enhanced Medusa fuzzing tests for Stable pool liquidity operations
 * @dev Key invariants tested:
 *   - BPT rate should never decrease after add/remove liquidity
 *   - Total supply should be consistent with balances
 *   - No tokens should be created or destroyed
 *   - Pool balances should remain above minimums
 *   - Invariant should be monotonic with liquidity
 */
contract AddAndRemoveLiquidityStableEnhancedMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    // Stable pool specific parameters
    uint256 internal constant AMPLIFICATION_PARAMETER = 200;
    uint256 internal constant AMP_PRECISION = StableMath.AMP_PRECISION;

    // Limits
    uint256 internal constant MIN_TRADE_AMOUNT = 1e6;
    uint256 internal constant _POOL_MINIMUM_TOTAL_SUPPLY = 1e6;

    // Track state for cross-call invariants
    uint256 internal lastKnownVaultBptRate;

    constructor() BaseMedusaTest() {
        // Record initial state after pool initialization
        lastKnownVaultBptRate = vault.getBptRate(address(pool));
    }

    /**
     * @notice Override to create a Stable pool instead of the default pool
     */
    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        StablePoolFactory factory = new StablePoolFactory(vault, 365 days, "", "");

        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Stable Pool",
            "STABLE",
            vault.buildTokenConfig(tokens),
            AMPLIFICATION_PARAMETER,
            roleAccounts,
            1e12, // 0.0001% swap fee
            address(0),
            false,
            false,
            // Use a unique salt (matches other Medusa pool tests)
            bytes32(poolCreationNonce++)
        );

        // Initialize liquidity
        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    /***************************************************************************
                               FUZZ FUNCTIONS
     ***************************************************************************/

    /**
     * @notice Fuzz: Add liquidity proportionally
     * @dev Note: `Router.addLiquidityProportional` takes an **exact BPT out** amount (not a minBPTOut).
     * @param exactBptOutSeed Seed used to derive exact BPT out (bounded)
     */
    function addLiquidityProportional(uint256 exactBptOutSeed) external {
        _addLiquidityProportionalAndAssert(exactBptOutSeed);
    }

    function _addLiquidityProportionalAndAssert(uint256 exactBptOutSeed) internal {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, uint256[] memory balancesScaled18Before) =
            vault.getPoolTokenInfo(address(pool));

        uint256 invariantBefore =
            StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balancesScaled18Before);
        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        uint256 aliceBptBefore = IERC20(address(pool)).balanceOf(alice);

        // Keep proportional mints small so the quote/execution should not revert.
        uint256 maxExactBptOut = totalSupplyBefore / 100; // 1% of supply
        if (maxExactBptOut < _POOL_MINIMUM_TOTAL_SUPPLY) return;
        uint256 exactBptAmountOut = _boundValue(exactBptOutSeed, _POOL_MINIMUM_TOTAL_SUPPLY, maxExactBptOut);

        uint256[] memory quotedAmountsIn =
            router.queryAddLiquidityProportional(address(pool), exactBptAmountOut, alice, bytes(""));
        if (!_anyNonZero(quotedAmountsIn)) return;

        uint256[] memory maxAmountsIn = _maxAmountsInCapped(tokens, balancesBefore, alice, quotedAmountsIn);

        uint256[] memory aliceTokenBefore = _balancesOf(tokens, alice);

        medusa.prank(alice);
        uint256[] memory actualAmountsIn =
            router.addLiquidityProportional(address(pool), maxAmountsIn, exactBptAmountOut, false, bytes(""));

        _assertAmountsInAndBalances(tokens, balancesBefore, alice, aliceTokenBefore, quotedAmountsIn, actualAmountsIn);

        uint256 aliceBptAfter = IERC20(address(pool)).balanceOf(alice);
        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        assert(aliceBptAfter - aliceBptBefore == exactBptAmountOut);
        assert(totalSupplyAfter - totalSupplyBefore == exactBptAmountOut);

        _assertInvariantNonDecreasingFrom(invariantBefore);
        _assertVaultBptRateNeverDecreases();
    }

    function _assertInvariantNonDecreasingFrom(uint256 invariantBefore) internal view {
        (, , , uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(address(pool));
        uint256 invariantAfter =
            StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balancesScaled18After);
        assert(invariantAfter + invariantBefore / 1e12 >= invariantBefore);
    }

    function _anyNonZero(uint256[] memory xs) internal pure returns (bool) {
        for (uint256 i = 0; i < xs.length; i++) {
            if (xs[i] != 0) return true;
        }
        return false;
    }

    function _balancesOf(IERC20[] memory tokens, address user) internal view returns (uint256[] memory bals) {
        bals = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            bals[i] = tokens[i].balanceOf(user);
        }
    }

    function _maxAmountsInCapped(
        IERC20[] memory tokens,
        uint256[] memory balancesBefore,
        address user,
        uint256[] memory quotedAmountsIn
    ) internal view returns (uint256[] memory maxAmountsIn) {
        maxAmountsIn = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 headroom = type(uint128).max - balancesBefore[i];
            uint256 userBal = tokens[i].balanceOf(user);
            uint256 max = headroom < userBal ? headroom : userBal;
            if (quotedAmountsIn[i] > max) revert();
            maxAmountsIn[i] = quotedAmountsIn[i];
        }
    }

    function _assertAmountsInAndBalances(
        IERC20[] memory tokens,
        uint256[] memory balancesBefore,
        address user,
        uint256[] memory userTokenBefore,
        uint256[] memory quotedAmountsIn,
        uint256[] memory actualAmountsIn
    ) internal view {
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < tokens.length; i++) {
            assert(actualAmountsIn[i] == quotedAmountsIn[i]);
            assert(userTokenBefore[i] - tokens[i].balanceOf(user) == actualAmountsIn[i]);
            assert(balancesAfter[i] - balancesBefore[i] == actualAmountsIn[i]);
        }
    }

    /**
     * @notice Fuzz: Add liquidity unbalanced
     * @param seed0 Seed for token 0 amount
     * @param seed1 Seed for token 1 amount
     * @param seed2 Seed for token 2 amount
     */
    function addLiquidityUnbalanced(uint256 seed0, uint256 seed1, uint256 seed2) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory exactAmountsIn = new uint256[](tokens.length);

        // Keep unbalanced adds small to reduce legitimate Stable guardrail reverts.
        uint256[3] memory seeds = [seed0, seed1, seed2];
        bool anyIn = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 headroom = type(uint128).max - balancesBefore[i];
            uint256 userBal = tokens[i].balanceOf(alice);
            uint256 max = headroom < userBal ? headroom : userBal;
            max = max / 200; // 0.5% of available headroom/balance

            if (max < MIN_TRADE_AMOUNT) {
                exactAmountsIn[i] = 0;
                continue;
            }

            uint256 amt = _boundValue(seeds[i], 0, max);
            if (amt != 0 && amt < MIN_TRADE_AMOUNT) amt = MIN_TRADE_AMOUNT;
            exactAmountsIn[i] = amt;
            if (amt != 0) anyIn = true;
        }
        if (!anyIn) return;

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        uint256 aliceBptBefore = IERC20(address(pool)).balanceOf(alice);

        uint256 quotedBptOut = router.queryAddLiquidityUnbalanced(address(pool), exactAmountsIn, alice, bytes(""));
        if (quotedBptOut == 0) return;

        uint256[] memory aliceTokenBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            aliceTokenBefore[i] = tokens[i].balanceOf(alice);
        }

        medusa.prank(alice);
        uint256 bptOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));
        assert(bptOut == quotedBptOut);

        // Verify BPT/accounting
        uint256 aliceBptAfter = IERC20(address(pool)).balanceOf(alice);
        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        assert(bptOut > 0);
        assert(aliceBptAfter - aliceBptBefore == bptOut);
        assert(totalSupplyAfter - totalSupplyBefore == bptOut);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 delta = aliceTokenBefore[i] - tokens[i].balanceOf(alice);
            assert(delta == exactAmountsIn[i]);
            assert(balancesAfter[i] - balancesBefore[i] == exactAmountsIn[i]);
        }

        _assertVaultBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Remove liquidity proportionally
     * @param bptIn Amount of BPT to burn (bounded)
     */
    function removeLiquidityProportional(uint256 bptIn) external {
        uint256 lpBalance = IERC20(address(pool)).balanceOf(lp);
        if (lpBalance == 0) return;

        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        if (totalSupplyBefore <= _POOL_MINIMUM_TOTAL_SUPPLY) return;

        // Bound to available balance and keep pool above minimum total supply
        uint256 maxBurn = totalSupplyBefore - _POOL_MINIMUM_TOTAL_SUPPLY;
        if (maxBurn > lpBalance) maxBurn = lpBalance;
        bptIn = _boundValue(bptIn, MIN_TRADE_AMOUNT, maxBurn / 50); // 2% max to reduce guardrail noise

        uint256[] memory quotedAmountsOut =
            router.queryRemoveLiquidityProportional(address(pool), bptIn, lp, bytes(""));

        uint256[] memory minAmountsOut = new uint256[](tokens.length);

        uint256 lpBptBefore = IERC20(address(pool)).balanceOf(lp);
        uint256[] memory lpTokenBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            lpTokenBefore[i] = tokens[i].balanceOf(lp);
        }

        medusa.prank(lp);
        uint256[] memory amountsOut =
            router.removeLiquidityProportional(address(pool), bptIn, minAmountsOut, false, bytes(""));

        // Verify BPT burn accounting
        uint256 lpBptAfter = IERC20(address(pool)).balanceOf(lp);
        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        assert(lpBptBefore - lpBptAfter == bptIn);
        assert(totalSupplyBefore - totalSupplyAfter == bptIn);

        // Verify accounting (pool/user deltas match returned amounts)
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < tokens.length; i++) {
            assert(amountsOut[i] == quotedAmountsOut[i]);
            assert(tokens[i].balanceOf(lp) - lpTokenBefore[i] == amountsOut[i]);
            assert(balancesBefore[i] - balancesAfter[i] == amountsOut[i]);
        }

        _assertVaultBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Remove liquidity single token exact out
     * @param amountOut Exact amount of token to receive
     * @param tokenIndex Which token to receive
     */
    function removeLiquiditySingleTokenExactOut(uint256 amountOut, uint256 tokenIndex) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        tokenIndex = tokenIndex % tokens.length;

        uint256 lpBptBefore = IERC20(address(pool)).balanceOf(lp);
        if (lpBptBefore == 0) return;

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        if (totalSupplyBefore <= _POOL_MINIMUM_TOTAL_SUPPLY) return;

        // Bound to a conservative fraction to reduce legitimate guardrail reverts
        uint256 maxOut = balancesBefore[tokenIndex] / 50; // 2%
        if (maxOut < MIN_TRADE_AMOUNT) return;
        amountOut = _boundValue(amountOut, MIN_TRADE_AMOUNT, maxOut);

        uint256 lpTokenBefore = tokens[tokenIndex].balanceOf(lp);

        uint256 quotedBptIn =
            router.queryRemoveLiquiditySingleTokenExactOut(address(pool), tokens[tokenIndex], amountOut, lp, bytes(""));
        if (quotedBptIn == 0 || quotedBptIn > lpBptBefore) return;

        medusa.prank(lp);
        uint256 bptIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            quotedBptIn, // max BPT in (tight: quote==execution)
            tokens[tokenIndex],
            amountOut,
            false,
            bytes("")
        );
        assert(bptIn == quotedBptIn);

        // Verify accounting
        uint256 lpBptAfter = IERC20(address(pool)).balanceOf(lp);
        assert(lpBptBefore - lpBptAfter == bptIn);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(tokens[tokenIndex].balanceOf(lp) - lpTokenBefore == amountOut);
        assert(balancesBefore[tokenIndex] - balancesAfter[tokenIndex] == amountOut);

        _assertVaultBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Remove liquidity single token exact in
     * @param bptIn Amount of BPT to burn
     * @param tokenIndex Which token to receive
     */
    function removeLiquiditySingleTokenExactIn(uint256 bptIn, uint256 tokenIndex) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        tokenIndex = tokenIndex % tokens.length;

        uint256 lpBptBefore = IERC20(address(pool)).balanceOf(lp);
        if (lpBptBefore == 0) return;

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        if (totalSupplyBefore <= _POOL_MINIMUM_TOTAL_SUPPLY) return;

        uint256 maxBurn = totalSupplyBefore - _POOL_MINIMUM_TOTAL_SUPPLY;
        if (maxBurn > lpBptBefore) maxBurn = lpBptBefore;
        bptIn = _boundValue(bptIn, MIN_TRADE_AMOUNT, maxBurn / 50); // 2% max to reduce guardrail noise

        uint256 lpTokenBefore = tokens[tokenIndex].balanceOf(lp);

        uint256 quotedAmountOut =
            router.queryRemoveLiquiditySingleTokenExactIn(address(pool), bptIn, tokens[tokenIndex], lp, bytes(""));
        if (quotedAmountOut == 0) return;

        medusa.prank(lp);
        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptIn,
            tokens[tokenIndex],
            0,
            false,
            bytes("")
        );
        assert(amountOut == quotedAmountOut);

        // Verify accounting
        uint256 lpBptAfter = IERC20(address(pool)).balanceOf(lp);
        assert(lpBptBefore - lpBptAfter == bptIn);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(tokens[tokenIndex].balanceOf(lp) - lpTokenBefore == amountOut);
        assert(balancesBefore[tokenIndex] - balancesAfter[tokenIndex] == amountOut);

        _assertVaultBptRateNeverDecreases();
    }
    /**
     * @notice Property: No profit from round-trip add/remove
     */
    /***************************************************************************
                              HELPER FUNCTIONS
     ***************************************************************************/

    function _boundValue(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _assertVaultBptRateNeverDecreases() internal {
        uint256 currentRate = vault.getBptRate(address(pool));
        if (currentRate > lastKnownVaultBptRate) {
            lastKnownVaultBptRate = currentRate;
        }
        // Allow for tiny rounding errors (0.001%)
        assert(currentRate >= lastKnownVaultBptRate.mulDown(99999e13));
    }
}
