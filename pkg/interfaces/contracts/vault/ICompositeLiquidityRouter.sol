// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice The composite liquidity router supports add/remove liquidity operations on ERC4626 and nested pools.
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
     * @notice Add arbitrary amounts of underlying tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before initializing or adding liquidity to
     * the "parent" pool, and also make sure limits are set properly.
     *
     * @param pool Address of the liquidity pool
     * @param useWrappedTokens An array indicating whether the input token is a wrapped or underlying token
     * @param exactAmountsIn Exact amounts of underlying/wrapped tokens in, sorted in token registration order
     * wrapped tokens in the pool
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory useWrappedTokens,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Add proportional amounts of underlying tokens to an ERC4626 pool through the buffer.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI). Ensure that any buffers associated
     * with the wrapped tokens in the ERC4626 pool have been initialized before initializing or adding liquidity to
     * the "parent" pool, and also make sure limits are set properly.
     *
     * @param pool Address of the liquidity pool
     * @param useWrappedTokens An array indicating whether the input token is a wrappe or underlying token
     * @param maxAmountsIn Maximum amounts of underlying/wrapped tokens in, sorted in token registration order
     * wrapped tokens in the pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for adding liquidity
     * @return underlyingAmountsIn Actual amounts of tokens added, sorted in token registration order of wrapped tokens
     * in the pool
     */
    function addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory useWrappedTokens,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory underlyingAmountsIn);

    /**
     * @notice Remove proportional amounts of underlying from an ERC4626 pool, burning an exact pool token amount.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param useWrappedTokens An array indicating whether the output token is a wrapper or underlying token
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of underlying tokens out, sorted in token registration order
     * wrapped tokens in the pool
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for removing liquidity
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     * tokens in the pool
     */
    function removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory useWrappedTokens,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);

    /**
     * @notice Queries an `addLiquidityUnbalancedToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param useWrappedTokens An array indicating whether the input token is a wrapped or underlying token
     * @param exactAmountsIn Exact amounts of underlying/wrapped tokens in, sorted in token registration order
     * wrapped tokens in the pool
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory useWrappedTokens,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquidityProportionalToERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param useWrappedTokens An array indicating whether the input token is a wrapper or underlying token
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return underlyingAmountsIn Expected amounts of tokens to add, sorted in token registration order of wrapped
     * tokens in the pool
     */
    function queryAddLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory useWrappedTokens,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory underlyingAmountsIn);

    /**
     * @notice Queries a `removeLiquidityProportionalFromERC4626Pool` operation without actually executing it.
     * @dev An "ERC4626 pool" contains IERC4626 yield-bearing tokens (e.g., waDAI).
     * @param pool Address of the liquidity pool
     * @param useWrappedTokens An array indicating whether the output token is a wrapper or underlying token
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the query
     * @return underlyingAmountsOut Expected amounts of tokens to receive, sorted in token registration order of
     * wrapped tokens in the pool
     */
    function queryRemoveLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory useWrappedTokens,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory underlyingAmountsOut);

    /***************************************************************************
                                   Nested pools
    ***************************************************************************/

    /**
     * @notice Adds liquidity unbalanced to a nested pool.
     * @dev A nested pool is one in which one or more tokens are BPTs from another pool (child pool). Since there are
     * multiple pools involved, the token order is not given, so the user must specify the preferred order to inform
     * the token in amounts.
     *
     * @param parentPool Address of the highest level pool (which contains BPTs of other pools)
     * @param tokensIn Input token addresses, sorted by user preference. `tokensIn` array must have all tokens from
     * child pools and all tokens that are not BPTs from the nested pool (parent pool).
     * @param exactAmountsIn Amount of each underlying token in, sorted according to tokensIn array
     * @param minBptAmountOut Expected minimum amount of parent pool tokens to receive
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for the operation
     * @return bptAmountOut Expected amount of parent pool tokens to receive
     */
    function addLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquidityUnbalancedNestedPool` operation without actually executing it.
     * @param parentPool Address of the highest level pool (which contains BPTs of other pools)
     * @param tokensIn Input token addresses, sorted by user preference. `tokensIn` array must have all tokens from
     * child pools and all tokens that are not BPTs from the nested pool (parent pool).
     * @param exactAmountsIn Amount of each underlying token in, sorted according to tokensIn array
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the operation
     * @return bptAmountOut Expected amount of parent pool tokens to receive
     */
    function queryAddLiquidityUnbalancedNestedPool(
        address parentPool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Removes liquidity of a nested pool.
     * @dev A nested pool is one in which one or more tokens are BPTs from another pool (child pool). Since there are
     * multiple pools involved, the token order is not given, so the user must specify the preferred order to inform
     * the token out amounts.
     *
     * @param parentPool Address of the highest level pool (which contains BPTs of other pools)
     * @param exactBptAmountIn Exact amount of `parentPool` tokens provided
     * @param tokensOut Output token addresses, sorted by user preference. `tokensOut` array must have all tokens from
     * child pools and all tokens that are not BPTs from the nested pool (parent pool). If not all tokens are informed,
     * balances are not settled and the operation reverts. Tokens that repeat must be informed only once.
     * @param minAmountsOut Minimum amounts of each outgoing underlying token, sorted according to tokensIn array
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional (optional) data required for the operation
     * @return amountsOut Actual amounts of tokens received, parallel to `tokensOut`
     */
    function removeLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);

    /**
     * @notice Queries an `removeLiquidityProportionalNestedPool` operation without actually executing it.
     * @param parentPool Address of the highest level pool (which contains BPTs of other pools)
     * @param exactBptAmountIn Exact amount of `parentPool` tokens provided
     * @param tokensOut Output token addresses, sorted by user preference. `tokensOut` array must have all tokens from
     * child pools and all tokens that are not BPTs from the nested pool (parent pool). If not all tokens are informed,
     * balances are not settled and the operation reverts. Tokens that repeat must be informed only once.
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data required for the operation
     * @return amountsOut Actual amounts of tokens received, parallel to `tokensOut`
     */
    function queryRemoveLiquidityProportionalNestedPool(
        address parentPool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        address sender,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);
}
