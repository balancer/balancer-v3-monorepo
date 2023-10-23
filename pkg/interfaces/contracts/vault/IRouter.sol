// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";

import { IVault } from "./IVault.sol";
import { IBasePool } from "./IBasePool.sol";

interface IRouter {
    /***************************************************************************
                               Pool Initialization
    ***************************************************************************/

    struct InitializeCallbackParams {
        address sender;
        address pool;
        Asset[] assets;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        bytes userData;
    }

    /**
     * @notice Initialize a liquidity pool.
     * @param pool Address of the liquidity pool
     * @param tokens Pool tokens
     * @param maxAmountsIn Maximum amounts of assets to be added
     * @param minBptAmountOut Minimum pool tokens to be received
     * @param userData Additional (optional) data required for initialization
     * @return amountsIn Actual token amounts transferred (e.g., including fees)
     * @return bptAmountOut Actual BPT amount minted in exchange for initial liquidity
     */
    function initialize(
        address pool,
        Asset[] memory tokens,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    struct AddLiquidityCallbackParams {
        address sender;
        address pool;
        Asset[] assets;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        IBasePool.AddLiquidityKind kind;
        bytes userData;
    }

    /**
     * @notice Adds liquidity to a pool.
     * @param pool Address of the liquidity pool
     * @param assets Array of assets to add
     * @param maxAmountsIn Maximum amounts of assets to be added
     * @param minBptAmountOut Minimum pool tokens to be received
     * @param userData Additional (optional) data required for adding liquidity
     * @return amountsIn Actual amounts of assets added
     * @return bptAmountOut Pool tokens received
     */
    function addLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IBasePool.AddLiquidityKind kind,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    struct RemoveLiquidityCallbackParams {
        address sender;
        address pool;
        Asset[] assets;
        uint256[] minAmountsOut;
        uint256 maxBptAmountIn;
        IBasePool.RemoveLiquidityKind kind;
        bytes userData;
    }

    /**
     * @notice Removes liquidity from a pool.
     * @param pool Address of the liquidity pool
     * @param assets Array of assets to remove
     * @param minAmountsOut Minimum amounts of assets to be received
     * @param maxBptAmountIn Pool tokens provided
     * @param userData Additional (optional) data required for removing liquidity
     * @return amountsOut Actual amounts of assets received
     */
    function removeLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        IBasePool.RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    struct SwapCallbackParams {
        address sender;
        IVault.SwapKind kind;
        address pool;
        Asset assetIn;
        Asset assetOut;
        uint256 amountGiven;
        uint256 limit;
        uint256 deadline;
        bytes userData;
    }

    /**
     * @notice Executes a swap operation.
     * @param kind Type of swap (given in or given out)
     * @param pool Address of the liquidity pool
     * @param assetIn Asset to be swapped from
     * @param assetOut Asset to be swapped to
     * @param amountGiven Amount given based on kind of the swap (e.g., tokenIn for given in)
     * @param limit Maximum or minimum amount based on the kind of swap (e.g., maxAmountIn for given out)
     * @param deadline Deadline for the swap
     * @param userData Additional (optional) data required for the swap
     * @return amountCalculated Amount calculated based on the kind of swap
     */
    function swap(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        uint256 limit,
        uint256 deadline,
        bytes calldata userData
    ) external payable returns (uint256 amountCalculated);

    /***************************************************************************
                                     Queries
    ***************************************************************************/

    /**
     * @notice Queries an addLiquidity operation without executing it.
     * @param pool Address of the liquidity pool
     * @param assets Array of assets to add
     * @param maxAmountsIn Maximum amounts of assets to be added
     * @param minBptAmountOut Minimum pool tokens expected
     * @param userData Additional (optional) data required for the query
     * @return amountsIn Expected amounts of assets to add
     * @return bptAmountOut Expected pool tokens to receive
     */
    function queryAddLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IBasePool.AddLiquidityKind kind,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Queries removeLiquidity operation without executing it.
     * @param pool Address of the liquidity pool
     * @param assets Array of assets to remove
     * @param minAmountsOut Minimum amounts of assets expected
     * @param maxBptAmountIn Pool tokens provided for the query
     * @param userData Additional (optional) data required for the query
     * @return amountsOut Expected amounts of assets to receive
     */
    function queryRemoveLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        IBasePool.RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn);

    /**
     * @notice Queries a swap operation without executing it.
     * @param kind Type of swap
     * @param pool Address of the liquidity pool
     * @param assetIn Asset to be swapped from
     * @param assetOut Asset to be swapped to
     * @param amountGiven Amount given based on kind of the swap
     * @param userData Additional (optional) data required for the query
     * @return amountCalculated Amount calculated based on the kind of swap
     */
    function querySwap(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        bytes calldata userData
    ) external payable returns (uint256 amountCalculated);
}
