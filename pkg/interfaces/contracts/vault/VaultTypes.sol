// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IRateProvider } from "./IRateProvider.sol";

struct LiquidityManagement {
    bool disableUnbalancedLiquidity;
    bool enableAddLiquidityCustom;
    bool enableRemoveLiquidityCustom;
}

// @notice Config type to store entire configuration of the pool
struct PoolConfigBits {
    bytes32 bits;
}

// @notice Config type to store entire hook configuration of the pool
struct HooksConfigBits {
    bytes32 bits;
    address hooksContract;
}

/// @dev Represents a pool's configuration (hooks configuration are separated in another struct).
struct PoolConfig {
    LiquidityManagement liquidityManagement;
    uint256 staticSwapFeePercentage;
    uint256 aggregateProtocolSwapFeePercentage;
    uint256 aggregateProtocolYieldFeePercentage;
    uint256 tokenDecimalDiffs;
    uint256 pauseWindowEndTime;
    bool isPoolRegistered;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
}

/// @dev Represents a hook contract configuration for a pool.
struct HooksConfig {
    bool shouldCallBeforeInitialize;
    bool shouldCallAfterInitialize;
    bool shouldCallComputeDynamicSwapFee;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
    bool shouldCallBeforeAddLiquidity;
    bool shouldCallAfterAddLiquidity;
    bool shouldCallBeforeRemoveLiquidity;
    bool shouldCallAfterRemoveLiquidity;
    address hooksContract;
}

/// @dev Represents temporary state used in a swap operation.
struct SwapState {
    uint256 indexIn;
    uint256 indexOut;
    uint256 amountGivenScaled18;
    uint256 swapFeePercentage;
}

/**
 * @dev Represents the Vault's configuration.
 * @param isQueryDisabled If set to true, disables query functionality of the Vault. Can be modified only by
 * governance.
 * @param isVaultPaused If set to true, Swaps and Add/Remove Liquidity operations are halted
 * @param areBuffersPaused If set to true, the Vault wrap/unwrap primitives associated with buffers will be disabled
 */
struct VaultState {
    bool isQueryDisabled;
    bool isVaultPaused;
    bool areBuffersPaused;
}

/**
 * @dev Represents the accounts holding certain roles for a given pool. This is passed in on pool registration.
 * @param pauseManager Account empowered to pause/unpause the pool (or 0 to delegate to governance)
 * @param swapFeeManager Account empowered to set static swap fees for a pool (or 0 to delegate to goverance)
 * @param poolCreator Account empowered to set the pool creator fee percentage
 */
struct PoolRoleAccounts {
    address pauseManager;
    address swapFeeManager;
    address poolCreator;
}

/**
 * @notice Record pool function permissions (as a sort of local authorizer).
 * @dev For each permissioned function controlled by a role (e.g., pause/unpause), store the account empowered to call
 * that function, and flag indicating whether, if the caller is not the designated account (which might be zero),
 * it should then delegate to governance. If the `onlyOwner` flag is true, it can only be called by the designated
 * account.
 *
 * @param account The account with permission to perform the role
 * @param onlyOwner Flag indicating whether it is reserved to the account alone, or also governance
 */
struct PoolFunctionPermission {
    address account;
    bool onlyOwner;
}

/**
 * @dev Token types supported by the Vault. In general, pools may contain any combination of these tokens.
 * STANDARD tokens (e.g., BAL, WETH) have no rate provider.
 * WITH_RATE tokens (e.g., wstETH) require a rate provider. These may be tokens like wstETH, which need to be wrapped
 * because the underlying stETH token is rebasing, and such tokens are unsupported by the Vault. They may also be
 * tokens like sEUR, which track an underlying asset, but are not yield-bearing. Finally, this encompasses
 * yield-bearing ERC4626 tokens, which can be used to facilitate swaps without requiring wrapping or unwrapping
 * in most cases. The `paysYieldFees` flag can be used to indicate whether a token is yield-bearing (e.g., waDAI),
 * not yield-bearing (e.g., sEUR), or yield-bearing but exempt from fees (e.g., in certain nested pools, where
 * protocol yield fees are charged elsewhere).
 *
 * NB: STANDARD must always be the first enum element, so that newly initialized data structures default to Standard.
 */
enum TokenType {
    STANDARD,
    WITH_RATE
}

/**
 * @dev Encapsulate the data required for the Vault to support a token of the given type.
 * For STANDARD tokens, the rate provider address must be 0, and paysYieldFees must be false.
 * All WITH_RATE tokens need a rate provider, and may or may not be yield-bearing.
 *
 * @param token The token address
 * @param tokenType The token type (see the enum for supported types)
 * @param rateProvider The rate provider for a token (see further documentation above)
 * @param paysYieldFees Flag indicating whether yield fees should be charged on this token
 */
struct TokenConfig {
    IERC20 token;
    TokenType tokenType;
    IRateProvider rateProvider;
    bool paysYieldFees;
}

struct PoolData {
    PoolConfigBits poolConfig;
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
    PROPORTIONAL,
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

/*******************************************************************************
                                Remove liquidity
*******************************************************************************/

enum WrappingDirection {
    WRAP,
    UNWRAP
}

/**
 * @dev Data for a wrap/unwrap operation.
 * @param kind Type of swap (Exact In or Exact Out)
 * @param direction Direction of the wrapping operation (Wrap or Unwrap)
 * @param wrappedToken Wrapped token, compatible with interface ERC4626
 * @param amountGivenRaw Amount specified for tokenIn or tokenOut (depends on the type of swap and wrapping direction)
 * @param limitRaw Minimum or maximum amount specified for the other token (depends on the type of swap and wrapping
 * direction)
 * @param userData Optional user data
 */
struct BufferWrapOrUnwrapParams {
    SwapKind kind;
    WrappingDirection direction;
    IERC4626 wrappedToken;
    uint256 amountGivenRaw;
    uint256 limitRaw;
    bytes userData;
}

// Protocol Fees are 24-bit values. We transform them by multiplying by 1e11, so
// they can be set to any value between 0% and 100% (step 0.00001%).
uint256 constant FEE_BITLENGTH = 24;
uint256 constant FEE_SCALING_FACTOR = 1e11;
