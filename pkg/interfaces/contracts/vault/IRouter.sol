// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";

import { IVault } from "./IVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev
 */
interface IRouter {
    /**
     * @dev
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

    /**
     * @dev
     */
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
     * @dev
     */
    function addLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @dev
     */
    struct AddLiquidityCallbackParams {
        address sender;
        address pool;
        Asset[] assets;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        bytes userData;
    }

    /**
     * @dev
     */
    function removeLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    /**
     * @dev
     */
    struct RemoveLiquidityCallbackParams {
        address sender;
        address pool;
        Asset[] assets;
        uint256[] minAmountsOut;
        uint256 bptAmountIn;
        bytes userData;
    }

    /**
     * @notice Queries a swap operation on a given pool.
     *
     * This function is designed to perform a swap query.
     * It will revert with a proper error message if anything goes wrong, or return the expected value otherwise.
     *
     * @param kind The type of swap to perform.
     * @param pool Address of the liquidity pool.
     * @param assetIn Asset (token) to be swapped from.
     * @param assetOut Asset (token) to be swapped to.
     * @param amountGiven Amount of assetIn to be swapped.
     * @param userData Additional data that might be needed for the swap (depends on the specific pool logic).
     *
     * @return amountCalculated The amount of assetOut that will be received for the given amount of assetIn.
     */
    function querySwap(
        IVault.SwapKind kind,
        address pool,
        Asset assetIn,
        Asset assetOut,
        uint256 amountGiven,
        bytes calldata userData
    ) external payable returns (uint256 amountCalculated);

    /**
     * @dev
     */
    struct QuerySwapCallbackParams {
        address sender;
        IVault.SwapKind kind;
        address pool;
        Asset assetIn;
        Asset assetOut;
        uint256 amountGiven;
        bytes userData;
    }
}
