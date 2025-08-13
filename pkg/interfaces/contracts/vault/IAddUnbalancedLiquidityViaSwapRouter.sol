// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";
import { IRouterQueries } from "./IRouterQueries.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";
import "./RouterTypes.sol";

/// @notice Router interface for adding unbalanced liquidity via a combination of a proportional add and a swap.
interface IAddUnbalancedLiquidityViaSwapRouter {
    struct AddLiquidityProportionalParams {
        uint256[] maxAmountsIn;
        uint256 exactBptAmountOut;
        bytes userData;
    }

    struct SwapExactInParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 exactAmountIn;
        uint256 minAmountOut;
        bytes userData;
    }

    struct SwapExactOutParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 exactAmountOut;
        uint256 maxAmountIn;
        bytes userData;
    }

    struct AddLiquidityAndSwapHookParams {
        AddLiquidityHookParams addLiquidityParams;
        SwapSingleTokenHookParams swapParams;
    }

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactIn swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return addLiquidityAmountsIn Array of amounts in for each token added to the pool
     * @return addLiquidityBptAmountOut Amount of BPT tokens received from the liquidity addition
     * @return swapAmountOut Amount of tokens received from the swap operation
     * @return addLiquidityReturnData Additional data returned from the add liquidity operation
     */
    function addUnbalancedLiquidityViaSwapExactIn(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    )
        external
        payable
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountOut,
            bytes memory addLiquidityReturnData
        );

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and an ExactOut swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return addLiquidityAmountsIn Array of amounts in for each token added to the pool
     * @return addLiquidityBptAmountOut Amount of BPT tokens received from the liquidity addition
     * @return swapAmountIn Amount of tokens used in the swap operation
     * @return addLiquidityReturnData Additional data returned from the add liquidity operation
     */
    function addUnbalancedLiquidityViaSwapExactOut(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    )
        external
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountIn,
            bytes memory addLiquidityReturnData
        );

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return addLiquidityAmountsIn Array of amounts in for each token added to the pool
     * @return addLiquidityBptAmountOut Amount of BPT tokens received from the liquidity
     * @return swapAmountOut Amount of tokens received from the swap operation
     * @return addLiquidityReturnData Additional data returned from the add liquidity operation
     */
    function queryAddUnbalancedLiquidityViaSwapExactIn(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactInParams calldata swapParams
    )
        external
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountOut,
            bytes memory addLiquidityReturnData
        );

    /**
     * @notice Queries an `addUnbalancedLiquidityViaSwapExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return addLiquidityAmountsIn Array of amounts in for each token added to the pool
     * @return addLiquidityBptAmountOut Amount of BPT tokens received from the liquidity
     * @return swapAmountIn Amount of tokens received from the swap operation
     * @return addLiquidityReturnData Additional data returned from the add liquidity operation
     */
    function queryAddUnbalancedLiquidityViaSwapExactOut(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapExactOutParams calldata swapParams
    )
        external
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountIn,
            bytes memory addLiquidityReturnData
        );
}
