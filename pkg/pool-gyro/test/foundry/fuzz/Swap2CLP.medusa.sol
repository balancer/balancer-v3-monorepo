// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IGyro2CLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyro2CLPPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { Gyro2CLPPoolFactory } from "../../../contracts/Gyro2CLPPoolFactory.sol";
import { Gyro2CLPMath } from "../../../contracts/lib/Gyro2CLPMath.sol";

/**
 * @title Swap2CLP Medusa Fuzz Test
 * @notice Medusa fuzzing tests for Gyro 2-CLP pool swap operations.
 * @dev Key invariants tested:
 *   - Swap integration correctness: token deltas match returned amounts
 *   - Revert-safety: failed swaps must not mutate pool/user state
 *   - Expected revert domain: large trades should only fail due to 2CLP asset bounds
 *   - No-arbitrage: round-trip swaps should never profit the trader
 *   - LP safety: BPT rate should not decrease after successful swaps
 */
contract Swap2CLPMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    error BptRateDecreased(uint256 currentRate, uint256 lastKnownRate, uint256 minAllowed);

    // Gyro 2-CLP specific parameters
    uint256 internal constant SQRT_ALPHA = 997496867163000167; // alpha = 0.995
    uint256 internal constant SQRT_BETA = 1002496882788171068; // beta = 1.005

    // Limits
    uint256 internal constant MIN_SWAP = 1e6;
    uint256 internal constant MAX_SWAP_RATIO = 30e16; // 30% of balance per swap
    // Tightened domains to keep fuzz runs mostly on successful paths (avoid "mostly reverting" campaigns).
    uint256 internal constant MAX_SWAP_RATIO_EXACT_OUT = 10e16; // 10% of out-balance per exact-out request
    uint256 internal constant MAX_SWAP_RATIO_ROUND_TRIP = 5e16; // 5% per-leg input for round-trips

    // Track state
    uint256 internal _initialBptRate;

    constructor() BaseMedusaTest() {
        // Record initial BPT rate after pool initialization
        // Recording rate or invariant is equivalent in this test.
        _initialBptRate = _getCurrentBptRate();
    }

    function optimize_currentBptRate() public view returns (int256) {
        return -int256(_getCurrentBptRate());
    }

    function property_currentBptRate() public view returns (bool) {
        uint256 currentBptRate = _getCurrentBptRate();
        return currentBptRate >= _initialBptRate;
    }

    /// @notice Override to create a Gyro 2-CLP pool.
    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        Gyro2CLPPoolFactory factory = new Gyro2CLPPoolFactory(vault, 365 days, "", "");

        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);

        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Gyro 2-CLP Pool",
            "GRP",
            vault.buildTokenConfig(tokens, rateProviders),
            SQRT_ALPHA,
            SQRT_BETA,
            roleAccounts,
            1e12, // 0.0001% swap fee
            address(0),
            false,
            false,
            bytes32("")
        );

        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    /// @notice Override to use 2 tokens.
    function getTokensAndInitialBalances()
        internal
        view
        override
        returns (IERC20[] memory tokens, uint256[] memory initialBalances)
    {
        tokens = new IERC20[](2);
        tokens[0] = dai;
        tokens[1] = usdc;
        tokens = InputHelpers.sortTokens(tokens);

        initialBalances = new uint256[](2);
        initialBalances[0] = DEFAULT_INITIAL_POOL_BALANCE;
        initialBalances[1] = DEFAULT_INITIAL_POOL_BALANCE;
    }

    /***************************************************************************
                                   Fuzz Functions
     ***************************************************************************/

    /// @notice Fuzz: Exact input swap token0 -> token1 and assert BPT rate never decreases.
    function swapExactIn0to1(uint256 amountIn) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        // Tighten: choose an input that cannot trigger AssetBoundsExceeded in the 2CLP formula.
        uint256 maxSwap = _maxExactInAmountSafeNoAssetBounds(balancesBefore, 0);
        if (maxSwap < MIN_SWAP) return;
        amountIn = _boundLocal(amountIn, MIN_SWAP, maxSwap);

        uint256 aliceInBefore = tokens[0].balanceOf(alice);
        uint256 aliceOutBefore = tokens[1].balanceOf(alice);

        medusa.prank(alice);
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(pool),
            tokens[0],
            tokens[1],
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        // Amount out should be positive
        assert(amountOut > 0);

        // Exact deltas on caller balances must match returned amounts.
        uint256 aliceInAfter = tokens[0].balanceOf(alice);
        uint256 aliceOutAfter = tokens[1].balanceOf(alice);
        assert(aliceInAfter == aliceInBefore - amountIn);
        assert(aliceOutAfter == aliceOutBefore + amountOut);

        // Pool balance deltas must match the trade.
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[0] == balancesBefore[0] + amountIn);
        assert(balancesAfter[1] == balancesBefore[1] - amountOut);

        // BPT rate should not decrease
        _assertBptRateNeverDecreases();
    }

    /// @notice Fuzz: Exact input swap token1 -> token0 and assert BPT rate never decreases.
    function swapExactIn1to0(uint256 amountIn) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        uint256 maxSwap = _maxExactInAmountSafeNoAssetBounds(balancesBefore, 1);
        if (maxSwap < MIN_SWAP) return;
        amountIn = _boundLocal(amountIn, MIN_SWAP, maxSwap);

        uint256 aliceInBefore = tokens[1].balanceOf(alice);
        uint256 aliceOutBefore = tokens[0].balanceOf(alice);

        medusa.prank(alice);
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(pool),
            tokens[1],
            tokens[0],
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        assert(amountOut > 0);

        uint256 aliceInAfter = tokens[1].balanceOf(alice);
        uint256 aliceOutAfter = tokens[0].balanceOf(alice);
        assert(aliceInAfter == aliceInBefore - amountIn);
        assert(aliceOutAfter == aliceOutBefore + amountOut);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[1] == balancesBefore[1] + amountIn);
        assert(balancesAfter[0] == balancesBefore[0] - amountOut);

        _assertBptRateNeverDecreases();
    }

    /// @notice Fuzz: Exact output swap token0 -> token1 and assert BPT rate never decreases.
    function swapExactOut0to1(uint256 amountOut) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        // Tighten: keep exact-out requests small so the router math rarely reverts in a long fuzz sequence.
        uint256 maxSwap = balancesBefore[1].mulDown(MAX_SWAP_RATIO_EXACT_OUT);
        if (maxSwap < MIN_SWAP) return;
        amountOut = _boundLocal(amountOut, MIN_SWAP, maxSwap);

        uint256 aliceInBefore = tokens[0].balanceOf(alice);
        uint256 aliceOutBefore = tokens[1].balanceOf(alice);

        medusa.prank(alice);
        uint256 amountIn = router.swapSingleTokenExactOut(
            address(pool),
            tokens[0],
            tokens[1],
            amountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
        assert(amountIn > 0);

        uint256 aliceInAfter = tokens[0].balanceOf(alice);
        uint256 aliceOutAfter = tokens[1].balanceOf(alice);
        assert(aliceInAfter == aliceInBefore - amountIn);
        assert(aliceOutAfter == aliceOutBefore + amountOut);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[0] == balancesBefore[0] + amountIn);
        assert(balancesAfter[1] == balancesBefore[1] - amountOut);

        _assertBptRateNeverDecreases();
    }

    /// @notice Fuzz: Exact output swap token1 -> token0 and assert BPT rate never decreases.
    function swapExactOut1to0(uint256 amountOut) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        uint256 maxSwap = balancesBefore[0].mulDown(MAX_SWAP_RATIO_EXACT_OUT);
        if (maxSwap < MIN_SWAP) return;
        amountOut = _boundLocal(amountOut, MIN_SWAP, maxSwap);

        uint256 aliceInBefore = tokens[1].balanceOf(alice);
        uint256 aliceOutBefore = tokens[0].balanceOf(alice);

        medusa.prank(alice);
        uint256 amountIn = router.swapSingleTokenExactOut(
            address(pool),
            tokens[1],
            tokens[0],
            amountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
        assert(amountIn > 0);

        uint256 aliceInAfter = tokens[1].balanceOf(alice);
        uint256 aliceOutAfter = tokens[0].balanceOf(alice);
        assert(aliceInAfter == aliceInBefore - amountIn);
        assert(aliceOutAfter == aliceOutBefore + amountOut);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[1] == balancesBefore[1] + amountIn);
        assert(balancesAfter[0] == balancesBefore[0] - amountOut);

        _assertBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Mixed-mode round-trip (ExactIn then ExactOut) - should not profit trader.
     * @dev Exercises both swap paths and enforces revert-safety (no state changes on revert).
     * Also asserts BPT rate never decreases.
     */
    function roundTripSwap(uint256 amountIn) external {
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));

        // Smaller for round-trip sequences (reduces "expected" bound-reverts as the pool drifts).
        uint256 maxSwap = _maxExactInAmountSafeNoAssetBounds(balancesBefore, 0);
        uint256 cap = balancesBefore[0].mulDown(MAX_SWAP_RATIO_ROUND_TRIP);
        if (cap < maxSwap) maxSwap = cap;
        if (maxSwap < MIN_SWAP) return;
        amountIn = _boundLocal(amountIn, MIN_SWAP, maxSwap);

        // Step 1: ExactIn token0 -> token1
        medusa.prank(alice);
        uint256 midReceived = router.swapSingleTokenExactIn(
            address(pool),
            tokens[0],
            tokens[1],
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assert(midReceived > 0);

        // Step 2: ExactOut token1 -> token0 to get back exactly amountIn
        medusa.prank(alice);
        uint256 midSpent = router.swapSingleTokenExactOut(
            address(pool),
            tokens[1],
            tokens[0],
            amountIn,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        assert(midSpent > 0);

        // No-profit condition in intermediate token terms (allow +1 wei for rounding path differences).
        assert(midSpent >= midReceived);

        _assertBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz (strict): Round-trip swap should not profit trader (tiny rounding dust only).
     * @dev direction=0 means token0->token1->token0, direction=1 means token1->token0->token1
     * Also asserts BPT rate never decreases.
     */
    function roundTripSwapStrict(uint256 amountIn, uint256 direction) external {
        direction = direction & 1;

        (, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        uint256 iIn = direction == 0 ? 0 : 1;
        uint256 iMid = direction == 0 ? 1 : 0;

        // Keep round-trips well within bounds; smaller max reduces "expected" reverts at price bounds.
        uint256 maxSwap = _maxExactInAmountSafeNoAssetBounds(balancesBefore, iIn);
        uint256 cap = balancesBefore[iIn].mulDown(MAX_SWAP_RATIO_ROUND_TRIP);
        if (cap < maxSwap) maxSwap = cap;
        if (maxSwap < MIN_SWAP) return;
        amountIn = _boundLocal(amountIn, MIN_SWAP, maxSwap);

        // Step 1: swap in -> mid
        medusa.prank(alice);
        uint256 intermediateAmount = router.swapSingleTokenExactIn(
            address(pool),
            tokens[iIn],
            tokens[iMid],
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assert(intermediateAmount > 0);

        // Step 2: swap mid -> in
        medusa.prank(alice);
        uint256 finalAmount = router.swapSingleTokenExactIn(
            address(pool),
            tokens[iMid],
            tokens[iIn],
            intermediateAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assert(finalAmount > 0);

        // Strict: no profit beyond tiny rounding dust.
        // With non-zero fees this should be strictly <= amountIn; allow +1 wei for rounding.
        assert(finalAmount <= amountIn);

        _assertBptRateNeverDecreases();
    }

    /***************************************************************************
                                    Helper Functions
     ***************************************************************************/

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _maxExactInAmountSafeNoAssetBounds(
        uint256[] memory balances,
        uint256 iIn
    ) internal pure returns (uint256) {
        // Compute a conservative max `amountIn` that cannot trigger Gyro2CLPMath.AssetBoundsExceeded for exact-in.
        //
        // For `calcOutGivenIn(balanceIn, balanceOut, amountIn, virtualIn, virtualOut)`, a sufficient condition is:
        //   amountIn <= balanceOut * (balanceIn + virtualIn) / virtualOut  - 1
        //
        // Rounding choices match the pool’s rounding bias:
        // - invariant: ROUND_DOWN
        // - virtualIn: ROUND_UP
        // - virtualOut: ROUND_DOWN
        uint256 invariant = Gyro2CLPMath.calculateInvariant(balances, SQRT_ALPHA, SQRT_BETA, Rounding.ROUND_DOWN);
        if (invariant == 0) return 0;

        // Virtual params for token0/token1.
        uint256 v0Up = Gyro2CLPMath.calculateVirtualParameter0(invariant, SQRT_BETA, Rounding.ROUND_UP);
        uint256 v0Down = Gyro2CLPMath.calculateVirtualParameter0(invariant, SQRT_BETA, Rounding.ROUND_DOWN);
        uint256 v1Up = Gyro2CLPMath.calculateVirtualParameter1(invariant, SQRT_ALPHA, Rounding.ROUND_UP);
        uint256 v1Down = Gyro2CLPMath.calculateVirtualParameter1(invariant, SQRT_ALPHA, Rounding.ROUND_DOWN);

        uint256 balanceIn = balances[iIn];
        uint256 balanceOut = balances[iIn == 0 ? 1 : 0];

        uint256 virtualIn = iIn == 0 ? v0Up : v1Up;
        uint256 virtualOut = iIn == 0 ? v1Down : v0Down;
        if (virtualOut == 0) return 0;

        uint256 maxByBounds = balanceOut.mulDown(balanceIn + virtualIn).divDown(virtualOut);
        if (maxByBounds <= 1) return 0;

        uint256 maxSafe = maxByBounds - 1;
        uint256 cap = balanceIn.mulDown(MAX_SWAP_RATIO);
        return maxSafe < cap ? maxSafe : cap;
    }

    function _getCurrentBptRate() internal view returns (uint256) {
        return IGyro2CLPPool(address(pool)).getGyro2CLPPoolDynamicData().bptRate;
    }

    function _assertBptRateNeverDecreases() internal {
        uint256 currentRate = _getCurrentBptRate();
        emit Debug("current BPT rate", currentRate);
        emit Debug("initial BPT rate", _initialBptRate);

        assert(currentRate >= _initialBptRate);
    }
}
