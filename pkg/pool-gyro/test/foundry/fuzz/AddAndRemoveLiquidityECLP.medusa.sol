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
            (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
            initialBptRate = _computeBptRate(totalSupply, balances);
            lastKnownBptRate = initialBptRate;
        }
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

    /**
     * @notice Override to use 2 tokens for ECLP
     */
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
                               FUZZ FUNCTIONS
     ***************************************************************************/

    /**
     * @notice Fuzz: Add liquidity proportionally
     */
    function addLiquidityProportional(uint256 amountIn) external {
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
        try router.addLiquidityProportional(address(pool), maxAmountsIn, 0, false, bytes("")) returns (
            uint256[] memory amountsIn
        ) {
            if (amountsIn.length != 2) revert InvalidAmountsInLength(amountsIn.length);
            if (amountsIn[0] == 0 && amountsIn[1] == 0) revert ZeroAmountsIn();

            // User and pool balances must move exactly by returned amounts.
            uint256 alice0After = tokens[0].balanceOf(alice);
            uint256 alice1After = tokens[1].balanceOf(alice);
            if (alice0After != alice0Before - amountsIn[0]) {
                revert TokenBalanceDidNotDecrease(address(tokens[0]), alice0Before, alice0After, amountsIn[0]);
            }
            if (alice1After != alice1Before - amountsIn[1]) {
                revert TokenBalanceDidNotDecrease(address(tokens[1]), alice1Before, alice1After, amountsIn[1]);
            }

            (, , uint256[] memory balancesAfter, uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(
                address(pool)
            );
            if (balancesAfter[0] != balancesBefore[0] + amountsIn[0]) {
                revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountsIn[0]);
            }
            if (balancesAfter[1] != balancesBefore[1] + amountsIn[1]) {
                revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountsIn[1]);
            }

            // Proportional adds should not violate invariant-ratio bounds either (allow tiny rounding slack).
            if (invBefore != 0) {
                uint256 invAfter = IBasePool(address(pool)).computeInvariant(
                    balancesScaled18After,
                    Rounding.ROUND_DOWN
                );
                uint256 ratio = invAfter.divDown(invBefore);
                uint256 maxRatio = IBasePool(address(pool)).getMaximumInvariantRatio();
                assertLe(ratio, maxRatio + 1, "Invariant ratio above max (prop add)");
            }

            _assertBptRateNeverDecreases();
        } catch (bytes memory err) {
            _assertExpectedLiquidityRevert(err);
        }
    }

    /**
     * @notice Fuzz: Add liquidity unbalanced (limited in ECLP)
     */
    function addLiquidityUnbalanced(uint256 amountIn0, uint256 amountIn1) external {
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
        try router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes("")) returns (uint256 bptOut) {
            if (bptOut < MIN_BPT_OUT) revert BptOutTooLow(bptOut, MIN_BPT_OUT);

            // Unbalanced add uses *exact* amounts; validate deltas precisely.
            uint256 alice0After = tokens[0].balanceOf(alice);
            uint256 alice1After = tokens[1].balanceOf(alice);
            if (alice0After != alice0Before - exactAmountsIn[0]) {
                revert TokenBalanceDidNotDecrease(address(tokens[0]), alice0Before, alice0After, exactAmountsIn[0]);
            }
            if (alice1After != alice1Before - exactAmountsIn[1]) {
                revert TokenBalanceDidNotDecrease(address(tokens[1]), alice1Before, alice1After, exactAmountsIn[1]);
            }

            (, , uint256[] memory balancesAfter, uint256[] memory balancesScaled18After) = vault.getPoolTokenInfo(
                address(pool)
            );
            if (balancesAfter[0] != balancesBefore[0] + exactAmountsIn[0]) {
                revert PoolBalanceDidNotChangeByExpectedAmount(
                    0,
                    balancesBefore[0],
                    balancesAfter[0],
                    exactAmountsIn[0]
                );
            }
            if (balancesAfter[1] != balancesBefore[1] + exactAmountsIn[1]) {
                revert PoolBalanceDidNotChangeByExpectedAmount(
                    1,
                    balancesBefore[1],
                    balancesAfter[1],
                    exactAmountsIn[1]
                );
            }

            _assertBptRateNeverDecreases();
            _assertInvariantRatioWithinBounds(invBefore, balancesScaled18After, Rounding.ROUND_DOWN);
        } catch (bytes memory err) {
            _assertExpectedLiquidityRevert(err);
        }
    }

    /**
     * @notice Fuzz: Remove liquidity proportionally
     */
    function removeLiquidityProportional(uint256 bptIn) external {
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
        try router.removeLiquidityProportional(address(pool), bptIn, minAmountsOut, false, bytes("")) returns (
            uint256[] memory amountsOut
        ) {
            for (uint256 i = 0; i < amountsOut.length; i++) {
                if (amountsOut[i] == 0) revert ZeroAmountOut();
            }

            uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
            if (totalSupplyAfter >= totalSupplyBefore)
                revert TotalSupplyDidNotDecrease(totalSupplyBefore, totalSupplyAfter);

            // Exact token deltas for proportional remove.
            uint256 lp0After = tokens[0].balanceOf(lp);
            uint256 lp1After = tokens[1].balanceOf(lp);
            if (lp0After != lp0Before + amountsOut[0]) {
                revert TokenBalanceDidNotIncrease(address(tokens[0]), lp0Before, lp0After, amountsOut[0]);
            }
            if (lp1After != lp1Before + amountsOut[1]) {
                revert TokenBalanceDidNotIncrease(address(tokens[1]), lp1Before, lp1After, amountsOut[1]);
            }

            (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
            if (balancesAfter[0] != balancesBefore[0] - amountsOut[0]) {
                revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountsOut[0]);
            }
            if (balancesAfter[1] != balancesBefore[1] - amountsOut[1]) {
                revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountsOut[1]);
            }

            _assertBptRateNeverDecreases();
        } catch (bytes memory err) {
            _assertExpectedLiquidityRevert(err);
        }
    }

    /**
     * @notice Fuzz: Remove liquidity single token (limited in ECLP)
     */
    function removeLiquiditySingleTokenExactOut(uint256 amountOut, uint256 tokenIndex) external {
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
        try
            router.removeLiquiditySingleTokenExactOut(address(pool), lpBalance, token, amountOut, false, bytes(""))
        returns (uint256 bptIn) {
            if (bptIn == 0 || bptIn > lpBalance) revert BptInInvalid(bptIn, lpBalance);
            _assertBptRateNeverDecreases();

            // Exact out must match user/pool deltas.
            uint256 lpTokenAfter = token.balanceOf(lp);
            if (lpTokenAfter != lpTokenBefore + amountOut) {
                revert TokenBalanceDidNotIncrease(address(token), lpTokenBefore, lpTokenAfter, amountOut);
            }

            uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
            // BPT supply should decrease by the burned amount (allowing for exact accounting).
            if (totalSupplyAfter != totalSupplyBefore - bptIn) {
                revert TotalSupplyDidNotDecrease(totalSupplyBefore, totalSupplyAfter);
            }

            _assertPoolBalanceAndInvariantAfterSingleTokenExactOut(tokenIndex, balanceBefore, amountOut, invBefore);
        } catch (bytes memory err) {
            _assertExpectedLiquidityRevert(err);
        }
    }

    /***************************************************************************
                              HELPER FUNCTIONS
     ***************************************************************************/

    function _boundAmount(uint256 amount) internal pure returns (uint256) {
        return _boundLocal(amount, MIN_TRADE_AMOUNT, MAX_AMOUNT_IN);
    }

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _getCurrentBptRate() internal view returns (uint256) {
        uint256 totalSupply = IERC20(address(pool)).totalSupply();
        if (totalSupply == 0) return 0;

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        return _computeBptRate(totalSupply, balances);
    }

    function _computeBptRate(uint256 totalSupply, uint256[] memory balances) internal pure returns (uint256) {
        if (totalSupply == 0) return 0;

        uint256 totalValue = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            totalValue += balances[i];
        }
        return totalValue.divDown(totalSupply);
    }

    function _assertBptRateNeverDecreases() internal {
        uint256 currentRate = _getCurrentBptRate();
        if (currentRate > lastKnownBptRate) {
            lastKnownBptRate = currentRate;
        }
        uint256 minAllowed = lastKnownBptRate.mulDown(99999e13);
        if (currentRate < minAllowed) revert BptRateDecreased(currentRate, lastKnownBptRate, minAllowed);
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
        if (ratio + 1 < minRatio) assertGe(ratio, minRatio, "Invariant ratio below min bound");
        assertLe(ratio, maxRatio + 1, "Invariant ratio above max bound");
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
        if (balancesAfter[tokenIndex] != balanceBefore - amountOut) {
            revert PoolBalanceDidNotChangeByExpectedAmount(
                tokenIndex,
                balanceBefore,
                balancesAfter[tokenIndex],
                amountOut
            );
        }
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

    function _assertExpectedLiquidityRevert(bytes memory err) internal pure {
        bytes4 sel = _revertSelector(err);
        if (sel == bytes4(0)) revert RevertedWithoutData();

        // Common, high-signal guardrails for ECLP liquidity paths.
        if (sel == GyroECLPMath.AssetBoundsExceeded.selector) return;
        if (sel == BasePoolMath.InvariantRatioAboveMax.selector) return;
        if (sel == BasePoolMath.InvariantRatioBelowMin.selector) return;

        revert UnexpectedRevertSelector(sel);
    }

    function _revertSelector(bytes memory err) internal pure returns (bytes4 selector) {
        if (err.length < 4) return bytes4(0);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := mload(add(err, 0x20))
        }
    }
}
