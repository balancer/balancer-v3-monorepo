// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "./IRateProvider.sol";

/// @dev Represents a pool's hooks.
struct PoolHooks {
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

/// @dev Represents a pool's configuration, including hooks.
struct PoolConfig {
    bool isPoolRegistered;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool hasDynamicSwapFee;
    uint64 staticSwapFeePercentage; // stores an 18-decimal FP value (max FixedPoint.ONE)
    uint24 tokenDecimalDiffs; // stores 18-(token decimals), for each token
    uint32 pauseWindowEndTime;
    PoolHooks hooks;
    LiquidityManagement liquidityManagement;
}

/**
 * @dev Token types supported by the Vault. In general, pools may contain any combination of these tokens.
 * STANDARD tokens (e.g., BAL, WETH) have no rate provider.
 * WITH_RATE tokens (e.g., wstETH) require rates but cannot be directly wrapped or unwrapped.
 * In the case of wstETH, this is because the underlying stETH token is rebasing, and such tokens are unsupported
 * by the Vault.
 * ERC4626 tokens (e.g., waDAI) have rates, and can be directly wrapped and unwrapped. The token must conform to
 * a subset of IERC4626, and functions as its own rate provider. To the outside world (e.g., callers of
 * `getPoolTokens`), the pool will appear to contain the underlying base token (DAI, for waDAI), though the
 * wrapped token will be registered and stored in the pool's balance in the Vault.
 *
 * NB: STANDARD must always be the first enum element, so that newly initialized data structures default to Standard.
 */
enum TokenType {
    STANDARD,
    WITH_RATE,
    ERC4626
}

/**
 * @dev Encapsulate the data required for the Vault to support a token of the given type.
 * For STANDARD or ERC4626 tokens, the rate provider address will be 0. By definition, ERC4626 tokens cannot be
 * yield exempt, so the `yieldFeeExempt` flag must be false when registering them.
 *
 * @param token The token address
 * @param tokenType The token type (see the enum for supported types)
 * @param rateProvider The rate provider for a token (see further documentation above)
 * @param yieldFeeExempt Flag indicating whether yield fees should be charged on this token
 */
struct TokenConfig {
    IERC20 token;
    TokenType tokenType;
    IRateProvider rateProvider;
    bool yieldFeeExempt;
}

struct PoolData {
    PoolConfig poolConfig;
    TokenConfig[] tokenConfig;
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
    EXACT_IN,
    EXACT_OUT
}

/**
 * @dev Data for a swap operation.
 * @param kind Type of swap (Exact In or Exact Out)
 * @param pool The pool with the tokens being swapped
 * @param tokenIn The token entering the Vault (balance increases)
 * @param tokenOut The token leaving the Vault (balance decreases)
 * @param amountGivenRaw Amount specified for tokenIn or tokenOut (depending on the type of swap)
 * @param limitRaw
 * @param userData Additional (optional) user data
 */
struct SwapParams {
    SwapKind kind;
    address pool;
    IERC20 tokenIn;
    IERC20 tokenOut;
    uint256 amountGivenRaw;
    uint256 limitRaw;
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
