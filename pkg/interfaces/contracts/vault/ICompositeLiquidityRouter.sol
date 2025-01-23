// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice The composite liquidity router supports add/remove liquidity operations on ERC4626 pools.
 * @dev This contract allow interacting with ERC4626 Pools (which contain wrapped ERC4626 tokens) using only underlying
 * standard tokens. For instance, with `addLiquidityUnbalancedToERC4626Pool` it is possible to add liquidity to an
 * ERC4626 Pool with [waDAI, waUSDC], using only DAI, only USDC, or an arbitrary amount of both. If the ERC4626 buffers
 * in the Vault have liquidity, these will be used to avoid wrapping/unwrapping through the wrapped token interface,
 * saving gas.
 *
 * For instance, adding only DAI to the pool above (and assuming an aDAI buffer with enough liquidity), would pull in
 * the DAI from the user, swap it for waDAI in the internal Vault buffer, and deposit the waDAI into the ERC4626 pool:
 * 1) without having to do any expensive ERC4626 wrapping operations; and
 * 2) without requiring the user to construct a batch operation containing the buffer swap.
 */
interface ICompositeLiquidityRouter {
    /// @notice `tokensOut` array does not have all the tokens from `expectedTokensOut`.
    error WrongTokensOut(address[] expectedTokensOut, address[] tokensOut);

    /***************************************************************************
                                   ERC4626 Pools
    ***************************************************************************/

    /**
     * @notice Add arbitrary amounts of tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before initializing or adding liquidity to
     * the "parent" pool, and also make sure limits are set properly.
     *
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or
     * used as a standard ERC20
     * @param exactAmountsIn Exact amounts of underlying/wrapped tokens in, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Add proportional amounts of tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before initializing or adding liquidity to
     * the "parent" pool, and also make sure limits are set properly.
     *
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or
     * used as a standard ERC20
     * @param maxAmountsIn Maximum amounts of underlying/wrapped tokens in, sorted in token registration order
     * wrapped tokens in the pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return tokensIn Actual tokens added to the pool
     * @return amountsIn Actual amounts of tokens added to the pool
     */
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (address[] memory tokensIn, uint256[] memory amountsIn);

    /**
     * @notice Remove proportional amounts of tokens from an ERC4626 pool, burning an exact pool token amount.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param unwrapWrapped Flags indicating whether the corresponding token should be unwrapped or
     * used as a standard ERC20
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of each token, corresponding to `tokensOut`
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for removing liquidity
     * @return tokensOut Actual tokens received
     * @return amountsOut Actual amounts of tokens received
     */
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (address[] memory tokensOut, uint256[] memory amountsOut);

    /**
     * @notice Queries an `addLiquidityUnbalancedToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or
     * used as a standard ERC20
     * @param exactAmountsIn Exact amounts of underlying/wrapped tokens in, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquidityProportionalToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param wrapUnderlying Flags indicating whether the corresponding token should be wrapped or
     * used as a standard ERC20
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return tokensIn Expected tokens added to the pool
     * @return amountsIn Expected amounts of tokens added to the pool
     */
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (address[] memory tokensIn, uint256[] memory amountsIn);

    /**
     * @notice Queries a `removeLiquidityProportionalFromERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param unwrapWrapped Flags indicating whether the corresponding token should be unwrapped or
     * used as a standard ERC20
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return tokensOut Expected tokens to receive
     * @return amountsOut Expected amounts of tokens to receive
     */
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external returns (address[] memory tokensOut, uint256[] memory amountsOut);
}
