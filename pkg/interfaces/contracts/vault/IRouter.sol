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
    ) external payable returns (uint256);

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
}
