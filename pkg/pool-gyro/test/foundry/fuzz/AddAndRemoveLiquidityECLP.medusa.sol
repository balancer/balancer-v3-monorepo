// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-vault/contracts/BasePoolMath.sol";

import { GyroECLPPoolFactory } from "../../../contracts/GyroECLPPoolFactory.sol";
import { GyroECLPMath } from "../../../contracts/lib/GyroECLPMath.sol";

/**
 * @title AddAndRemoveLiquidityECLP Medusa Fuzz Test
 * @notice Medusa fuzzing tests for Gyro ECLP pool liquidity operations
 * @dev Key invariants tested:
 *   - BPT rate should never decrease after add/remove liquidity
 *   - Invariant ratio limits are respected (60% - 500%)
 *   - No tokens should be created or destroyed
 *   - Pool balances should remain within ECLP bounds
 */
contract AddAndRemoveLiquidityECLPMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant BPT_RATE_TOLERANCE = 100;
    uint256 internal maxObservedRateDrop = 0;

    error BptOutTooLow(uint256 bptOut, uint256 minBptOut);
    error ZeroAmountOut();
    error InvalidAmountsInLength(uint256 length);
    error ZeroAmountsIn();
    error BptRateDecreased(uint256 currentRate, uint256 lastKnownRate, uint256 minAllowed);
    error TotalSupplyDidNotDecrease(uint256 beforeSupply, uint256 afterSupply);
    error BptInInvalid(uint256 bptIn, uint256 lpBalance);
    error RevertedWithoutData();
    error UnexpectedRevertSelector(bytes4 selector);
    error PoolStateChangedOnRevert(bytes32 beforeHash, bytes32 afterHash);
    error TokenBalanceDidNotDecrease(address token, uint256 beforeBal, uint256 afterBal, uint256 expectedDelta);
    error TokenBalanceDidNotIncrease(address token, uint256 beforeBal, uint256 afterBal, uint256 expectedDelta);
    error PoolBalanceDidNotChangeByExpectedAmount(
        uint256 tokenIndex,
        uint256 beforeBal,
        uint256 afterBal,
        uint256 expectedDelta
    );

    // ECLP pools require a consistent (params, derivedParams) pair; derived params are typically computed off-chain.
    // These constants are a known-good mainnet fixture (see `test/foundry/utils/GyroEclpPoolDeployer.sol`).
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
    uint256 internal constant MIN_BPT_OUT = 1e6;
    uint256 internal constant MAX_AMOUNT_IN = 1e24;
    uint256 internal constant MIN_TRADE_AMOUNT = 1e6;

    // ECLP specific limits
    uint256 internal constant MIN_INVARIANT_RATIO = 60e16; // 60%
    uint256 internal constant MAX_INVARIANT_RATIO = 500e16; // 500%

    // Track invariant state
    uint256 internal lastKnownBptRate;
    uint256 internal initialBptRate;

    constructor() BaseMedusaTest() {
        // Record initial BPT rate
        uint256 totalSupply = IERC20(address(pool)).totalSupply();
        if (totalSupply > 0) {
            initialBptRate = vault.getBptRate(address(pool));
            lastKnownBptRate = initialBptRate;
        }
    }

    function optimize_currentBptRate() public view returns (int256) {
        return -int256(_getCurrentBptRate());
    }

    function property_currentBptRate() public view returns (bool) {
        uint256 currentBptRate = _getCurrentBptRate();
        return currentBptRate + 1 >= initialBptRate;
    }

    /**
     * @notice Override to create a Gyro ECLP pool
     */
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
            "Gyro ECLP Pool",
            "GECLP",
            vault.buildTokenConfig(tokens, rateProviders),
            eclpParams,
            derivedParams,
            roleAccounts,
            1e12, // 0.0001% swap fee
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

    /// @notice Override to use 2 tokens for ECLP.
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

    /// @notice Fuzz: Add liquidity proportionally.
    function addLiquidityProportional(uint256 amountIn) external {
        _saveLastKnownBptRate();

        amountIn = _boundAmount(amountIn);

        (IERC20[] memory tokens, , uint256[] memory balancesBefore, uint256[] memory balancesScaled18Before) = vault
            .getPoolTokenInfo(address(pool));
        uint256 alice0Before = tokens[0].balanceOf(alice);
        uint256 alice1Before = tokens[1].balanceOf(alice);
        uint256 invBefore = IBasePool(address(pool)).computeInvariant(balancesScaled18Before, Rounding.ROUND_DOWN);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = amountIn;
        maxAmountsIn[1] = amountIn;

        medusa.prank(alice);
        uint256[] memory amountsIn = router.addLiquidityProportional(address(pool), maxAmountsIn, 0, false, bytes(""));
        assert(amountsIn.length == 2);
        // Zero amounts in are valid; just skip the rest of the checks
        if (amountsIn[0] == 0 && amountsIn[1] == 0) return;

        // User and pool balances must move exactly by returned amounts.
        uint256 alice0After = tokens[0].balanceOf(alice);
        uint256 alice1After = tokens[1].balanceOf(alice);
        assert(alice0After == alice0Before - amountsIn[0]);
        assert(alice1After == alice1Before - amountsIn[1]);

        (, , uint256[] memory balancesAfter, uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(
            address(pool)
        );
        assert(balancesAfter[0] == balancesBefore[0] + amountsIn[0]);
        assert(balancesAfter[1] == balancesBefore[1] + amountsIn[1]);

        // Proportional adds should not violate invariant-ratio bounds either (allow tiny rounding slack).
        if (invBefore != 0) {
            uint256 invAfter = IBasePool(address(pool)).computeInvariant(
                balancesScaled18After,
                Rounding.ROUND_DOWN
            );
            uint256 ratio = invAfter.divDown(invBefore);
            uint256 maxRatio = IBasePool(address(pool)).getMaximumInvariantRatio();
            assert(ratio <= maxRatio);
        }

        _assertBptRateNeverDecreases();
    }

    /// @notice Fuzz: Add liquidity unbalanced (limited in ECLP).
    function addLiquidityUnbalanced(uint256 amountIn0, uint256 amountIn1) external {
        _saveLastKnownBptRate();

        // ECLP has stricter limits on unbalanced operations
        amountIn0 = _boundAmount(amountIn0);
        amountIn1 = _boundAmount(amountIn1);

        // Limit imbalance to stay within invariant ratio limits
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, uint256[] memory balancesScaled18Before) = vault
            .getPoolTokenInfo(address(pool));
        uint256 maxImbalance = balancesBefore[0] / 5; // 20% max imbalance (rough guardrail to avoid vacuous reverts)

        if (amountIn0 > amountIn1 + maxImbalance) {
            amountIn0 = amountIn1 + maxImbalance;
        } else if (amountIn1 > amountIn0 + maxImbalance) {
            amountIn1 = amountIn0 + maxImbalance;
        }

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = amountIn0;
        exactAmountsIn[1] = amountIn1;

        uint256 alice0Before = tokens[0].balanceOf(alice);
        uint256 alice1Before = tokens[1].balanceOf(alice);
        uint256 invBefore = IBasePool(address(pool)).computeInvariant(balancesScaled18Before, Rounding.ROUND_DOWN);

        medusa.prank(alice);
        uint256 bptOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));

        // Unbalanced add uses *exact* amounts; validate deltas precisely.
        uint256 alice0After = tokens[0].balanceOf(alice);
        uint256 alice1After = tokens[1].balanceOf(alice);
        assert(alice0After == alice0Before - exactAmountsIn[0]);
        assert(alice1After == alice1Before - exactAmountsIn[1]);

        (, , uint256[] memory balancesAfter, uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(
            address(pool)
        );
        assert(balancesAfter[0] == balancesBefore[0] + exactAmountsIn[0]);
        assert(balancesAfter[1] == balancesBefore[1] + exactAmountsIn[1]);

        _assertBptRateNeverDecreases();
        _assertInvariantRatioWithinBounds(invBefore, balancesScaled18After, Rounding.ROUND_DOWN);
    }

    /// @notice Fuzz: Remove liquidity proportionally.
    function removeLiquidityProportional(uint256 bptIn) external {
        _saveLastKnownBptRate();

        uint256 lpBalance = IERC20(address(pool)).balanceOf(lp);
        if (lpBalance == 0) return;

        bptIn = _boundLocal(bptIn, MIN_BPT_OUT, lpBalance / 2);

        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        uint256 lp0Before = tokens[0].balanceOf(lp);
        uint256 lp1Before = tokens[1].balanceOf(lp);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();

        medusa.prank(lp);
        uint256[] memory amountsOut = router.removeLiquidityProportional(address(pool), bptIn, minAmountsOut, false, bytes(""));
        for (uint256 i = 0; i < amountsOut.length; i++) {
            assert(amountsOut[i] > 0);
        }

        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        assert(totalSupplyAfter < totalSupplyBefore);

        // Exact token deltas for proportional remove.
        uint256 lp0After = tokens[0].balanceOf(lp);
        uint256 lp1After = tokens[1].balanceOf(lp);
        assert(lp0After == lp0Before + amountsOut[0]);
        assert(lp1After == lp1Before + amountsOut[1]);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[0] == balancesBefore[0] - amountsOut[0]);
        assert(balancesAfter[1] == balancesBefore[1] - amountsOut[1]);

        _assertBptRateNeverDecreases();
    }

    /// @notice Fuzz: Remove liquidity single token (limited in ECLP).
    function removeLiquiditySingleTokenExactOut(uint256 amountOut, uint256 tokenIndex) external {
        _saveLastKnownBptRate();

        tokenIndex = tokenIndex % 2;

        // Keep memory arrays tightly scoped to avoid "stack too deep" when coverage compilation
        // disables optimizer/viaIR.
        IERC20 token;
        uint256 balanceBefore;
        uint256 invBefore;
        uint256 maxOut;
        {
            (IERC20[] memory tokens, , uint256[] memory balancesBefore, uint256[] memory balancesScaled18Before) = vault
                .getPoolTokenInfo(address(pool));
            token = tokens[tokenIndex];
            balanceBefore = balancesBefore[tokenIndex];
            // Limit to 10% of balance for ECLP (more restrictive than 2-CLP)
            maxOut = balanceBefore / 10;
            invBefore = IBasePool(address(pool)).computeInvariant(balancesScaled18Before, Rounding.ROUND_UP);
        }

        if (maxOut < MIN_TRADE_AMOUNT) return;
        amountOut = _boundLocal(amountOut, MIN_TRADE_AMOUNT, maxOut);

        uint256 lpBalance = IERC20(address(pool)).balanceOf(lp);
        if (lpBalance == 0) return;

        uint256 lpTokenBefore = token.balanceOf(lp);
        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();

        medusa.prank(lp);
        uint256 bptIn = router.removeLiquiditySingleTokenExactOut(address(pool), lpBalance, token, amountOut, false, bytes(""));
        assert(bptIn > 0 && bptIn <= lpBalance);
        _assertBptRateNeverDecreases();

        // Exact out must match user/pool deltas.
        uint256 lpTokenAfter = token.balanceOf(lp);
        assert(lpTokenAfter == lpTokenBefore + amountOut);

        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        // BPT supply should decrease by the burned amount (allowing for exact accounting).
        assert(totalSupplyAfter == totalSupplyBefore - bptIn);

        _assertPoolBalanceAndInvariantAfterSingleTokenExactOut(tokenIndex, balanceBefore, amountOut, invBefore);
    }

    /***************************************************************************
                                    Helper Functions
     ***************************************************************************/

    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return _boundLocal(amount, MIN_TRADE_AMOUNT, MAX_AMOUNT_IN);
    }

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _getCurrentBptRate() internal view returns (uint256) {
        return vault.getBptRate(address(pool));
    }

    function _assertBptRateNeverDecreases() internal {
        uint256 currentRate = _getCurrentBptRate();
        emit Debug("current BPT rate", currentRate);
        emit Debug("initial BPT rate", initialBptRate);
     
        assert(currentRate + 1 >= lastKnownBptRate);
    }

    function _saveLastKnownBptRate() internal {
        lastKnownBptRate = _getCurrentBptRate();
    }

    function _assertInvariantRatioWithinBounds(
        uint256 invBefore,
        uint256[] memory balancesScaled18After,
        Rounding rounding
    ) internal view {
        if (invBefore == 0) return;
        uint256 invAfter = IBasePool(address(pool)).computeInvariant(balancesScaled18After, rounding);
        if (invAfter == 0) return;

        uint256 ratio = invAfter.divDown(invBefore);

        // Compare to the pool's own configured bounds (more robust than hard-coded constants).
        uint256 minRatio = IBasePool(address(pool)).getMinimumInvariantRatio();
        uint256 maxRatio = IBasePool(address(pool)).getMaximumInvariantRatio();

        // Use a tiny slack to avoid false positives due to rounding differences vs Vault internal calculations.
        if (ratio < minRatio) assert(ratio >= minRatio);
        assert(ratio <= maxRatio);
    }

    function _assertPoolBalanceAndInvariantAfterSingleTokenExactOut(
        uint256 tokenIndex,
        uint256 balanceBefore,
        uint256 amountOut,
        uint256 invBefore
    ) internal view {
        (, , uint256[] memory balancesAfter, uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(
            address(pool)
        );
        assert(balancesAfter[tokenIndex] == balanceBefore - amountOut);
        _assertInvariantRatioWithinBounds(invBefore, balancesScaled18After, Rounding.ROUND_UP);
    }

    function _poolStateHash(
        address actor,
        IERC20[] memory tokens,
        uint256[] memory balancesRaw
    ) internal view returns (bytes32) {
        uint256 totalSupply = IERC20(address(pool)).totalSupply();
        return
            keccak256(
                abi.encode(
                    totalSupply,
                    balancesRaw,
                    IERC20(address(pool)).balanceOf(actor),
                    tokens[0].balanceOf(actor),
                    tokens[1].balanceOf(actor)
                )
            );
    }
}
