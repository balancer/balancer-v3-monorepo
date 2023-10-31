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
     * @param maxAmountsIn Maximum amounts of tokens to be added
     * @param userData Additional (optional) data provided by the user
     * @return amountsIn Actual amounts of tokens added
     * @return bptAmountOut Amount of pool tokens minted
     */
    function onInitialize(
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /**
     * @notice Optional callback to be executed before `onAddLiquidity...` callbacks are executed.
     * @param currentBalances Current pool balances, in the same order as the registered pool tokens
     * @param userData Optional, arbitrary data with the encoded request
     */
    function onBeforeAddLiquidity(
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        uint256 minBptOut,
        bytes memory userData
    ) external returns (bool);

    /**
     * @notice Add liquidity to the pool specifying exact token amounts in.
     * @param sender Address of the sender
     * @param exactAmountsIn Exact amounts of tokens to be added, in the same order as the registered pool tokens
     * @param currentBalances Current pool balances, in the same order as the registered pool tokens
     * @return bptAmountOut Amount of pool tokens minted in exchange for the added liquidity
     */
    function onAddLiquidityUnbalanced(
        address sender,
        uint256[] memory exactAmountsIn,
        uint256[] memory currentBalances
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Add liquidity to the pool with a single token, specifying exact pool token amount out.
     * @param sender Address of the sender
     * @param tokenInIndex Index of the token used to add liquidity, corresponding to the token address in the pool's
     * registered token array
     * @param exactBptAmountOut Exact amount of pool tokens to receive
     * @param currentBalances Current pool balances, in the same order as the registered pool tokens
     * @return amountIn Amount of tokens required as input
     */
    function onAddLiquiditySingleTokenExactOut(
        address sender,
        uint256 tokenInIndex,
        uint256 exactBptAmountOut,
        uint256[] memory currentBalances
    ) external returns (uint256 amountIn);

    /**
     * @notice Add liquidity to the pool with a custom handler.
     * @param sender Address of the sender
     * @param userData Arbitrary data with the encoded request
     * @param currentBalances Current pool balances, in the same order as the registered pool tokens
     * @return amountsIn Amount of tokens required as input, in the same order as the registered pool tokens
     * @return bptAmountOut Calculated pool token amount to receive
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function onAddLiquidityCustom(
        address sender,
        bytes memory userData,
        uint256[] memory currentBalances
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /**
     * @notice Callback after adding liquidity to the pool.
     * @param sender Address of the sender
     * @param currentBalances Current balances of the tokens
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        bytes memory userData,
        uint256[] memory amountsIn,
        uint256 bptAmountOut
    ) external returns (bool success);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Optional callback to be executed before `onRemoveLiquidity...` callbacks are executed.
     * @param currentBalances Current pool balances, in the same order as the registered pool tokens
     * @param userData Optional, arbitrary data with the encoded request
     */
    function onBeforeRemoveLiquidity(
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        bytes memory userData
    ) external returns (bool);

    /**
     * @notice Remove liquidity from the pool, specifying exact pool token amount out in exchange for a single token.
     * @param sender Address of the sender
     * @param tokenOutIndex Index of the token to receive in exchange for pool tokens, corresponding to the token
     * address in the pool's registered token array
     * @param exactBptAmountIn Exact amount of pool tokens to burn
     * @param currentBalances Current pool balances, in the same order as the registered pool tokens
     * @return amountOut Amount of tokens out
     */
    function onRemoveLiquiditySingleTokenExactIn(
        address sender,
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256[] memory currentBalances
    ) external returns (uint256 amountOut);

    function onRemoveLiquiditySingleTokenExactOut(
        address sender,
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256[] memory currentBalances
    ) external returns (uint256 bptAmountIn);

    /**
     * @notice Remove liquidity from the pool with a custom handler.
     * @param sender Address of the sender
     * @param userData Arbitrary data with the encoded request
     * @param currentBalances Current pool balances, in the same order as the registered pool tokens
     * @return amountsOut Amount of tokens to receive, in the same order as the registered pool tokens
     * @return bptAmountIn Calculated pool token amount to burn
     * @return returnData Arbitrary data with encoded response from the pool
     */
    function onRemoveLiquidityCustom(
        address sender,
        bytes memory userData,
        uint256[] memory currentBalances
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn, bytes memory returnData);

    /**
     * @notice Callback after removing liquidity from the pool.
     * @param sender Address of the sender
     * @param currentBalances Current balances of the tokens
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256 bptAmountIn,
        bytes memory userData,
        uint256[] memory amountsOut
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
     * @param amountGiven Amount given based on kind of the swap (e.g., tokenIn for given in)
     * @param balances Current pool balances
     * @param indexIn Index of tokenIn
     * @param indexOut Index of tokenOut
     * @param userData Additional (optional) data required for the swap
     */
    struct SwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256[] balances;
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
     * @param amountIn Amount of tokenIn (entering the Vault)
     * @param amountOut Amount of tokenOut (leaving the Vault)
     * @param tokenInBalance Updated (after swap) balance of tokenIn
     * @param tokenOutBalance Updated (after swap) balance of tokenOut
     * @param sender Account originating the swap operation
     * @param userData Additional (optional) data required for the swap
     */
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

    /**
     * @notice Execute a swap in the pool.
     * @param params Swap parameters (see above for struct definition)
     * @return amountCalculated Calculated amount for the swap
     */
    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculated);

    /**
     * @notice Called after a swap to give the Pool an opportunity to perform actions.
     * once the balances have been updated by the swap.
     *
     * @param params Swap parameters (see above for struct definition)
     * @param amountCalculated Token amount calculated by the swap
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterSwap(AfterSwapParams calldata params, uint256 amountCalculated) external returns (bool success);

    /**
     * @notice Gets pool tokens and their balances.
     * @return tokens List of tokens in the pool
     * @return balances Corresponding balances of the tokens
     */
    function getPoolTokens() external view returns (IERC20[] memory tokens, uint256[] memory balances);
}
