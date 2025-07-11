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

    struct SwapParams {
        IERC20 tokenIn;
        IERC20 tokenOut;
        SwapKind kind;
        uint256 amountGiven;
        uint256 limit;
        bytes userData;
    }

    struct AddLiquidityAndSwapHookParams {
        AddLiquidityHookParams addLiquidityParams;
        SwapSingleTokenHookParams swapParams;
    }

    /**
     * @notice Adds liquidity to a pool with proportional token amounts and a swap in the same transaction.
     * @param pool Address of the liquidity pool
     * @param deadline Timestamp after which the transaction will revert
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return addLiquidityAmountsIn Array of amounts in for each token added to the pool
     * @return addLiquidityBptAmountOut Amount of BPT tokens received from the liquidity addition
     * @return swapAmountOut Amount of tokens received from the swap operation
     * @return addLiquidityReturnData Additional data returned from the add liquidity operation
     */
    function addUnbalancedLiquidityViaSwap(
        address pool,
        uint256 deadline,
        bool wethIsEth,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
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
     * @notice Queries an `addUnbalancedLiquidityViaSwap` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param addLiquidityParams Parameters for adding liquidity
     * @param swapParams Parameters for the swap operation
     * @return addLiquidityAmountsIn Array of amounts in for each token added to the pool
     * @return addLiquidityBptAmountOut Amount of BPT tokens received from the liquidity
     * @return swapAmountOut Amount of tokens received from the swap operation
     * @return addLiquidityReturnData Additional data returned from the add liquidity operation
     */
    function queryAddUnbalancedLiquidityViaSwap(
        address pool,
        address sender,
        AddLiquidityProportionalParams calldata addLiquidityParams,
        SwapParams calldata swapParams
    )
        external
        returns (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountOut,
            bytes memory addLiquidityReturnData
        );
}
