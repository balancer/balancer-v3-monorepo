// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Asset } from "../solidity-utils/misc/Asset.sol";

import { IVault } from "./IVault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Interface for Router operations
 * @dev Description of the Router interface
 */
interface IRouter {
    /**
     * @notice Mints `amount` of `token`
     * @param token       The ERC20 token to mint
     * @param amount      The amount of token to mint
     */
    function mint(IERC20 token, uint256 amount) external;

    /**
     * @notice Burns `amount` of `token`
     * @param token       The ERC20 token to burn
     * @param amount      The amount of token to burn
     */
    function burn(IERC20 token, uint256 amount) external;

    /**
     * @notice Executes a swap operation
     * @param kind                  Type of swap
     * @param pool                  Address of the liquidity pool
     * @param assetIn               Asset to be swapped from
     * @param assetOut              Asset to be swapped to
     * @param amountGiven           Amount given based on kind of the swap
     * @param limit                 Maximum or minimum amount based on the kind of swap
     * @param deadline              Deadline for the swap
     * @param userData              Additional data required for the swap
     * @return amountCalculated     Amount calculated based on the kind of swap
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
     * @notice Contains parameters required for swap callback
     */
    struct SwapCallbackParams {
        /// @notice Address of the sender
        address sender;
        /// @notice Type of swap
        IVault.SwapKind kind;
        /// @notice Address of the liquidity pool
        address pool;
        /// @notice Asset to be swapped from
        Asset assetIn;
        /// @notice Asset to be swapped to
        Asset assetOut;
        /// @notice Amount given based on kind of the swap
        uint256 amountGiven;
        /// @notice Maximum or minimum amount based on the kind of swap
        uint256 limit;
        /// @notice Deadline for the swap
        uint256 deadline;
        /// @notice Additional data required for the swap
        bytes userData;
    }

    /**
     * @notice Adds liquidity to a pool
     * @param pool                  Address of the liquidity pool
     * @param assets                Array of assets to add
     * @param maxAmountsIn          Maximum amounts of assets to be added
     * @param minBptAmountOut       Minimum pool tokens to be received
     * @param userData              Additional data required for adding liquidity
     * @return amountsIn            Actual amounts of assets added
     * @return bptAmountOut         Pool tokens received
     */
    function addLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /// Contains parameters required for addLiquidity callback
    struct AddLiquidityCallbackParams {
        // Address of the sender
        address sender;
        // Address of the liquidity pool
        address pool;
        // Array of assets to add
        Asset[] assets;
        // Maximum amounts of assets to be added
        uint256[] maxAmountsIn;
        // Minimum pool tokens to be received
        uint256 minBptAmountOut;
        // Additional data required for adding liquidity
        bytes userData;
    }

    /**
     * @notice Removes liquidity from a pool
     * @param pool                  Address of the liquidity pool
     * @param assets                Array of assets to remove
     * @param minAmountsOut         Minimum amounts of assets to be received
     * @param bptAmountIn           Pool tokens provided
     * @param userData              Additional data required for removing liquidity
     * @return amountsOut           Actual amounts of assets received
     */
    function removeLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    /**
     * @notice Contains parameters required for removeLiquidity callback
     */
    struct RemoveLiquidityCallbackParams {
        /// @notice Address of the sender
        address sender;
        /// @notice Address of the liquidity pool
        address pool;
        /// @notice Array of assets to remove
        Asset[] assets;
        /// @notice Minimum amounts of assets to be received
        uint256[] minAmountsOut;
        /// @notice Pool tokens provided
        uint256 bptAmountIn;
        /// @notice Additional data required for removing liquidity
        bytes userData;
    }

    /**
     * @notice Queries a swap operation without executing it
     * @param kind                  Type of swap
     * @param pool                  Address of the liquidity pool
     * @param assetIn               Asset to be swapped from
     * @param assetOut              Asset to be swapped to
     * @param amountGiven           Amount given based on kind of the swap
     * @param userData              Additional data required for the query
     * @return amountCalculated     Amount calculated based on the kind of swap
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
     * @notice Queries addLiquidity operation without executing it
     * @param pool                  Address of the liquidity pool
     * @param assets                Array of assets to add
     * @param maxAmountsIn          Maximum amounts of assets to be added
     * @param minBptAmountOut       Minimum pool tokens expected
     * @param userData              Additional data required for the query
     * @return amountsIn            Expected amounts of assets to add
     * @return bptAmountOut         Expected pool tokens to receive
     */
    function queryAddLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Queries removeLiquidity operation without executing it
     * @param pool                  Address of the liquidity pool
     * @param assets                Array of assets to remove
     * @param minAmountsOut         Minimum amounts of assets expected
     * @param bptAmountIn           Pool tokens provided for the query
     * @param userData              Additional data required for the query
     * @return amountsOut           Expected amounts of assets to receive
     */
    function queryRemoveLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);
}
