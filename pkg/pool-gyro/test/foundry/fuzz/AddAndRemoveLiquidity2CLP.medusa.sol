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

/**
 * @title AddAndRemoveLiquidity2CLP Medusa Fuzz Test
 * @notice Medusa fuzzing tests for Gyro 2-CLP pool liquidity operations.
 * @dev Key invariants tested:
 *   - BPT rate should never decrease after add/remove liquidity
 *   - Total supply should be consistent with balances
 *   - No tokens should be created or destroyed
 *   - Pool balances should remain above minimums
 */
contract AddAndRemoveLiquidity2CLPMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    error BptOutTooLow(uint256 bptOut, uint256 minBptOut);
    error ZeroAmountOut();
    error BptRateDecreased(uint256 currentRate, uint256 lastKnownRate, uint256 minAllowed);
    error TotalSupplyDidNotIncrease(uint256 beforeSupply, uint256 afterSupply);
    error TotalSupplyDidNotDecrease(uint256 beforeSupply, uint256 afterSupply);
    error BalanceDidNotIncrease(uint256 tokenIndex, uint256 beforeBal, uint256 afterBal);
    error BptInInvalid(uint256 bptIn, uint256 lpBalance);
    error UnexpectedSupplyDelta(uint256 beforeSupply, uint256 afterSupply, uint256 expectedDelta);
    error TokenBalanceDidNotDecrease(address token, uint256 beforeBal, uint256 afterBal, uint256 expectedDelta);
    error TokenBalanceDidNotIncrease(address token, uint256 beforeBal, uint256 afterBal, uint256 expectedDelta);
    error PoolBalanceDidNotChangeByExpectedAmount(
        uint256 tokenIndex,
        uint256 beforeBal,
        uint256 afterBal,
        uint256 expectedDelta
    );

    // Gyro 2-CLP specific parameters
    uint256 internal constant SQRT_ALPHA = 997496867163000167; // alpha = 0.995
    uint256 internal constant SQRT_BETA = 1002496882788171068; // beta = 1.005

    // Limits
    uint256 internal constant MAX_AMOUNT_IN = 1e24;
    uint256 internal constant MIN_TRADE_AMOUNT = 1e6;
    uint256 internal constant MIN_BPT_IN = 1e12; // avoid tiny BPT amounts that round to zero outs

    // Track invariant state
    uint256 internal lastKnownBptRate;
    uint256 internal initialBptRate;

    constructor() BaseMedusaTest() {
        // Record initial BPT rate after pool initialization
        initialBptRate = _getCurrentBptRate();
        lastKnownBptRate = initialBptRate;
    }

    /// @notice Override to create a Gyro 2-CLP pool instead of the default pool.
    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        Gyro2CLPPoolFactory factory = new Gyro2CLPPoolFactory(vault, 365 days, "", "");

        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        // No rate providers (all return 1e18)

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

        // Initialize liquidity
        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    /// @notice Override to use 2 tokens for Gyro 2-CLP.
    function getTokensAndInitialBalances()
        internal
        view
        override
        returns (IERC20[] memory tokens, uint256[] memory initialBalances)
    {
        // Gyro 2-CLP only supports 2 tokens
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

    /**
     * @notice Fuzz: Add liquidity proportionally.
     * @param amountIn Amount to add for each token (bounded)
     */
    function addLiquidityProportional(uint256 amountIn) external {
        amountIn = _boundAmount(amountIn);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = amountIn;
        maxAmountsIn[1] = amountIn;

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        uint256 aliceToken0Before = tokens[0].balanceOf(alice);
        uint256 aliceToken1Before = tokens[1].balanceOf(alice);

        medusa.prank(alice);
        uint256[] memory amountsIn = router.addLiquidityProportional(address(pool), maxAmountsIn, 0, false, bytes(""));

        // Verify some input was actually taken.
        if (amountsIn.length != 2) revert("INVALID_AMOUNTS_IN_LENGTH");
        if (amountsIn[0] == 0 && amountsIn[1] == 0) revert("ZERO_AMOUNTS_IN");

        // Verify BPT was minted (indirectly via totalSupply increase).
        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        if (totalSupplyAfter <= totalSupplyBefore)
            revert TotalSupplyDidNotIncrease(totalSupplyBefore, totalSupplyAfter);

        // Verify caller token balances decreased by exactly the reported input.
        uint256 aliceToken0After = tokens[0].balanceOf(alice);
        uint256 aliceToken1After = tokens[1].balanceOf(alice);
        if (aliceToken0After != aliceToken0Before - amountsIn[0]) {
            revert TokenBalanceDidNotDecrease(address(tokens[0]), aliceToken0Before, aliceToken0After, amountsIn[0]);
        }
        if (aliceToken1After != aliceToken1Before - amountsIn[1]) {
            revert TokenBalanceDidNotDecrease(address(tokens[1]), aliceToken1Before, aliceToken1After, amountsIn[1]);
        }

        // Verify pool balances increased by exactly the reported input.
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        if (balancesAfter[0] != balancesBefore[0] + amountsIn[0]) {
            revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountsIn[0]);
        }
        if (balancesAfter[1] != balancesBefore[1] + amountsIn[1]) {
            revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountsIn[1]);
        }

        // Verify rate invariant
        _assertBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Add liquidity unbalanced.
     * @param amountIn0 Amount of token 0 to add
     * @param amountIn1 Amount of token 1 to add
     */
    function addLiquidityUnbalanced(uint256 amountIn0, uint256 amountIn1) external {
        amountIn0 = _boundAmount(amountIn0);
        amountIn1 = _boundAmount(amountIn1);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = amountIn0;
        // Keep the imbalance within a narrow range so joins are expected to succeed (avoid "always reverting" fuzz).
        // For the 2CLP narrow band [0.995, 1.005], large imbalances commonly hit asset bounds.
        uint256 min1 = (amountIn0 * 95) / 100;
        uint256 max1 = (amountIn0 * 105) / 100;
        if (min1 < MIN_TRADE_AMOUNT) min1 = MIN_TRADE_AMOUNT;
        if (max1 > MAX_AMOUNT_IN) max1 = MAX_AMOUNT_IN;
        exactAmountsIn[1] = _boundLocal(amountIn1, min1, max1);

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        uint256 aliceToken0Before = tokens[0].balanceOf(alice);
        uint256 aliceToken1Before = tokens[1].balanceOf(alice);

        medusa.prank(alice);
        uint256 bptOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));

        // Verify BPT was minted.
        if (bptOut == 0) revert BptOutTooLow(bptOut, 1);

        // Total supply should increase by exactly the minted amount.
        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        if (totalSupplyAfter != totalSupplyBefore + bptOut) {
            revert UnexpectedSupplyDelta(totalSupplyBefore, totalSupplyAfter, bptOut);
        }

        // Verify caller token balances decreased by exactly the input.
        uint256 aliceToken0After = tokens[0].balanceOf(alice);
        uint256 aliceToken1After = tokens[1].balanceOf(alice);
        if (aliceToken0After != aliceToken0Before - exactAmountsIn[0]) {
            revert TokenBalanceDidNotDecrease(
                address(tokens[0]),
                aliceToken0Before,
                aliceToken0After,
                exactAmountsIn[0]
            );
        }
        if (aliceToken1After != aliceToken1Before - exactAmountsIn[1]) {
            revert TokenBalanceDidNotDecrease(
                address(tokens[1]),
                aliceToken1Before,
                aliceToken1After,
                exactAmountsIn[1]
            );
        }

        // Verify pool balances increased by exactly the input.
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        if (balancesAfter[0] != balancesBefore[0] + exactAmountsIn[0]) {
            revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], exactAmountsIn[0]);
        }
        if (balancesAfter[1] != balancesBefore[1] + exactAmountsIn[1]) {
            revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], exactAmountsIn[1]);
        }

        // Verify rate invariant.
        _assertBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Remove liquidity proportionally.
     * @param bptIn Amount of BPT to burn (bounded)
     */
    function removeLiquidityProportional(uint256 bptIn) external {
        uint256 lpBalance = IERC20(address(pool)).balanceOf(lp);
        if (lpBalance == 0) return;
        // Avoid degenerate ranges where min > max.
        if (lpBalance < 2 * MIN_BPT_IN) return;

        // Bound to available balance and leave some liquidity
        bptIn = _boundLocal(bptIn, MIN_BPT_IN, lpBalance / 2);

        uint256[] memory minAmountsOut = new uint256[](2);
        // Set to 0 for simplicity, the invariant checks will catch issues
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        uint256 lpToken0Before = tokens[0].balanceOf(lp);
        uint256 lpToken1Before = tokens[1].balanceOf(lp);

        medusa.prank(lp);
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptIn,
            minAmountsOut,
            false,
            bytes("")
        );

        if (amountsOut.length != 2) revert("INVALID_AMOUNTS_OUT_LENGTH");
        if (amountsOut[0] == 0 && amountsOut[1] == 0) revert ZeroAmountOut();

        // Total supply should have decreased by exactly bptIn.
        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        if (totalSupplyAfter != totalSupplyBefore - bptIn) {
            revert UnexpectedSupplyDelta(totalSupplyBefore, totalSupplyAfter, bptIn);
        }

        // Verify LP received the reported token amounts.
        uint256 lpToken0After = tokens[0].balanceOf(lp);
        uint256 lpToken1After = tokens[1].balanceOf(lp);
        if (lpToken0After != lpToken0Before + amountsOut[0]) {
            revert TokenBalanceDidNotIncrease(address(tokens[0]), lpToken0Before, lpToken0After, amountsOut[0]);
        }
        if (lpToken1After != lpToken1Before + amountsOut[1]) {
            revert TokenBalanceDidNotIncrease(address(tokens[1]), lpToken1Before, lpToken1After, amountsOut[1]);
        }

        // Verify pool balances decreased by exactly the reported output.
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        if (balancesAfter[0] != balancesBefore[0] - amountsOut[0]) {
            revert PoolBalanceDidNotChangeByExpectedAmount(0, balancesBefore[0], balancesAfter[0], amountsOut[0]);
        }
        if (balancesAfter[1] != balancesBefore[1] - amountsOut[1]) {
            revert PoolBalanceDidNotChangeByExpectedAmount(1, balancesBefore[1], balancesAfter[1], amountsOut[1]);
        }

        // Verify rate invariant.
        _assertBptRateNeverDecreases();
    }

    /**
     * @notice Fuzz: Remove liquidity single token exact out.
     * @param amountOut Exact amount of token to receive
     * @param tokenIndex Which token to receive (0 or 1)
     */
    function removeLiquiditySingleTokenExactOut(uint256 amountOut, uint256 tokenIndex) external {
        tokenIndex = tokenIndex % 2;

        // Keep memory arrays tightly scoped to avoid "stack too deep" when coverage compilation
        // disables optimizer/viaIR.
        IERC20 token;
        uint256 poolTokenBalBefore;
        uint256 maxOut;
        {
            (IERC20[] memory tokens, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
            token = tokens[tokenIndex];
            poolTokenBalBefore = balances[tokenIndex];
            // Bound to 1% of pool balance to reduce "expected revert" scenarios in fuzzing.
            maxOut = poolTokenBalBefore / 100;
        }

        if (maxOut < MIN_TRADE_AMOUNT) return;
        amountOut = _boundLocal(amountOut, MIN_TRADE_AMOUNT, maxOut);

        uint256 lpBalance = IERC20(address(pool)).balanceOf(lp);
        if (lpBalance == 0) return;

        uint256 totalSupplyBefore = IERC20(address(pool)).totalSupply();
        uint256 lpBptBefore = IERC20(address(pool)).balanceOf(lp);
        uint256 lpTokenBefore = token.balanceOf(lp);

        medusa.prank(lp);
        uint256 bptIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            lpBalance /* max BPT in */,
            token,
            amountOut,
            false,
            bytes("")
        );

        // Verify BPT was burned.
        if (bptIn == 0 || bptIn > lpBalance) revert BptInInvalid(bptIn, lpBalance);
        uint256 lpBptAfter = IERC20(address(pool)).balanceOf(lp);
        if (lpBptAfter != lpBptBefore - bptIn) {
            revert TokenBalanceDidNotDecrease(address(pool), lpBptBefore, lpBptAfter, bptIn);
        }

        // Total supply should decrease by exactly bptIn.
        uint256 totalSupplyAfter = IERC20(address(pool)).totalSupply();
        if (totalSupplyAfter != totalSupplyBefore - bptIn) {
            revert UnexpectedSupplyDelta(totalSupplyBefore, totalSupplyAfter, bptIn);
        }

        // LP must receive the exact amountOut for the selected token.
        uint256 lpTokenAfter = token.balanceOf(lp);
        if (lpTokenAfter != lpTokenBefore + amountOut) {
            revert TokenBalanceDidNotIncrease(address(token), lpTokenBefore, lpTokenAfter, amountOut);
        }

        _assertPoolBalanceDecreasedByExpectedAmount(tokenIndex, poolTokenBalBefore, amountOut);

        // Verify rate invariant.
        _assertBptRateNeverDecreases();
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
        return IGyro2CLPPool(address(pool)).getGyro2CLPPoolDynamicData().bptRate;
    }

    function _assertBptRateNeverDecreases() internal {
        uint256 currentRate = _getCurrentBptRate();
        // Update tracked rate if it increased
        if (currentRate > lastKnownBptRate) {
            lastKnownBptRate = currentRate;
        }
        // Allow for tiny rounding errors (0.001%)
        uint256 minAllowed = lastKnownBptRate.mulDown(99999e13);
        if (currentRate < minAllowed) revert BptRateDecreased(currentRate, lastKnownBptRate, minAllowed);
    }

    function _assertPoolBalanceDecreasedByExpectedAmount(
        uint256 tokenIndex,
        uint256 poolTokenBalBefore,
        uint256 amountOut
    ) internal view {
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        if (balancesAfter[tokenIndex] != poolTokenBalBefore - amountOut) {
            revert PoolBalanceDidNotChangeByExpectedAmount(
                tokenIndex,
                poolTokenBalBefore,
                balancesAfter[tokenIndex],
                amountOut
            );
        }
    }
}
