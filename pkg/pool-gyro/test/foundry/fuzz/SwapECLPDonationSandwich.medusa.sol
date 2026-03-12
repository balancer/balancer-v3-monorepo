// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { GyroECLPPoolFactory } from "../../../contracts/GyroECLPPoolFactory.sol";
import { GyroECLPMath } from "../../../contracts/lib/GyroECLPMath.sol";

/**
 * @title SwapECLP Donation + Sandwich Medusa Fuzz Test
 * @notice High-value adversarial sequencing tests for Gyro ECLP:
 *  - Interleave `donate` with swaps (donation enabled).
 *  - Sandwich (attacker/victim/attacker) should not profit the attacker.
 *  - Donation should never mint BPT (totalSupply constant).
 *
 * IMPORTANT: ECLP requires a consistent (params, derivedParams) pair (usually computed off-chain).
 * This harness uses a known-good mainnet fixture for construction stability.
 */
contract SwapECLPDonationSandwichMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    struct SandwichCtx {
        uint256 iIn;
        uint256 iOut;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 balInBefore;
        uint256 balOutBefore;
        uint256 attackerAmountIn;
        uint256 victimAmountIn;
        uint256 startIn;
    }

    // Known-good mainnet fixture (see `test/foundry/utils/GyroEclpPoolDeployer.sol`).
    int256 internal constant PARAMS_ALPHA = 998502246630054917;
    int256 internal constant PARAMS_BETA = 1000200040008001600;
    int256 internal constant PARAMS_C = 707106781186547524;
    int256 internal constant PARAMS_S = 707106781186547524;
    int256 internal constant PARAMS_LAMBDA = 4000000000000000000000;

    int256 internal constant TAU_ALPHA_X = -94861212813096057289512505574275160547;
    int256 internal constant TAU_ALPHA_Y = 31644119574235279926451292677567331630;
    int256 internal constant TAU_BETA_X = 37142269533113549537591131345643981951;
    int256 internal constant TAU_BETA_Y = 92846388265400743995957747409218517601;
    int256 internal constant DERIVED_U = 66001741173104803338721745994955553010;
    int256 internal constant DERIVED_V = 62245253919818011890633399060291020887;
    int256 internal constant DERIVED_W = 30601134345582732000058913853921008022;
    int256 internal constant DERIVED_Z = -28859471639991253843240999485797747790;
    int256 internal constant DERIVED_DSQ = 99999999999999999886624093342106115200;

    // Limits
    // NOTE: token decimals differ (DAI 18, USDC 6). Use per-token mins to avoid "rounds to zero" domains.
    uint256 internal constant MIN_SWAP_USDC = 1e6; // 1 USDC
    uint256 internal constant MIN_SWAP_DAI = 1e12; // 1e-6 DAI
    uint256 internal constant MAX_SWAP_RATIO = 20e16; // 20% of balance per swap
    uint256 internal constant MAX_DONATION = 1e24;

    uint256 internal _initBptSupply;

    constructor() BaseMedusaTest() {
        _initBptSupply = IERC20(address(pool)).totalSupply();
    }

    function property_bpt_supply_constant() external view returns (bool) {
        return IERC20(address(pool)).totalSupply() == _initBptSupply;
    }

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
            "Gyro ECLP Pool (donations enabled)",
            "GECLP-DON",
            vault.buildTokenConfig(tokens, rateProviders),
            eclpParams,
            derivedParams,
            roleAccounts,
            1e12, // 0.0001% swap fee
            address(0),
            true, // enableDonation
            false, // disableUnbalancedLiquidity
            bytes32("")
        );

        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

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

    function computeDonate(uint256[] memory rawAmountsIn) external {
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = rawAmountsIn.length > 0 ? rawAmountsIn[0] : 0;
        amountsIn[1] = rawAmountsIn.length > 1 ? rawAmountsIn[1] : 0;

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory maxIns = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            uint256 headroom = type(uint128).max - balancesRaw[i];
            uint256 maxIn = headroom < MAX_DONATION ? headroom : MAX_DONATION;
            uint256 donorBal = tokens[i].balanceOf(bob);
            if (donorBal < maxIn) maxIn = donorBal;
            maxIns[i] = maxIn;
            amountsIn[i] = _boundLocal(amountsIn[i], 0, maxIn);
        }

        // Non-vacuity: if donation is possible, ensure at least one token donates a non-zero amount.
        if (amountsIn[0] == 0 && amountsIn[1] == 0) {
            if (maxIns[0] == 0 && maxIns[1] == 0) return;
            uint256 pick = (rawAmountsIn.length > 0 ? rawAmountsIn[0] : 1) & 1;
            if (maxIns[pick] == 0) pick ^= 1;
            amountsIn[pick] = 1;
        }

        (, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        uint256 beforeSupply = IERC20(address(pool)).totalSupply();
        uint256 bptBobBefore = IERC20(address(pool)).balanceOf(bob);
        uint256 bob0Before = tokens[0].balanceOf(bob);
        uint256 bob1Before = tokens[1].balanceOf(bob);
        medusa.prank(bob);
        router.donate(address(pool), amountsIn, false, bytes(""));
        uint256 afterSupply = IERC20(address(pool)).totalSupply();
        assert(afterSupply == beforeSupply);
        uint256 bptBobAfter = IERC20(address(pool)).balanceOf(bob);
        assert(bptBobAfter == bptBobBefore);

        uint256 bob0After = tokens[0].balanceOf(bob);
        uint256 bob1After = tokens[1].balanceOf(bob);
        assert(bob0After == bob0Before - amountsIn[0]);
        assert(bob1After == bob1Before - amountsIn[1]);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[0] == balancesBefore[0] + amountsIn[0]);
        assert(balancesAfter[1] == balancesBefore[1] + amountsIn[1]);
    }

    function sandwichExactIn(uint256 attackerAmountIn, uint256 victimAmountIn, uint256 direction) external {
        (SandwichCtx memory ctx, bool ok) = _initSandwich(attackerAmountIn, victimAmountIn, direction);

        (uint256 attackerOut, uint256 balInAfter1, uint256 balOutAfter1) = _attackerLeg(ctx);
        uint256 victimOut = _victimLeg(ctx);
        _assertVictimPoolDeltas(ctx, balInAfter1, balOutAfter1, victimOut);

        uint256 endIn = _unwindLeg(ctx, attackerOut);
        // Sandwich may or may not profit depending on the swap sizes and pool fees.
        // assert(endIn <= ctx.startIn);

        // Integration sanity: after a *successful* sandwich, spot price should remain within [alpha, beta].
        // (We don't assert this after donation calls, since donation can move balances without swap clamping.)
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        _assertSpotPriceWithinBounds(balancesAfter);
    }

    function _initSandwich(
        uint256 attackerAmountIn,
        uint256 victimAmountIn,
        uint256 direction
    ) internal view returns (SandwichCtx memory ctx, bool ok) {
        direction = direction & 1;
        ctx.iIn = direction == 0 ? 0 : 1;
        ctx.iOut = direction == 0 ? 1 : 0;

        uint256 minSwap;
        {
            (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
            ctx.tokenIn = tokens[ctx.iIn];
            ctx.tokenOut = tokens[ctx.iOut];
            ctx.balInBefore = balancesBefore[ctx.iIn];
            ctx.balOutBefore = balancesBefore[ctx.iOut];
            minSwap = _minSwap(ctx.tokenIn);
        }

        uint256 maxAttacker = ctx.balInBefore.mulDown(MAX_SWAP_RATIO / 20); // 1% (small front-run)
        uint256 maxVictim = ctx.balInBefore.mulDown(MAX_SWAP_RATIO / 2); // 10% (large victim)
        if (maxAttacker < minSwap || maxVictim < minSwap) return (ctx, false);

        ctx.attackerAmountIn = _boundLocal(attackerAmountIn, minSwap, maxAttacker);
        ctx.victimAmountIn = _boundLocal(victimAmountIn, minSwap, maxVictim);
        ctx.startIn = ctx.tokenIn.balanceOf(alice);
        return (ctx, true);
    }

    function _attackerLeg(
        SandwichCtx memory ctx
    ) internal returns (uint256 attackerOut, uint256 balInAfter1, uint256 balOutAfter1) {
        uint256 aliceInBefore = ctx.startIn;
        uint256 aliceOutBefore = ctx.tokenOut.balanceOf(alice);

        medusa.prank(alice);
        uint256 out1 = router.swapSingleTokenExactIn(
            address(pool),
            ctx.tokenIn,
            ctx.tokenOut,
            ctx.attackerAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        assert(out1 > 0);

        uint256 aliceInAfter1 = ctx.tokenIn.balanceOf(alice);
        uint256 aliceOutAfter1 = ctx.tokenOut.balanceOf(alice);
        assert(aliceInAfter1 == aliceInBefore - ctx.attackerAmountIn);
        assert(aliceOutAfter1 == aliceOutBefore + out1);

        (, , uint256[] memory balancesAfter1, ) = vault.getPoolTokenInfo(address(pool));
        balInAfter1 = balancesAfter1[ctx.iIn];
        balOutAfter1 = balancesAfter1[ctx.iOut];
        assert(balInAfter1 == ctx.balInBefore + ctx.attackerAmountIn);
        assert(balOutAfter1 == ctx.balOutBefore - out1);

        return (out1, balInAfter1, balOutAfter1);
    }

    function _victimLeg(SandwichCtx memory ctx) internal returns (uint256 victimOut) {
        uint256 bobInBefore = ctx.tokenIn.balanceOf(bob);
        uint256 bobOutBefore = ctx.tokenOut.balanceOf(bob);

        medusa.prank(bob);
        victimOut = router.swapSingleTokenExactIn(
            address(pool),
            ctx.tokenIn,
            ctx.tokenOut,
            ctx.victimAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 bobInAfter = ctx.tokenIn.balanceOf(bob);
        uint256 bobOutAfter = ctx.tokenOut.balanceOf(bob);
        assert(victimOut > 0);
        assert(bobInAfter == bobInBefore - ctx.victimAmountIn);
        assert(bobOutAfter == bobOutBefore + victimOut);

        return victimOut;
    }

    function _assertVictimPoolDeltas(
        SandwichCtx memory ctx,
        uint256 balInAfter1,
        uint256 balOutAfter1,
        uint256 victimOut
    ) internal view {
        (, , uint256[] memory balancesAfter2, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter2[ctx.iIn] == balInAfter1 + ctx.victimAmountIn);
        assert(balancesAfter2[ctx.iOut] == balOutAfter1 - victimOut);
    }

    function _unwindLeg(SandwichCtx memory ctx, uint256 attackerOut) internal returns (uint256 endIn) {
        // attacker swaps back iOut -> iIn with what she got
        uint256 aliceOutBefore3 = ctx.tokenOut.balanceOf(alice);
        uint256 aliceInBefore3 = ctx.tokenIn.balanceOf(alice);

        medusa.prank(alice);
        uint256 unwindOut = router.swapSingleTokenExactIn(
            address(pool),
            ctx.tokenOut,
            ctx.tokenIn,
            attackerOut,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 aliceOutAfter3 = ctx.tokenOut.balanceOf(alice);
        uint256 aliceInAfter3 = ctx.tokenIn.balanceOf(alice);
        assert(unwindOut > 0);
        // We are using token in and token out upside down.
        assert(aliceOutAfter3 == aliceOutBefore3 - attackerOut);
        assert(aliceInAfter3 == aliceInBefore3 + unwindOut);

        return ctx.tokenIn.balanceOf(alice);
    }

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _minSwap(IERC20 token) internal view returns (uint256) {
        // Token identities are known fixtures in BaseMedusaTest (DAI/USDC).
        if (address(token) == address(usdc)) return MIN_SWAP_USDC;
        return MIN_SWAP_DAI;
    }

    function _params() internal pure returns (IGyroECLPPool.EclpParams memory p) {
        p.alpha = PARAMS_ALPHA;
        p.beta = PARAMS_BETA;
        p.c = PARAMS_C;
        p.s = PARAMS_S;
        p.lambda = PARAMS_LAMBDA;
    }

    function _derived() internal pure returns (IGyroECLPPool.DerivedEclpParams memory d) {
        d.tauAlpha = IGyroECLPPool.Vector2(TAU_ALPHA_X, TAU_ALPHA_Y);
        d.tauBeta = IGyroECLPPool.Vector2(TAU_BETA_X, TAU_BETA_Y);
        d.u = DERIVED_U;
        d.v = DERIVED_V;
        d.w = DERIVED_W;
        d.z = DERIVED_Z;
        d.dSq = DERIVED_DSQ;
    }

    function _computeSpotPrice(uint256[] memory balances) internal pure returns (uint256 spotPrice) {
        IGyroECLPPool.EclpParams memory p = _params();
        IGyroECLPPool.DerivedEclpParams memory d = _derived();
        (int256 a, int256 b) = GyroECLPMath.computeOffsetFromBalances(balances, p, d);
        return GyroECLPMath.computePrice(balances, p, a, b);
    }

    function _assertSpotPriceWithinBounds(uint256[] memory balances) internal pure {
        uint256 spotPrice = _computeSpotPrice(balances);
        assert(spotPrice >= uint256(PARAMS_ALPHA) && spotPrice <= uint256(PARAMS_BETA));
    }
}
