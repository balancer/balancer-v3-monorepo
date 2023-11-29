// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";

/// @notice Interface for a Base Pool
interface IBasePool {
    /// @dev The caller is not allowed to execute this function; it should be executed by the Vault only.
    error CallerNotVault();

    /// @dev The pool does not support the given join kind.
    error UnhandledJoinKind();

    /// @dev The pool does not support the given exit kind.
    error UnhandledExitKind();

    /// @dev The pool does not implement a callback it was configured with.
    error CallbackNotImplemented();

    /***************************************************************************
                                  Initialization
    ***************************************************************************/

    /**
     * @notice Initialize pool with seed funds.
     * @dev The vault enforces that this callback will only be called once.
     * `exactAmountsIn` have been decimal scaled by the Vault, and are given here as 18-decimal floating point values.
     *
     * @param exactAmountsIn Exact amounts of tokens to be added
     * @param userData Additional (optional) data provided by the user
     * @return bptAmountOut Amount of pool tokens minted
     */
    function onInitialize(
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /***************************************************************************
                                   Invariant
    ***************************************************************************/

    /// @notice Calculates and returns the pool's invariant.
    /// @dev This function computes the invariant based on current balances.
    /// @param balancesScaled18 Array of current pool balances for each token in the pool, scaled to 18 decimals.
    /// @return invariant The calculated invariant of the pool, represented as a uint256.
    function getInvariant(uint256[] memory balancesScaled18) external view returns (uint256);

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /**
     * @notice Optional callback to be executed before `onAddLiquidity...` callbacks are executed.
     * @param sender Address of the sender
     * @param maxAmountsInScaled18 Maximum amounts of input tokens
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Optional, arbitrary data with the encoded request
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeAddLiquidity(
        address sender,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /**
     * @notice Add liquidity to the pool with a single token, specifying exact pool token amount out.
     * @param sender Address of the sender
     * @param tokenInIndex Index of the token used to add liquidity, corresponding to the token address in the pool's
     * registered token array
     * @param exactBptAmountOut Exact amount of pool tokens to receive
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @return amountInScaled18 Amount of tokens required as input
     */
    function onAddLiquiditySingleTokenExactOut(
        address sender,
        uint256 tokenInIndex,
        uint256 exactBptAmountOut,
        uint256[] memory balancesScaled18
    ) external returns (uint256 amountInScaled18);

    /**
     * @notice Add liquidity to the pool with a custom handler.
     * @param sender Address of the sender
     * @param maxAmountsInScaled18 Maximum input amounts, in the same order as the tokens registered in the pool
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Arbitrary data with the encoded request
     * @return amountsInScaled18 Input token amounts, in the same order as the tokens registered in the pool
     * @return bptAmountOut Calculated pool token amount to receive
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function onAddLiquidityCustom(
        address sender,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (uint256[] memory amountsInScaled18, uint256 bptAmountOut, bytes memory returnData);

    /**
     * @notice Optional callback to be executed after `onAddLiquidity...` callbacks are executed.
     * @param sender Address of the sender
     * @param amountsInScaled18 Actual amounts of tokens added, in the same order as the tokens registered in the pool
     * @param bptAmountOut Amount of pool tokens minted
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterAddLiquidity(
        address sender,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Optional callback to be executed before `onRemoveLiquidity...` callbacks are executed.
     * @param sender Address of the sender
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOutScaled18 Minimum output amounts, in the same order as the tokens registered in the pool
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Optional, arbitrary data with the encoded request
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeRemoveLiquidity(
        address sender,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /**
     * @notice Remove liquidity from the pool, specifying exact input pool token amount in exchange for a single token.
     * @param sender Address of the sender
     * @param tokenOutIndex Index of the token to receive in exchange for pool tokens, corresponding to the token
     * address in the pool's registered token array
     * @param exactBptAmountIn Exact amount of pool tokens to burn
     * @param currentBalances Current pool balances, in the same order as the tokens registered in the pool
     * @return amountOutScaled18 Amount of tokens out
     */
    function onRemoveLiquiditySingleTokenExactIn(
        address sender,
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256[] memory currentBalances
    ) external returns (uint256 amountOutScaled18);

    /**
     * @notice Remove liquidity from the pool, specifying exact amount out for a single token.
     * @param sender Address of the sender
     * @param tokenOutIndex Index of the token to receive in exchange for pool tokens, corresponding to the token
     * address in the pool's registered token array
     * @param exactAmountOutScaled18 Exact amount of tokens to receive
     * @param currentBalances Current pool balances, in the same order as the tokens registered in the pool
     * @return bptAmountIn Amount of pool tokens to burn
     */
    function onRemoveLiquiditySingleTokenExactOut(
        address sender,
        uint256 tokenOutIndex,
        uint256 exactAmountOutScaled18,
        uint256[] memory currentBalances
    ) external returns (uint256 bptAmountIn);

    /**
     * @notice Remove liquidity from the pool with a custom handler.
     * @param sender Address of the sender
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOutScaled18 Minimum output amounts, in the same order as the tokens registered in the pool
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Arbitrary data with the encoded request
     * @return bptAmountIn Calculated pool token amount to burn
     * @return amountsOutScaled18 Amount of tokens to receive, in the same order as the tokens registered in the pool
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function onRemoveLiquidityCustom(
        address sender,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOutScaled18, bytes memory returnData);

    /**
     * @notice Optional callback to be executed after `onAddLiquidity...` callbacks are executed.
     * @param sender Address of the sender
     * @param bptAmountIn Amount of pool tokens to burn
     * @param amountsOutScaled18 Amount of tokens to receive, in the same order as the tokens registered in the pool
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterRemoveLiquidity(
        address sender,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /**
     * @dev Data for a swap operation.
     * @param kind Type of swap (given in or given out)
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from (entering the Vault)
     * @param tokenOut Token to be swapped to (leaving the Vault)
     * @param amountGivenScaled18 Amount given based on kind of the swap (e.g., tokenIn for given in)
     * @param balancesScaled18 Current pool balances
     * @param indexIn Index of tokenIn
     * @param indexOut Index of tokenOut
     * @param userData Additional (optional) data required for the swap
     */
    struct SwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGivenScaled18;
        uint256[] balancesScaled18;
        uint256 indexIn;
        uint256 indexOut;
        address sender;
        bytes userData;
    }

