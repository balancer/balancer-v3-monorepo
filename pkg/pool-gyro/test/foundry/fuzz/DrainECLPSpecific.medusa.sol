// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { GyroECLPPoolFactory } from "../../../contracts/GyroECLPPoolFactory.sol";
import { GyroECLPMath } from "../../../contracts/lib/GyroECLPMath.sol";

/**
 * @title Stateful drain campaign for one pinned E-CLP configuration
 * @notice Searches for a sequence of pool operations that extracts value from the E-CLP.
 * @dev The configuration is the one pinned by `test/foundry/utils/BaseECLPSpecificTest.sol`: a 45 degree rotation
 * with `lambda = 300`, a price interval of `[0.980392156862745098, 1.000000630371029932]` and a swap fee of 0.01%.
 * It is deliberately *not* the mainnet fixture used by the other campaigns in this folder.
 *
 * The pool is initialized at a spot price of exactly 1. Because 1 sits only ~6.3e-7 below `beta`, the pool holds
 * ~99.99% of its value in token 1 and only ~0.00995% in token 0, so the two sides are ~9999x apart. Operation
 * bounds are therefore expressed against the *opposite* balance (the side that has to pay out), which is the real
 * headroom in every direction; bounding against the input balance would make almost every call revert.
 *
 * Properties (see the `property_*` functions):
 *  - The BPT rate (invariant / total supply) never decreases. This is the anti-drain property.
 *  - Atomic round trips (swap out and back, add then remove) never return more than they consumed.
 *  - The Vault is solvent: its real token balances cover the balances it accounts to the pool.
 *  - BPT total supply equals the sum of all balances that can hold it.
 *  - The spot price stays inside `[alpha, beta]`.
 */
