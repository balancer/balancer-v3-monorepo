// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "./IRateProvider.sol";

/// @dev Represents a pool's callbacks.
struct PoolCallbacks {
    bool shouldCallBeforeInitialize;
    bool shouldCallAfterInitialize;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
    bool shouldCallBeforeAddLiquidity;
    bool shouldCallAfterAddLiquidity;
    bool shouldCallBeforeRemoveLiquidity;
    bool shouldCallAfterRemoveLiquidity;
}

struct LiquidityManagement {
    bool supportsAddLiquidityCustom;
    bool supportsRemoveLiquidityCustom;
}

/// @dev Represents a pool's configuration, including callbacks.
struct PoolConfig {
    bool isPoolRegistered;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool hasDynamicSwapFee;
    uint64 staticSwapFeePercentage; // stores an 18-decimal FP value (max FixedPoint.ONE)
    uint24 tokenDecimalDiffs; // stores 18-(token decimals), for each token
    uint32 pauseWindowEndTime;
    PoolCallbacks callbacks;
    LiquidityManagement liquidityManagement;
}

struct PoolData {
    PoolConfig config;
    IERC20[] tokens;
    IRateProvider[] rateProviders;
    uint256[] balancesRaw;
    uint256[] balancesLiveScaled18;
    uint256[] tokenRates;
    uint256[] decimalScalingFactors;
}

enum Rounding {
    ROUND_UP,
    ROUND_DOWN
}

/*******************************************************************************
                                    Swaps
*******************************************************************************/

enum SwapKind {
    GIVEN_IN,
    GIVEN_OUT
}

/**
 * @dev Data for a swap operation.
 * @param kind Type of swap (Given In or Given Out)
 * @param pool The pool with the tokens being swapped
 * @param tokenIn The token entering the Vault (balance increases)
 * @param tokenOut The token leaving the Vault (balance decreases)
 * @param amountGivenRaw Amount specified for tokenIn or tokenOut (depending on the type of swap)
 * @param userData Additional (optional) user data
 */
struct SwapParams {
    SwapKind kind;
    address pool;
    IERC20 tokenIn;
    IERC20 tokenOut;
    uint256 amountGivenRaw;
    bytes userData;
}

/*******************************************************************************
                                Add liquidity
*******************************************************************************/

enum AddLiquidityKind {
    UNBALANCED,
    SINGLE_TOKEN_EXACT_OUT,
    CUSTOM
}

/**
 * @dev Data for an add liquidity operation.
 * @param pool Address of the pool
 * @param to Address of user to mint to
 * @param maxAmountsIn Maximum amounts of input tokens
 * @param minBptAmountOut Minimum amount of output pool tokens
 * @param kind Add liquidity kind
 * @param userData Optional user data
 */
struct AddLiquidityParams {
    address pool;
    address to;
    uint256[] maxAmountsIn;
    uint256 minBptAmountOut;
    AddLiquidityKind kind;
    bytes userData;
}

/*******************************************************************************
                                Remove liquidity
*******************************************************************************/

enum RemoveLiquidityKind {
    PROPORTIONAL,
    SINGLE_TOKEN_EXACT_IN,
    SINGLE_TOKEN_EXACT_OUT,
    CUSTOM
}

/**
 * @param pool Address of the pool
 * @param from Address of user to burn from
 * @param maxBptAmountIn Maximum amount of input pool tokens
 * @param minAmountsOut Minimum amounts of output tokens
 * @param kind Remove liquidity kind
 * @param userData Optional user data
 */
struct RemoveLiquidityParams {
    address pool;
    address from;
    uint256 maxBptAmountIn;
    uint256[] minAmountsOut;
    RemoveLiquidityKind kind;
    bytes userData;
}
