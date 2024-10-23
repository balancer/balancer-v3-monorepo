// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AddLiquidityKind, RemoveLiquidityKind, SwapKind } from "./VaultTypes.sol";

/**
 * @notice The composite liquidity router supports add/remove liquidity operations on ERC4626 and nested pools.
 * @dev This contract allow interacting with ERC4626 Pools (which contain wrapped ERC4626 tokens) using only underlying
 * standard tokens. For instance, with `addLiquidityUnbalancedToERC4626Pool` it is possible to add liquidity to an
 * ERC4626 Pool with [waDAI, waUSDC], using only DAI, only USDC, or an arbitrary amount of both. If the ERC4626 buffers
 * in the Vault have liquidity, these will be used to avoid wrapping/unwrapping through the wrapped token interface,
 * saving gas.
 * For instance, adding only DAI to the pool above (and assuming an aDAI buffer with enough liquidity), would pull in
 * the DAI from the user, swap it for waDAI in the internal Vault buffer, and deposit the waDAI into the ERC4626 pool:
 * 1) without having to do any expensive ERC4626 wrapping operations; and
 * 2) without requiring the user to construct a batch operation containing the buffer swap.
 */
interface ICompositeLiquidityRouter {
    /// @notice `tokensOut` array does not have all the tokens from `expectedTokensOut`.
    error WrongTokensOut(address[] expectedTokensOut, address[] tokensOut);

    /**
     * @notice Struct to represent a nested pool add liquidity operation.
     * @param prevPool Address of the previous pool in the nested pool chain. Zero address if it is the main pool.
     * @param pool Address of the pool
     * @param tokensInAmounts Array of amounts of tokens to add to the nested pool
     * @param minBptAmountOut Minimum amount of BPT tokens to receive from the nested pool
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH
     * @param userData Additional (optional) data required for adding liquidity
     **/
    struct NestedPoolAddOperation {
        address prevPool;
        address pool;
        uint256[] tokensInAmounts;
        uint256 minBptAmountOut;
        bool wethIsEth;
        bytes userData;
    }

    struct AddLiquidityNestedPoolHookParams {
        address sender;
        address pool;
        NestedPoolAddOperation[] nestedPoolOperations;
    }

    /**
     * @notice Struct to represent a nested pool remove liquidity operation.
     * @param prevPool Address of the previous pool in the nested pool chain. Zero address if it is the main pool.
     * @param pool Address of the pool
     * @param minAmountsOut Array of minimum amounts of tokens to receive from the nested pool
     * @param wethIsEth If true, outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for removing liquidity
     */
    struct NestedPoolRemoveOperation {
        address prevPool;
        address pool;
        uint256[] minAmountsOut;
        bool wethIsEth;
        bytes userData;
    }

    struct RemoveLiquidityNestedPoolHookParams {
        address sender;
        address pool;
        uint256 targetPoolExactBptAmountIn;
        uint256 expectedAmountOutCount;
        NestedPoolRemoveOperation[] nestedPoolOperations;
    }

    /**
     * @notice Struct to represent a remove amount out operation.
     * @param pool Address of the pool
     * @param token Token to remove
     * @param amountOut Amount of token to remove
     */
    struct RemoveAmountOut {
        address pool;
        IERC20 token;
        uint256 amountOut;
    }

    /***************************************************************************
                                   ERC4626 Pools
    ***************************************************************************/

    /**
     * @notice Add proportional amounts of underlying tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param maxUnderlyingAmountsIn Maximum amounts of underlying tokens in, sorted in token registration order of
     * wrapped tokens in the pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return underlyingAmountsIn Actual amounts of tokens added, sorted in token registration order of wrapped tokens
     * in the pool
     */
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        uint256[] memory maxUnderlyingAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory underlyingAmountsIn);

    /**
     * @notice Queries an `addLiquidityProportionalToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return underlyingAmountsIn Expected amounts of tokens to add, sorted in token registration order of wrapped
     * tokens in the pool
     */
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory underlyingAmountsIn);

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /**
     * @notice Add liquidity to a main pool and nested pools in a single transaction.
     * @dev This function allows adding liquidity to a main pool and nested pools in a single transaction. The main pool is a pool that contains nested pools.
     * @param mainPool Address of the main pool
     * @param nestedPoolOperations Array of nested pool operations
     * @return bptAmountOut Amount of main pool BPT tokens received
     */
    function addLiquidityUnbalancedNestedPool(
        address mainPool,
        NestedPoolAddOperation[] calldata nestedPoolOperations
    ) external returns (uint256);

    /**
     * @notice Queries an `addLiquidityUnbalancedNestedPool` operation without actually executing it.
     * @dev This function allows querying for adding liquidity to the main pool and its nested pools in a single transaction. The main pool is a parent pool that contains nested pools.
     * @param mainPool Address of the main pool
     * @param nestedPoolOperations Array of nested pool operations
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @return bptAmountOut Expected amount of main pool BPT tokens to receive
     */
    function queryAddLiquidityUnbalancedNestedPool(
        address mainPool,
        NestedPoolAddOperation[] calldata nestedPoolOperations,
        address sender
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Remove liquidity from a main pool and nested pools in a single transaction.
     * @dev This function allows removing liquidity from a main pool and nested pools in a single transaction. The main pool is a pool that contains nested pools.
     * @param mainPool Address of the main pool
     * @param targetPoolExactBptAmountIn Exact amount of BPT tokens to remove from the main pool
     * @param expectedAmountOutCount Expected number of tokens to receive
     * @param nestedPoolOperations Array of nested pool operations
     * @return totalAmountsOut Array of amounts received from the main pool and nested pools
     */
    function removeLiquidityProportionalNestedPool(
        address mainPool,
        uint256 targetPoolExactBptAmountIn,
        uint256 expectedAmountOutCount,
        NestedPoolRemoveOperation[] calldata nestedPoolOperations
    ) external returns (RemoveAmountOut[] memory totalAmountsOut);

    /**
     * @notice Queries a `removeLiquidityProportionalNestedPool` operation without actually executing it.
     * @dev This function allows querying for removing liquidity from the main pool and its nested pools in a single transaction. The main pool is a parent pool that contains nested pools.
     * @param mainPool Address of the main pool
     * @param targetPoolExactBptAmountIn Exact amount of BPT tokens to remove from the main pool
     * @param expectedAmountOutCount Expected number of tokens to receive
     * @param sender The address passed to the operation as the sender. It influences results (e.g., with user-dependent hooks)
     * @param nestedPoolOperations Array of nested pool operations
     * @return totalAmountsOut Array of expected amounts to receive from the main pool and nested pools
     */
    function queryRemoveLiquidityProportionalNestedPool(
        address mainPool,
        uint256 targetPoolExactBptAmountIn,
        uint256 expectedAmountOutCount,
        address sender,
        NestedPoolRemoveOperation[] calldata nestedPoolOperations
    ) external returns (RemoveAmountOut[] memory totalAmountsOut);
}
