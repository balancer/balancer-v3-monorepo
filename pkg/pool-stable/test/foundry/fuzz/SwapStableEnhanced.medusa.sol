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
 * @title SwapStableEnhanced Medusa Fuzz Test
 * @notice Enhanced Medusa fuzzing tests for Stable pool swap operations
 * @dev Key invariants tested:
 *   - Quote/execution consistency (query == swap)
 *   - Invariant (scaled18) should not decrease after swaps (beyond tolerance)
 *   - Rounding should favor the pool (ExactOut >= ExactIn for same quoted output)
 *   - No profitable round-trip swaps (beyond tiny tolerance)
 */
contract SwapStableEnhancedMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    // Stable pool specific parameters
    uint256 internal constant AMPLIFICATION_PARAMETER = 200;
    uint256 internal constant AMP_PRECISION = StableMath.AMP_PRECISION;

    // Limits
    uint256 internal constant MIN_SWAP_AMOUNT = 1e6;
    uint256 internal constant MIN_INVARIANT_TOL = 10;
    uint256 internal constant MIN_SWAP_FEE_PERCENTAGE = 1e12; // StablePool.getMinimumSwapFeePercentage()

    // Track state
    uint256 internal lastKnownInvariant;
    uint256 internal swapCount;
    uint256 internal roundTripProfitCount;
    uint256 internal maxRoundTripProfit;

    constructor() BaseMedusaTest() {
        // Record initial invariant
        (, , , uint256[] memory balancesScaled18) = vault.getPoolTokenInfo(address(pool));
        lastKnownInvariant = StableMath.computeInvariant(
            AMPLIFICATION_PARAMETER * AMP_PRECISION,
            balancesScaled18
        );
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
            // Must be >= StablePool.getMinimumSwapFeePercentage() or pool registration reverts.
            MIN_SWAP_FEE_PERCENTAGE,
            address(0),
            false,
            false,
            bytes32("")
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
     * @notice Fuzz: Swap exact in
     * @param amountIn Amount to swap in
     * @param tokenSeedIn Seed used to pick tokenIn
     * @param tokenSeedOut Seed used to pick tokenOut (must differ from tokenIn)
     */
    function swapExactIn(uint256 amountIn, uint256 tokenSeedIn, uint256 tokenSeedOut) external {
        (IERC20[] memory tokens, uint256[] memory balancesRaw, ) = _getPoolData();
        if (tokens.length < 2) return;

        (uint256 tokenIndexIn, uint256 tokenIndexOut) = _pickTwoDistinctTokenIndexes(
            tokenSeedIn,
            tokenSeedOut,
            tokens.length
        );

        // Keep swaps comfortably within safe bounds so these calls should not revert.
        uint256 maxAmountIn = balancesRaw[tokenIndexIn] / 100; // 1% of balance
        if (maxAmountIn < MIN_SWAP_AMOUNT) return;
        amountIn = _boundValue(amountIn, MIN_SWAP_AMOUNT, maxAmountIn);

        _swapExactInAndAssert(tokens[tokenIndexIn], tokens[tokenIndexOut], amountIn);
    }

    /**
     * @notice Fuzz: Swap exact out
     * @param amountOut Amount to receive
     * @param tokenSeedIn Seed used to pick tokenIn
     * @param tokenSeedOut Seed used to pick tokenOut (must differ from tokenIn)
     */
    function swapExactOut(uint256 amountOut, uint256 tokenSeedIn, uint256 tokenSeedOut) external {
        (IERC20[] memory tokens, uint256[] memory balancesRaw, ) = _getPoolData();
        if (tokens.length < 2) return;

        (uint256 tokenIndexIn, uint256 tokenIndexOut) = _pickTwoDistinctTokenIndexes(
            tokenSeedIn,
            tokenSeedOut,
            tokens.length
        );

        // Keep swaps comfortably within safe bounds so these calls should not revert.
        uint256 maxAmountOut = balancesRaw[tokenIndexOut] / 100; // 1% of balance
        if (maxAmountOut < MIN_SWAP_AMOUNT) return;
        amountOut = _boundValue(amountOut, MIN_SWAP_AMOUNT, maxAmountOut);

        _swapExactOutAndAssert(tokens[tokenIndexIn], tokens[tokenIndexOut], amountOut);
    }

    /**
     * @notice Fuzz: Round trip swap (should never profit)
     * @param amountIn Initial amount to swap
     * @param startTokenIndex Starting token (0 or 1)
     */
    function roundTripSwap(uint256 amountIn, uint256 startTokenIndex) external {
        (IERC20[] memory tokens, uint256[] memory balancesRaw, ) = _getPoolData();
        if (tokens.length < 2) return;

        startTokenIndex = startTokenIndex % tokens.length;
        uint256 otherTokenIndex = (startTokenIndex + 1) % tokens.length;
        if (otherTokenIndex == startTokenIndex) return;

        // Keep round-trip swaps small so they should not revert.
        uint256 maxAmountIn = balancesRaw[startTokenIndex] / 200; // 0.5% of balance
        if (maxAmountIn < MIN_SWAP_AMOUNT) return;
        amountIn = _boundValue(amountIn, MIN_SWAP_AMOUNT, maxAmountIn);

        // Quote exact-in for the first leg to avoid reverts and keep it deterministic.
        uint256 quotedOut1 = router.querySwapSingleTokenExactIn(
            address(pool),
            tokens[startTokenIndex],
            tokens[otherTokenIndex],
            amountIn,
            alice,
            bytes("")
        );
        if (quotedOut1 == 0) return;

        medusa.prank(alice);
        uint256 amountOut1 = router.swapSingleTokenExactIn(
            address(pool),
            tokens[startTokenIndex],
            tokens[otherTokenIndex],
            amountIn,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        assert(amountOut1 == quotedOut1);

        // Quote and execute the second leg.
        uint256 quotedOut2 = router.querySwapSingleTokenExactIn(
            address(pool),
            tokens[otherTokenIndex],
            tokens[startTokenIndex],
            amountOut1,
            alice,
            bytes("")
        );
        if (quotedOut2 == 0) return;

        medusa.prank(alice);
        uint256 amountOut2 = router.swapSingleTokenExactIn(
            address(pool),
            tokens[otherTokenIndex],
            tokens[startTokenIndex],
            amountOut1,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        assert(amountOut2 == quotedOut2);

        // Should not profit from round trip (with small tolerance for rounding).
        if (amountOut2 > amountIn + 2) {
            roundTripProfitCount++;
            uint256 profit = amountOut2 - amountIn;
            if (profit > maxRoundTripProfit) maxRoundTripProfit = profit;
        }
        assert(amountOut2 <= amountIn + 2);
    }

    /**
     * @notice Fuzz: Multiple consecutive swaps
     * @param seed Random seed for swap parameters
     */
    function consecutiveSwaps(uint256 seed) external {
        uint256 numSwaps = (seed % 5) + 1; // 1-5 swaps

        (IERC20[] memory tokens, uint256[] memory balancesRaw, uint256[] memory balancesScaled18) = _getPoolData();
        if (tokens.length < 2) return;

        uint256 invariantBefore = StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balancesScaled18);

        for (uint256 i = 0; i < numSwaps; i++) {
            // Refresh balances so max bounds track the evolving state.
            (tokens, balancesRaw, ) = _getPoolData();

            (uint256 tokenIndexIn, uint256 tokenIndexOut) = _pickTwoDistinctTokenIndexes(
                seed + i,
                seed / (i + 1),
                tokens.length
            );

            uint256 maxAmountIn = balancesRaw[tokenIndexIn] / 200; // 0.5% of balance
            if (maxAmountIn < MIN_SWAP_AMOUNT) break;
            uint256 amountIn = _boundValue(seed + (i * 17), MIN_SWAP_AMOUNT, maxAmountIn);

            uint256 quotedOut = router.querySwapSingleTokenExactIn(
                address(pool),
                tokens[tokenIndexIn],
                tokens[tokenIndexOut],
                amountIn,
                alice,
                bytes("")
            );
            if (quotedOut == 0) break;

            medusa.prank(alice);
            uint256 amountOut = router.swapSingleTokenExactIn(
                address(pool),
                tokens[tokenIndexIn],
                tokens[tokenIndexOut],
                amountIn,
                0,
                type(uint256).max,
                false,
                bytes("")
            );
            swapCount++;
            assert(amountOut == quotedOut);

            (, , , uint256[] memory balancesScaled18AfterSwap) = vault.getPoolTokenInfo(address(pool));
            uint256 invariantAfterSwap = StableMath.computeInvariant(
                AMPLIFICATION_PARAMETER * AMP_PRECISION,
                balancesScaled18AfterSwap
            );
            uint256 tol = _invariantTolerance(invariantBefore);
            assert(invariantAfterSwap + tol >= invariantBefore);
            invariantBefore = invariantAfterSwap;
            if (invariantAfterSwap > lastKnownInvariant) lastKnownInvariant = invariantAfterSwap;
        }
    }

    /***************************************************************************
                              INVARIANT PROPERTIES
     ***************************************************************************/

    /**
     * @notice Property: Invariant should never decrease
     */
    function property_invariantNonDecreasing() external view returns (bool) {
        (, , , uint256[] memory balancesScaled18) = vault.getPoolTokenInfo(address(pool));

        try this.externalComputeInvariant(balancesScaled18) returns (uint256 currentInvariant) {
            uint256 tol = _invariantTolerance(lastKnownInvariant);
            return currentInvariant + tol >= lastKnownInvariant;
        } catch {
            // If computing the invariant doesn't converge, that's a real failure signal (not something to hide).
            return false;
        }
    }

    /**
     * @notice Property: No round trip profit
     */
    function property_noRoundTripProfit() external view returns (bool) {
        // Check that we haven't recorded any significant round-trip profits
        return maxRoundTripProfit <= 2; // Allow 2 wei tolerance
    }

    /***************************************************************************
                              HELPER FUNCTIONS
     ***************************************************************************/

    function _swapExactInAndAssert(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) internal {
        (, , , uint256[] memory balancesScaled18Before) = vault.getPoolTokenInfo(address(pool));
        uint256 invariantBefore = StableMath.computeInvariant(
            AMPLIFICATION_PARAMETER * AMP_PRECISION,
            balancesScaled18Before
        );

        uint256 quotedOut = _quoteExactInAndAssertRounding(tokenIn, tokenOut, amountIn);
        _executeSwapExactInAndAssertBalances(tokenIn, tokenOut, amountIn, quotedOut);
        _assertInvariantNonDecreasingFrom(invariantBefore);
    }

    function _quoteExactInAndAssertRounding(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn
    ) internal returns (uint256 quotedOut) {
        // Query first to avoid "sometimes revert" fuzz lottery and to assert quote==execution.
        quotedOut = router.querySwapSingleTokenExactIn(
            address(pool),
            tokenIn,
            tokenOut,
            amountIn,
            alice,
            bytes("")
        );
        assert(quotedOut > 0);

        // Rounding-favors-pool check on the same starting state:
        // to receive `quotedOut` via EXACT_OUT, required input should be >= `amountIn` (mod tiny tolerance).
        uint256 quotedInForQuotedOut = router.querySwapSingleTokenExactOut(
            address(pool),
            tokenIn,
            tokenOut,
            quotedOut,
            alice,
            bytes("")
        );
        assert(quotedInForQuotedOut + 2 >= amountIn);
    }

    function _executeSwapExactInAndAssertBalances(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountIn,
        uint256 quotedOut
    ) internal {
        uint256 aliceInBefore = tokenIn.balanceOf(alice);
        uint256 aliceOutBefore = tokenOut.balanceOf(alice);

        medusa.prank(alice);
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(pool),
            tokenIn,
            tokenOut,
            amountIn,
            0,
            type(uint256).max,
            false,
            bytes("")
        );

        swapCount++;
        assert(amountOut == quotedOut);
        assert(tokenIn.balanceOf(alice) == aliceInBefore - amountIn);
        assert(tokenOut.balanceOf(alice) == aliceOutBefore + amountOut);
    }

    function _assertInvariantNonDecreasingFrom(uint256 invariantBefore) internal {
        (, , , uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(address(pool));
        uint256 invariantAfter = StableMath.computeInvariant(
            AMPLIFICATION_PARAMETER * AMP_PRECISION,
            balancesScaled18After
        );

        uint256 tol = _invariantTolerance(invariantBefore);
        assert(invariantAfter + tol >= invariantBefore);
        if (invariantAfter > lastKnownInvariant) lastKnownInvariant = invariantAfter;
    }

    function _swapExactOutAndAssert(IERC20 tokenIn, IERC20 tokenOut, uint256 amountOut) internal {
        (, , , uint256[] memory balancesScaled18Before) = vault.getPoolTokenInfo(address(pool));
        uint256 invariantBefore = StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balancesScaled18Before);

        // Query first so we can assert quote==execution.
        uint256 quotedIn = router.querySwapSingleTokenExactOut(
            address(pool),
            tokenIn,
            tokenOut,
            amountOut,
            alice,
            bytes("")
        );
        assert(quotedIn > 0);

        uint256 aliceInBefore = tokenIn.balanceOf(alice);
        uint256 aliceOutBefore = tokenOut.balanceOf(alice);

        medusa.prank(alice);
        uint256 amountIn = router.swapSingleTokenExactOut(
            address(pool),
            tokenIn,
            tokenOut,
            amountOut,
            type(uint256).max,
            type(uint256).max,
            false,
            bytes("")
        );

        swapCount++;
        assert(amountIn == quotedIn);
        assert(tokenIn.balanceOf(alice) == aliceInBefore - amountIn);
        assert(tokenOut.balanceOf(alice) == aliceOutBefore + amountOut);

        (, , , uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(address(pool));
        uint256 invariantAfter = StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balancesScaled18After);

        uint256 tol = _invariantTolerance(invariantBefore);
        assert(invariantAfter + tol >= invariantBefore);
        if (invariantAfter > lastKnownInvariant) lastKnownInvariant = invariantAfter;
    }

    function _getPoolData()
        internal
        view
        returns (IERC20[] memory tokens, uint256[] memory balancesRaw, uint256[] memory balancesScaled18)
    {
        (tokens, , balancesRaw, balancesScaled18) = vault.getPoolTokenInfo(address(pool));
    }

    function _pickTwoDistinctTokenIndexes(
        uint256 seedIn,
        uint256 seedOut,
        uint256 length
    ) internal pure returns (uint256 tokenIndexIn, uint256 tokenIndexOut) {
        tokenIndexIn = seedIn % length;
        tokenIndexOut = seedOut % (length - 1);
        if (tokenIndexOut >= tokenIndexIn) tokenIndexOut++;
    }

    function _invariantTolerance(uint256 invariant) internal pure returns (uint256 tol) {
        tol = invariant / 1e12;
        if (tol < MIN_INVARIANT_TOL) tol = MIN_INVARIANT_TOL;
    }

    function _boundValue(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function externalComputeInvariant(uint256[] memory balancesScaled18) external pure returns (uint256) {
        return StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balancesScaled18);
    }
}
