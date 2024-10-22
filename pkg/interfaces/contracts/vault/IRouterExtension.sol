// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouterCommon } from "./IRouterCommon.sol";

/// @notice User-friendly interface to basic Vault operations: swap, add/remove liquidity, and associated queries.
interface IRouterExtension {
    /***************************************************************************
                                      Queries
    ***************************************************************************/

    /**
     * @notice Queries an `addLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     */
    function queryAddLiquidityProportional(
        address pool,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn);

    /**
     * @notice Queries an `addLiquidityUnbalanced` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param exactBptAmountOut Expected exact amount of pool tokens to receive
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountIn Expected amount of tokens to add
     */
    function queryAddLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 amountIn);

    /**
     * @notice Queries an `addLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Expected minimum amount of pool tokens to receive
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     * @return bptAmountOut Expected amount of pool tokens to receive
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryAddLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /**
     * @notice Hook for add liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Add liquidity parameters (see IRouter for struct definition)
     * @return amountsIn Actual token amounts in required as inputs
     * @return bptAmountOut Expected pool tokens to be minted
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryAddLiquidityHook(
        IRouterCommon.AddLiquidityHookParams calldata params
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /**
     * @notice Queries a `removeLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param tokenOut Token used to remove liquidity
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Expected amount of tokens to receive
     */
    function queryRemoveLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 amountOut);

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Expected exact amount of tokens to receive
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountIn Expected amount of pool tokens to burn
     */
    function queryRemoveLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountIn);

    /**
     * @notice Queries a `removeLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Expected minimum amounts of tokens to receive, sorted in token registration order
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountIn Expected amount of pool tokens to burn
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryRemoveLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);

    /**
     * @notice Hook for remove liquidity queries.
     * @dev Can only be called by the Vault.
     * @param params Remove liquidity parameters (see IRouter for struct definition)
     * @return bptAmountIn Pool token amount to be burned for the output tokens
     * @return amountsOut Expected token amounts to be transferred to the sender
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryRemoveLiquidityHook(
        IRouterCommon.RemoveLiquidityHookParams calldata params
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);

    /**
     * @notice Queries a `removeLiquidityRecovery` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityRecovery(
        address pool,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut);

    /**
     * @notice Hook for remove liquidity queries.
     * @dev Can only be called by the Vault.
     * @param pool The liquidity pool
     * @param sender Account originating the remove liquidity operation
     * @param exactBptAmountIn Pool token amount to be burned for the output tokens
     * @return amountsOut Expected token amounts to be transferred to the sender
     */
    function queryRemoveLiquidityRecoveryHook(
        address pool,
        address sender,
        uint256 exactBptAmountIn
    ) external returns (uint256[] memory amountsOut);

    /**
     * @notice Queries a swap operation specifying an exact input token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function querySwapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        address sender,
        bytes calldata userData
    ) external returns (uint256 amountOut);

    /**
     * @notice Queries a swap operation specifying an exact output token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function querySwapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes calldata userData
    ) external returns (uint256 amountIn);

    /**
     * @notice Hook for swap queries.
     * @dev Can only be called by the Vault. Also handles native ETH.
     * @param params Swap parameters (see IRouter for struct definition)
     * @return amountCalculated Token amount calculated by the pool math (e.g., amountOut for a exact in swap)
     */
    function querySwapHook(IRouterCommon.SwapSingleTokenHookParams calldata params) external returns (uint256);
}