    /**
     * @dev Data for the callback after a swap operation.
     * @param kind Type of swap (given in or given out)
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param amountInScaled18 Amount of tokenIn (entering the Vault)
     * @param amountOutScaled18 Amount of tokenOut (leaving the Vault)
     * @param tokenInBalanceScaled18 Updated (after swap) balance of tokenIn
     * @param tokenOutBalanceScaled18 Updated (after swap) balance of tokenOut
     * @param sender Account originating the swap operation
     * @param userData Additional (optional) data required for the swap
     */
    struct AfterSwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountInScaled18;
        uint256 amountOutScaled18;
        uint256 tokenInBalanceScaled18;
        uint256 tokenOutBalanceScaled18;
        address sender;
        bytes userData;
    }

    /**
     * @notice Execute a swap in the pool.
     * @param params Swap parameters (see above for struct definition)
     * @return amountCalculatedScaled18 Calculated amount for the swap
     */
    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculatedScaled18);

    /**
     * @notice Called after a swap to give the Pool an opportunity to perform actions.
     * once the balances have been updated by the swap.
     *
     * @param params Swap parameters (see above for struct definition)
     * @param amountCalculatedScaled18 Token amount calculated by the swap
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterSwap(
        AfterSwapParams calldata params,
        uint256 amountCalculatedScaled18
    ) external returns (bool success);

    /**
     * @notice Gets pool tokens.
     * @return tokens List of tokens in the pool
     */
    function getPoolTokens() external view returns (IERC20[] memory tokens);
}