contract DrainECLPSpecificMedusa is BaseMedusaTest {
    using FixedPoint for uint256;

    /// @dev Snapshot of everything an operation needs to verify its own deltas afterwards.
    struct Snapshot {
        uint256 pool0;
        uint256 pool1;
        uint256 actor0;
        uint256 actor1;
        uint256 actorBpt;
        uint256 totalSupply;
    }

    // Price interval [0.980392156862745098, 1.000000630371029932], 45 degree rotation, stretch factor 300.
    int256 internal constant PARAMS_ALPHA = 980392156862745098;
    int256 internal constant PARAMS_BETA = 1000000630371029932;
    int256 internal constant PARAMS_C = 707106781186547524;
    int256 internal constant PARAMS_S = 707106781186547524;
    int256 internal constant PARAMS_LAMBDA = 300000000000000000000;

    // Derived params (38 decimals) computed offchain in exact integer arithmetic for the params above.
    int256 internal constant TAU_ALPHA_X = -94773130622350963813402481283118800045;
    int256 internal constant TAU_ALPHA_Y = 31906953976191491086066439875451340751;
    int256 internal constant TAU_BETA_X = 9455562426453687808195961460162005;
    int256 internal constant TAU_BETA_Y = 99999999552961694941282054418046780509;
    int256 internal constant DERIVED_U = 47391293092388708696875030401893946255;
    int256 internal constant DERIVED_V = 65953476764576592938898894892506970790;
    int256 internal constant DERIVED_W = 34046522788385101889007253374479656388;
    int256 internal constant DERIVED_Z = -47381837529962255009077554770064379269;
    int256 internal constant DERIVED_DSQ = 99999999999999999886624093342106115200;

    uint256 internal constant SWAP_FEE_PERCENTAGE = 1e14; // 0.01%

    /// @dev Ratio `balance1 / balance0` that puts this configuration at a spot price of exactly 1.
    uint256 internal constant PRICE_ONE_BALANCE_RATIO = 9998999999994488463412;

    // Initial liquidity. Token 1 ends up ~9999x larger, so the sum stays around 1e27, comfortably below the 1e34
    // cap enforced by `GyroECLPMath._MAX_BALANCES` even after the campaign grows the pool.
    uint256 internal constant INITIAL_BALANCE0 = 1e23;

    // Smallest amount that is worth trading or redeeming; both tokens have 18 decimals in `BaseMedusaTest`.
    uint256 internal constant MIN_AMOUNT = 1e12;

    // Every operation is sized against the balance that has to pay it out, which is the true headroom here.
    uint256 internal constant MAX_SWAP_RATIO = 20e16; // 20% of the output-side balance
    uint256 internal constant MAX_ROUND_TRIP_RATIO = 5e16; // 5% of the output-side balance, per leg
    uint256 internal constant MAX_ADD_UNBALANCED_RATIO = 20e16; // 20% of the *opposite* balance
    uint256 internal constant MAX_ADD_PROPORTIONAL_RATIO = 25e16; // 25% of total supply
    uint256 internal constant MAX_REMOVE_PROPORTIONAL_RATIO = 50e16; // 50% of the actor's BPT
    uint256 internal constant MAX_REMOVE_SINGLE_RATIO = 20e16; // 20% of the supply backed by that token

    // Liveness check: the LP redeems this share of its BPT, and only when the pool is not degenerate.
    uint256 internal constant LIVENESS_BPT_RATIO = 1e15; // 0.1% of the LP's BPT
    uint256 internal constant LIVENESS_MIN_BALANCE = 1e12;

    uint256 internal _initialBptRate;

    IERC20 internal _token0;
    IERC20 internal _token1;

    constructor() BaseMedusaTest() {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));
        _token0 = tokens[0];
        _token1 = tokens[1];

        _initialBptRate = vault.getBptRate(address(pool));
    }

    /// @notice Drives the campaign towards the lowest reachable BPT rate.
    function optimize_currentBptRate() public view returns (int256) {
        return -int256(vault.getBptRate(address(pool)));
    }

    /**
     * @notice The BPT rate must never fall below its value right after initialization.
     * @dev The bare `>=` form does *not* hold, and the single call below is enough to break it:
     *
     *   removeLiquidityProportional(bptIn = 2040726492856729865449737) by the LP
     *
     * from the initial state (balances `[1e23, 999899999999448846341200000]`, total supply and invariant both
     * `4985473881089467968896507`, so the initial rate is exactly `1e18`). Afterwards the balances are
     * `[59066549308432581104987, 590606426534691831021123376]`, the total supply is `2944747388232738103446770`
     * and the recomputed (round-down) invariant is `2944747388232738103446769` — exactly one wei short, which
     * rounds the rate to `999999999999999999`.
     *
     * This is the invariant being recomputed from scratch on the reduced balances, not value leaving the pool:
     * the loss is one wei out of ~2.9e24, i.e. ~3.4e-25 in relative terms, and it cannot be repeated for profit
     * because the burn is what pays for it. The tolerance is therefore pinned at exactly one wei, so any drop
     * larger than that — in particular anything that accumulates across a sequence — still fails the campaign.
     */
    function property_currentBptRate() public view returns (bool) {
        return vault.getBptRate(address(pool)) + 1 >= _initialBptRate;
    }

    /// @notice The Vault must actually hold every token it accounts to the pool.
    function property_vaultSolvent() public view returns (bool) {
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));

        return
            tokens[0].balanceOf(address(vault)) >= balancesRaw[0] &&
            tokens[1].balanceOf(address(vault)) >= balancesRaw[1];
    }

    /// @notice BPT total supply must equal the sum of every balance that can hold it.
    function property_totalSupplyMatchesBalances() public view returns (bool) {
        IERC20 bpt = IERC20(address(pool));
        uint256 sum = bpt.balanceOf(address(0)) + bpt.balanceOf(alice) + bpt.balanceOf(bob) + bpt.balanceOf(lp);

        return bpt.totalSupply() == sum;
    }

    /// @notice The spot price must stay inside the configured price interval.
    function property_spotPriceWithinBounds() public view returns (bool) {
        (, , , uint256[] memory balancesLiveScaled18) = vault.getPoolTokenInfo(address(pool));
        uint256 spotPrice = _computeSpotPrice(balancesLiveScaled18);

        return spotPrice >= uint256(PARAMS_ALPHA) && spotPrice <= uint256(PARAMS_BETA);
    }

    /// @notice Override to create the pinned E-CLP pool.
    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        GyroECLPPoolFactory factory = new GyroECLPPoolFactory(vault, 365 days, "", "");

        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);

        IGyroECLPPool.EclpParams memory eclpParams = IGyroECLPPool.EclpParams({
            alpha: PARAMS_ALPHA,
            beta: PARAMS_BETA,
            c: PARAMS_C,
            s: PARAMS_S,
            lambda: PARAMS_LAMBDA
        });

        IGyroECLPPool.DerivedEclpParams memory derivedParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2(TAU_ALPHA_X, TAU_ALPHA_Y),
            tauBeta: IGyroECLPPool.Vector2(TAU_BETA_X, TAU_BETA_Y),
            u: DERIVED_U,
            v: DERIVED_V,
            w: DERIVED_W,
            z: DERIVED_Z,
            dSq: DERIVED_DSQ
        });

        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Gyro E-CLP Pool",
            "ECLP-POOL",
            vault.buildTokenConfig(tokens, rateProviders),
            eclpParams,
            derivedParams,
            roleAccounts,
            SWAP_FEE_PERCENTAGE,
            address(0),
            false,
            false,
            bytes32("")
        );

        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    /// @notice Override to use 2 tokens, seeded at a spot price of exactly 1.
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
        initialBalances[0] = INITIAL_BALANCE0;
        initialBalances[1] = INITIAL_BALANCE0.mulDown(PRICE_ONE_BALANCE_RATIO);
    }

    /***************************************************************************
                                   Fuzz Functions
    ***************************************************************************/

    /// @notice Exact-in swap in either direction, by any actor.
    function swapExactIn(uint256 amountIn, uint256 direction, uint256 actorSeed) external {
        (uint256 indexIn, uint256 indexOut) = _direction(direction);

        uint256 maxIn = _poolBalance(indexOut).mulDown(MAX_SWAP_RATIO);
        if (maxIn < MIN_AMOUNT) return;

        _swapExactIn(_actor(actorSeed), indexIn, indexOut, _boundLocal(amountIn, MIN_AMOUNT, maxIn));
    }

    /// @notice Exact-out swap in either direction, by any actor.
    function swapExactOut(uint256 amountOut, uint256 direction, uint256 actorSeed) external {
        (uint256 indexIn, uint256 indexOut) = _direction(direction);

        uint256 maxOut = _poolBalance(indexOut).mulDown(MAX_SWAP_RATIO);
        if (maxOut < MIN_AMOUNT) return;

        _swapExactOut(_actor(actorSeed), indexIn, indexOut, _boundLocal(amountOut, MIN_AMOUNT, maxOut));
    }

    /**
     * @notice Swap out and straight back in, in either direction, by any actor.
     * @dev A round trip must never leave the actor with more of the input token than it started with.
     */
    function roundTripSwap(uint256 amountIn, uint256 direction, uint256 actorSeed) external {
        (uint256 indexIn, uint256 indexOut) = _direction(direction);
        address actor = _actor(actorSeed);

        uint256 maxIn = _poolBalance(indexOut).mulDown(MAX_ROUND_TRIP_RATIO);
        if (maxIn < MIN_AMOUNT) return;

        uint256 startIn = _tokenAt(indexIn).balanceOf(actor);

        uint256 intermediate = _swapExactIn(actor, indexIn, indexOut, _boundLocal(amountIn, MIN_AMOUNT, maxIn));
        _swapExactIn(actor, indexOut, indexIn, intermediate);

        assert(_tokenAt(indexIn).balanceOf(actor) <= startIn);
    }

    /// @notice Add liquidity proportionally, by any actor.
    function addLiquidityProportional(uint256 bptSeed, uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        Snapshot memory snapshot = _snapshot(actor);

        uint256 maxBptOut = snapshot.totalSupply.mulDown(MAX_ADD_PROPORTIONAL_RATIO);
        if (maxBptOut < MIN_AMOUNT) return;
        uint256 exactBptOut = _boundLocal(bptSeed, MIN_AMOUNT, maxBptOut);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = snapshot.actor0;
        maxAmountsIn[1] = snapshot.actor1;

        medusa.prank(actor);
        uint256[] memory amountsIn = router.addLiquidityProportional(
            address(pool),
            maxAmountsIn,
            exactBptOut,
            false,
            bytes("")
        );

        assert(IERC20(address(pool)).balanceOf(actor) == snapshot.actorBpt + exactBptOut);
        assert(IERC20(address(pool)).totalSupply() == snapshot.totalSupply + exactBptOut);
        _assertPoolBalances(snapshot.pool0 + amountsIn[0], snapshot.pool1 + amountsIn[1]);
    }

    /**
     * @notice Add liquidity unbalanced, by any actor.
     * @dev Each side is capped against the *opposite* balance: adding token 1 alone can at most buy out the token 0
     * side of the pool, and vice versa. Capping against the own balance would let token 1 adds blow through `beta`.
     */
    function addLiquidityUnbalanced(uint256 amount0Seed, uint256 amount1Seed, uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        Snapshot memory snapshot = _snapshot(actor);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = _boundLocal(amount0Seed, 0, snapshot.pool1.mulDown(MAX_ADD_UNBALANCED_RATIO));
        exactAmountsIn[1] = _boundLocal(amount1Seed, 0, snapshot.pool0.mulDown(MAX_ADD_UNBALANCED_RATIO));
        if (exactAmountsIn[0] == 0 && exactAmountsIn[1] == 0) return;

        medusa.prank(actor);
        uint256 bptOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));

        assert(_token0.balanceOf(actor) == snapshot.actor0 - exactAmountsIn[0]);
        assert(_token1.balanceOf(actor) == snapshot.actor1 - exactAmountsIn[1]);
        assert(IERC20(address(pool)).totalSupply() == snapshot.totalSupply + bptOut);
        _assertPoolBalances(snapshot.pool0 + exactAmountsIn[0], snapshot.pool1 + exactAmountsIn[1]);
    }

    /// @notice Remove liquidity proportionally, by any actor holding BPT.
    function removeLiquidityProportional(uint256 bptSeed, uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        Snapshot memory snapshot = _snapshot(actor);

        uint256 maxBptIn = snapshot.actorBpt.mulDown(MAX_REMOVE_PROPORTIONAL_RATIO);
        if (maxBptIn < MIN_AMOUNT) return;
        uint256 exactBptIn = _boundLocal(bptSeed, MIN_AMOUNT, maxBptIn);

        medusa.prank(actor);
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            exactBptIn,
            new uint256[](2),
            false,
            bytes("")
        );

        assert(IERC20(address(pool)).balanceOf(actor) == snapshot.actorBpt - exactBptIn);
        assert(IERC20(address(pool)).totalSupply() == snapshot.totalSupply - exactBptIn);
        assert(_token0.balanceOf(actor) == snapshot.actor0 + amountsOut[0]);
        assert(_token1.balanceOf(actor) == snapshot.actor1 + amountsOut[1]);
        _assertPoolBalances(snapshot.pool0 - amountsOut[0], snapshot.pool1 - amountsOut[1]);
    }

    /**
     * @notice Remove liquidity into a single token, by any actor holding BPT.
     * @dev The BPT burned is capped by the share of the pool's value that the chosen token actually holds; with
     * ~99.99% of the value on the token 1 side, a token 0 exit can only ever redeem a sliver of the supply.
     */
    function removeLiquiditySingleTokenExactIn(uint256 bptSeed, uint256 tokenIndex, uint256 actorSeed) external {
        tokenIndex = tokenIndex % 2;
        address actor = _actor(actorSeed);
        Snapshot memory snapshot = _snapshot(actor);

        uint256 exactBptIn;
        {
            uint256 poolBalance = tokenIndex == 0 ? snapshot.pool0 : snapshot.pool1;
            uint256 valueShare = poolBalance.divDown(snapshot.pool0 + snapshot.pool1);
            uint256 maxBptIn = snapshot.totalSupply.mulDown(valueShare).mulDown(MAX_REMOVE_SINGLE_RATIO);
            if (snapshot.actorBpt < maxBptIn) maxBptIn = snapshot.actorBpt;
            if (maxBptIn < MIN_AMOUNT) return;
            exactBptIn = _boundLocal(bptSeed, MIN_AMOUNT, maxBptIn);
        }

        medusa.prank(actor);
        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            exactBptIn,
            _tokenAt(tokenIndex),
            0,
            false,
            bytes("")
        );
        assert(amountOut > 0);

        assert(IERC20(address(pool)).balanceOf(actor) == snapshot.actorBpt - exactBptIn);
        assert(IERC20(address(pool)).totalSupply() == snapshot.totalSupply - exactBptIn);
        assert(_poolBalance(tokenIndex) == (tokenIndex == 0 ? snapshot.pool0 : snapshot.pool1) - amountOut);
        assert(_poolBalance(1 - tokenIndex) == (tokenIndex == 0 ? snapshot.pool1 : snapshot.pool0));
    }

    /**
     * @notice Add liquidity proportionally and immediately take it back out, by any actor.
     * @dev An atomic round trip must never return more of either token than it consumed.
     *
     * Note this is deliberately checked *atomically* rather than as a standing per-actor property. A global
     * "no actor ever ends up with more of both tokens" property is not an invariant of the pool: one actor can
     * move the price with a large swap and a second actor can then legitimately end up ahead in both tokens, and
     * an LP legitimately accrues swap fees. Only value conservation across the whole pool is invariant, and that
     * is what `property_currentBptRate` measures.
     */
    function addRemoveLiquidityRoundTrip(uint256 bptSeed, uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        Snapshot memory snapshot = _snapshot(actor);

        uint256 maxBpt = snapshot.totalSupply.mulDown(MAX_ADD_PROPORTIONAL_RATIO);
        if (maxBpt < MIN_AMOUNT) return;
        uint256 exactBpt = _boundLocal(bptSeed, MIN_AMOUNT, maxBpt);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = snapshot.actor0;
        maxAmountsIn[1] = snapshot.actor1;

        medusa.prank(actor);
        router.addLiquidityProportional(address(pool), maxAmountsIn, exactBpt, false, bytes(""));

        medusa.prank(actor);
        router.removeLiquidityProportional(address(pool), exactBpt, new uint256[](2), false, bytes(""));

        assert(_token0.balanceOf(actor) <= snapshot.actor0);
        assert(_token1.balanceOf(actor) <= snapshot.actor1);
        assert(IERC20(address(pool)).balanceOf(actor) == snapshot.actorBpt);
    }

    /**
     * @notice Liveness: a proportional exit by the LP must never revert, whatever the pool state.
     * @dev Proportional exits do not move the price, so no reachable state may lock an LP out of one. The pool has
     * to be non-degenerate for the redeemed amounts to round to something nonzero, hence the balance guard.
     */
    function lpCanAlwaysExitProportionally() external {
        if (_poolBalance(0) < LIVENESS_MIN_BALANCE || _poolBalance(1) < LIVENESS_MIN_BALANCE) return;

        uint256 exactBptIn = IERC20(address(pool)).balanceOf(lp).mulDown(LIVENESS_BPT_RATIO);
        if (exactBptIn < MIN_AMOUNT) return;

        medusa.prank(lp);
        try router.removeLiquidityProportional(address(pool), exactBptIn, new uint256[](2), false, bytes("")) returns (
            uint256[] memory amountsOut
        ) {
            assert(amountsOut[0] > 0 && amountsOut[1] > 0);
        } catch {
            // A proportional exit from a non-degenerate pool must always succeed.
            assert(false);
        }
    }

    /***************************************************************************
                                  Helper Functions
    ***************************************************************************/

    function _swapExactIn(
        address actor,
        uint256 indexIn,
        uint256 indexOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        Snapshot memory snapshot = _snapshot(actor);

        medusa.prank(actor);
        amountOut = router.swapSingleTokenExactIn(
            address(pool),
            _tokenAt(indexIn),
            _tokenAt(indexOut),
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        assert(amountOut > 0);

        _assertSwapDeltas(actor, snapshot, indexIn, indexOut, amountIn, amountOut);
    }

    function _swapExactOut(
        address actor,
        uint256 indexIn,
        uint256 indexOut,
        uint256 amountOut
    ) internal returns (uint256 amountIn) {
        Snapshot memory snapshot = _snapshot(actor);

        medusa.prank(actor);
        amountIn = router.swapSingleTokenExactOut(
            address(pool),
            _tokenAt(indexIn),
            _tokenAt(indexOut),
            amountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
        assert(amountIn > 0);

        _assertSwapDeltas(actor, snapshot, indexIn, indexOut, amountIn, amountOut);
    }

    /// @dev Both the actor's and the pool's balances must move by exactly the amounts the Router reported.
    function _assertSwapDeltas(
        address actor,
        Snapshot memory snapshot,
        uint256 indexIn,
        uint256 indexOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal view {
        (uint256 actorInBefore, uint256 actorOutBefore) = indexIn == 0
            ? (snapshot.actor0, snapshot.actor1)
            : (snapshot.actor1, snapshot.actor0);

        assert(_tokenAt(indexIn).balanceOf(actor) == actorInBefore - amountIn);
        assert(_tokenAt(indexOut).balanceOf(actor) == actorOutBefore + amountOut);

        (uint256 expected0, uint256 expected1) = indexIn == 0
            ? (snapshot.pool0 + amountIn, snapshot.pool1 - amountOut)
            : (snapshot.pool0 - amountOut, snapshot.pool1 + amountIn);

        _assertPoolBalances(expected0, expected1);
    }

    function _assertPoolBalances(uint256 expected0, uint256 expected1) internal view {
        assert(_poolBalance(0) == expected0);
        assert(_poolBalance(1) == expected1);
    }

    function _snapshot(address actor) internal view returns (Snapshot memory snapshot) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));

        snapshot.pool0 = balancesRaw[0];
        snapshot.pool1 = balancesRaw[1];
        snapshot.actor0 = _token0.balanceOf(actor);
        snapshot.actor1 = _token1.balanceOf(actor);
        snapshot.actorBpt = IERC20(address(pool)).balanceOf(actor);
        snapshot.totalSupply = IERC20(address(pool)).totalSupply();
    }

    function _computeSpotPrice(uint256[] memory balancesScaled18) internal pure returns (uint256) {
        IGyroECLPPool.EclpParams memory params = IGyroECLPPool.EclpParams({
            alpha: PARAMS_ALPHA,
            beta: PARAMS_BETA,
            c: PARAMS_C,
            s: PARAMS_S,
            lambda: PARAMS_LAMBDA
        });

        IGyroECLPPool.DerivedEclpParams memory derivedParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2(TAU_ALPHA_X, TAU_ALPHA_Y),
            tauBeta: IGyroECLPPool.Vector2(TAU_BETA_X, TAU_BETA_Y),
            u: DERIVED_U,
            v: DERIVED_V,
            w: DERIVED_W,
            z: DERIVED_Z,
            dSq: DERIVED_DSQ
        });

        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(balancesScaled18, params, derivedParams);

        return GyroECLPMath.computePrice(balancesScaled18, params, a, b);
    }

    function _poolBalance(uint256 index) internal view returns (uint256) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        return balancesRaw[index];
    }

    function _tokenAt(uint256 index) internal view returns (IERC20) {
        return index == 0 ? _token0 : _token1;
    }

    function _actor(uint256 seed) internal view returns (address) {
        uint256 index = seed % 3;
        if (index == 0) return alice;
        if (index == 1) return bob;
        return lp;
    }

    function _direction(uint256 seed) internal pure returns (uint256 indexIn, uint256 indexOut) {
        return (seed & 1) == 0 ? (uint256(0), uint256(1)) : (uint256(1), uint256(0));
    }

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
}
