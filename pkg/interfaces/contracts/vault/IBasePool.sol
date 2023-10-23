// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";

/// @notice Interface for a Base Pool
interface IBasePool {
    enum AddLiquidityKind {
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    enum RemoveLiquidityKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    /// @dev Indicates the caller is not allowed to execute this function; it should be executed by the Vault only.
    error CallerNotVault();

    /// @dev Indicates that the pool does not support the given join kind.
    error UnhandledJoinKind();

    /// @dev Indicates that the pool does not support the given exit kind.
    error UnhandledExitKind();

    /// @dev Indicates that the pool does not implement a callback that it was configured for.
    error CallbackNotImplemented();

    // TODO: move this to Vault.
    /// @dev Indicates the number of pool tokens is below the minimum allowed.
    error MinTokens();

    /// @dev Indicates the number of pool tokens is above the maximum allowed.
    error MaxTokens();

    /**
     * @notice Initialize pool with seed funds
     * @dev The vault enforces that this callback will only be called once
     * @param maxAmountsIn Maximum amounts of tokens to be added
     * @param userData Additional (optional) data provided by the user
     * @return amountsIn Actual amounts of tokens added
     * @return bptAmountOut Amount of BPT tokens minted
     */
    function onInitialize(
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Add liquidity to the pool
     * @param sender               Address of the sender
     * @param balances             Current balances of the tokens
     * @param maxAmountsIn         Maximum amounts of tokens to be added
     * @param minBptAmountOut      Minimum amount of BPT to receive
     * @param kind                 Add liquidity kind
     * @param userData             Additional data provided by the user
     * @return amountsIn           Actual amounts of tokens added
     * @return bptAmountOut        Amount of BPT tokens minted
     */
    function onAddLiquidity(
        address sender,
        uint256[] memory balances,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        AddLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    function onAfterAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData,
        uint256[] memory amountsIn,
        uint256 bptAmountOut
    ) external returns (bool success);

    /**
     * @notice Remove liquidity from the pool
     * @param sender               Address of the sender
     * @param balances             Current balances of the tokens
     * @param minAmountsOut        Minimum amounts of tokens to be removed
     * @param maxBptAmountIn       Maximum amount of BPT tokens burnt
     * @param kind                 Remove liquidity kind
     * @param userData             Additional data provided by the user
     * @return amountsOut          Actual amounts of tokens removed
     * @return bptAmountIn         Actual amount of BPT burned
     */
    function onRemoveLiquidity(
        address sender,
        uint256[] memory balances,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn);

    function onAfterRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData,
        uint256[] memory amountsOut
    ) external returns (bool success);

    /**
     * @notice Execute a swap in the pool
     * @param params               Parameters of the swap
     * @return amountCalculated    Calculated amount after the swap
     */
    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculated);

    /// @notice Parameters for a swap operation
    struct SwapParams {
        /// @notice Type of swap (given in or given out)
        IVault.SwapKind kind;
        /// @notice Token given in the swap
        IERC20 tokenIn;
        /// @notice Token received from the swap
        IERC20 tokenOut;
        /// @notice Amount of `tokenIn` given
        uint256 amountGiven;
        /// @notice Current balances of all tokens in the pool
        uint256[] balances;
        /// @notice Index of `tokenIn` in the list of pool tokens
        uint256 indexIn;
        /// @notice Index of `tokenOut` in the list of pool tokens
        uint256 indexOut;
        /// @notice Address of the sender
        address sender;
        /// @notice Additional data provided by the user
        bytes userData;
    }

    /**
     * @notice Called after a swap to give the Pool an opportunity to perform actions
     * once the balances have been updated by the swap.
     * @param params               Parameters of the swap
     * @param amountCalculated     Calculated amount after the swap
     * @return success             True if call was a success
     */
    function onAfterSwap(AfterSwapParams calldata params, uint256 amountCalculated) external returns (bool success);

    struct AfterSwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 tokenInBalance;
        uint256 tokenOutBalance;
        address sender;
        bytes userData;
    }
}
