// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";
import { IRouterQueries } from "./IRouterQueries.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";

/// @notice User-friendly interface to basic Vault operations: swap, add/remove liquidity, and associated queries.
interface IRouter is IRouterQueries {
    /***************************************************************************
                                Pool Initialization
    ***************************************************************************/

    /**
     * @notice Initialize a liquidity pool.
     * @param pool Address of the liquidity pool
     * @param tokens Pool tokens, in token registration order
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add initial liquidity
     * @return bptAmountOut Actual amount of pool tokens minted in exchange for initial liquidity
     */
    function initialize(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /**
     * @notice Adds liquidity to a pool with proportional token amounts, receiving an exact amount of pool tokens.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     */
    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn);

    /**
     * @notice Adds liquidity to a pool with arbitrary token amounts.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Adds liquidity to a pool in a single token, receiving an exact amount of pool tokens.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param maxAmountIn Maximum amount of tokens to be added
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountIn Actual amount of tokens added
     */
    function addLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 amountIn);

    /**
     * @notice Adds liquidity to a pool by donating the amounts in (no BPT out).
     * @dev To support donation, the pool config `enableDonation` flag must be set to true.
     * @param pool Address of the liquidity pool
     * @param amountsIn Amounts of tokens to be donated, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to donate liquidity
     */
    function donate(address pool, uint256[] memory amountsIn, bool wethIsEth, bytes memory userData) external payable;

    /**
     * @notice Adds liquidity to a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     * @return bptAmountOut Actual amount of pool tokens received
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function addLiquidityCustom(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Removes liquidity with proportional token amounts from a pool, burning an exact pool token amount.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);

    /**
     * @notice Removes liquidity from a pool via a single token, burning an exact pool token amount.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param minAmountOut Minimum amount of tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return amountOut Actual amount of tokens received
     */
    function removeLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 amountOut);

    /**
     * @notice Removes liquidity from a pool via a single token, specifying the exact amount of tokens to receive.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Exact amount of tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return bptAmountIn Actual amount of pool tokens burned
     */
    function removeLiquiditySingleTokenExactOut(
        address pool,
        uint256 maxBptAmountIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountIn);

    /**
     * @notice Removes liquidity from a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return bptAmountIn Actual amount of pool tokens burned
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function removeLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);

    /**
     * @notice Removes liquidity proportionally, burning an exact pool token amount. Only available in Recovery Mode.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquidityRecovery(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut
    ) external payable returns (uint256[] memory amountsOut);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /**
     * @notice Executes a swap operation specifying an exact input token amount.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap, after which it will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data sent with the swap request
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountOut);

    /**
     * @notice Executes a swap operation specifying an exact output token amount.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param maxAmountIn Maximum amount of tokens to be sent
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data sent with the swap request
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountIn);
}
