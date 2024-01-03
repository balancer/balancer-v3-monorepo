// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";
import { IBasePool } from "./IBasePool.sol";

interface IRouter {
    /// @dev Incoming ETH transfer from an address that is not WETH.
    error EthTransfer();

    /***************************************************************************
                               Pool Initialization
    ***************************************************************************/

    /**
     * @dev Data for the pool initialization callback
     * @param sender Account originating the pool initialization operation
     * @param pool Address of the liquidity pool
     * @param tokens Pool tokens
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @param userData Additional (optional) data required for adding initial liquidity
     */
    struct InitializeCallbackParams {
        address sender;
        address pool;
        IERC20[] tokens;
        uint256[] exactAmountsIn;
        uint256 minBptAmountOut;
        bool wethIsEth;
        bytes userData;
    }

    /**
     * @notice Initialize a liquidity pool.
     * @param pool Address of the liquidity pool
     * @param tokens Pool tokens
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @param userData Additional (optional) data required for adding liquidity
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

    /// @dev The amount of ETH paid is insufficient to complete this operation.
    error InsufficientEth();

    /**
     * @dev Data for the add liquidity callback.
     * @param sender Account originating the add liquidity operation
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param kind Type of join (e.g., single or multi-token)
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @param userData Additional (optional) data required for adding liquidity
     */
    struct AddLiquidityCallbackParams {
        address sender;
        address pool;
        uint256[] maxAmountsIn;
        uint256 minBptAmountOut;
        IVault.AddLiquidityKind kind;
        bool wethIsEth;
        bytes userData;
    }

    /// @dev The BPT amount received from adding liquidity is below the minimum specified for the operation.
    error BptAmountBelowMin(uint256 amount, uint256 limit);

    /// @dev A required amountIn exceeds the maximum limit specified in the join.
    error JoinAboveMax(uint256 amount, uint256 limit);

    /**
     * @notice Adds with arbitrary token amounts in to a pool.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @param userData Additional (optional) data required for adding liquidity
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
     * @notice Adds with a single token to a pool, receiving an exact amount of pool tokens.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param maxAmountIn Max amount tokens to be added
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @param userData Additional (optional) data required for adding liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     */
    function addLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn);

    /**
     * @notice Adds liquidity to a pool with a custom request.
     * @param pool Address of the liquidity pool
     * @param amountsInScaled18 Amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @param userData Additional (optional) data required for adding liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     * @return bptAmountOut Actual amount of pool tokens received
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function addLiquidityCustom(
        address pool,
        uint256[] memory amountsInScaled18,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @dev Data for the remove liquidity callback.
     * @param sender Account originating the remove liquidity operation
     * @param pool Address of the liquidity pool
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param kind Type of exit (e.g., single or multi-token)
     * @param wethIsEth If true, outgoing WETH will be unwrapped to ETH; otherwise the Vault will send WETH tokens
     * @param userData Additional (optional) data required for removing liquidity
     */
    struct RemoveLiquidityCallbackParams {
        address sender;
        address pool;
        uint256[] minAmountsOut;
        uint256 maxBptAmountIn;
        IVault.RemoveLiquidityKind kind;
        bool wethIsEth;
        bytes userData;
    }

    /// @dev The actual bptAmountOut is below the minimum limit specified in the exit.
    error ExitBelowMin(uint256 amount, uint256 limit);

    /**
     * @notice Removes liquidity with proportional token amounts from a pool, burning an exact pool token amount.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param wethIsEth If true, outgoing WETH will be unwrapped to ETH; otherwise the Vault will send WETH tokens
     * @param userData Additional (optional) data required for removing liquidity
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
     * @param wethIsEth If true, outgoing WETH will be unwrapped to ETH; otherwise the Vault will send WETH tokens
     * @param userData Additional (optional) data required for removing liquidity
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256[] memory amountsOut);

    /**
     * @notice Removes liquidity from a pool via a single token, specifying the exact amount of tokens to receive.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Exact amount of tokens to be received
     * @param wethIsEth If true, outgoing WETH will be unwrapped to ETH; otherwise the Vault will send WETH tokens
     * @param userData Additional (optional) data required for removing liquidity
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
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param wethIsEth If true, outgoing WETH will be unwrapped to ETH; otherwise the Vault will send WETH tokens
     * @param userData Additional (optional) data required for removing liquidity
     * @return bptAmountIn Actual amount of pool tokens burned
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function removeLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /**
     * @dev Data for the swap callback.
     * @param sender Account initiating the swap operation
     * @param kind Type of swap (given in or given out)
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param amountGiven Amount given based on kind of the swap (e.g., tokenIn for given in)
     * @param limit Maximum or minimum amount based on the kind of swap (e.g., maxAmountIn for given out)
     * @param deadline Deadline for the swap
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @param userData Additional (optional) data required for the swap
     */
    struct SwapCallbackParams {
        address sender;
        IVault.SwapKind kind;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256 limit;
        uint256 deadline;
        bool wethIsEth;
        bytes userData;
    }

    /// @dev The swap transaction was not mined before the specified deadline timestamp.
    error SwapDeadline();

    /// @dev An amount in or out has exceeded the limit specified in the swap request.
    error SwapLimit(uint256 amount, uint256 limit);

    /**
     * @notice Executes a swap operation specifying an exact input token amount.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap
     * @param userData Additional (optional) data required for the swap
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function swapExactIn(
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
     * @notice Executes a swap operation an exact output token amount.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param maxAmountIn Max amount tokens to be sent
     * @param deadline Deadline for the swap
     * @param userData Additional (optional) data required for the swap
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH; otherwise the Vault will pull WETH tokens
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function swapExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountIn);

    /***************************************************************************
                                     Queries
    ***************************************************************************/

    /**
     * @notice Queries an `addLiquidityUnbalanced` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Expected minimum amount of pool tokens to receive
     * @param userData Additional (optional) data required for the query
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256 bptAmountOut);

    /**
     * @notice Queries an `addLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param maxAmountIn Max amount tokens to be added
     * @param exactBptAmountOut Expected exact amount of pool tokens to receive
     * @param userData Additional (optional) data required for the query
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     */
    function queryAddLiquiditySingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn);

    /**
     * @notice Adds liquidity to a pool with a custom request.
     * @param pool Address of the liquidity pool
     * @param amountsInScaled18 Amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Expected minimum amount of pool tokens to receive
     * @param userData Additional (optional) data required for the query
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     * @return bptAmountOut Expected amount of pool tokens to receive
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function queryAddLiquidityCustom(
        address pool,
        uint256[] memory amountsInScaled18,
        uint256 minBptAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /**
     * @notice Queries `removeLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param minAmountsOut Expected minimum amounts of tokens to receive, sorted in token registration order
     * @param userData Additional (optional) data required for the query
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    /**
     * @notice Queries `removeLiquiditySingleTokenExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param tokenOut Token used to remove liquidity
     * @param minAmountOut Expected minimum amount of tokens to receive
     * @param userData Additional (optional) data required for the query
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquiditySingleTokenExactIn(
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut);

    /**
     * @notice Queries `removeLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Expected exact amount of tokens to receive
     * @param userData Additional (optional) data required for the query
     * @return bptAmountIn Expected amount of pool tokens to burn
     */
    function queryRemoveLiquiditySingleTokenExactOut(
        address pool,
        uint256 maxBptAmountIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bytes memory userData
    ) external returns (uint256 bptAmountIn);

    /**
     * @notice Queries `removeLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Expected minimum amounts of tokens to receive, sorted in token registration order
     * @param userData Additional (optional) data required for the query
     * @return bptAmountIn Expected amount of pool tokens to burn
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function queryRemoveLiquidityCustom(
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);

    /**
     * @notice Queries a swap operation specifying an exact input token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param userData Additional (optional) data required for the query
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function querySwapExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        bytes calldata userData
    ) external returns (uint256 amountOut);

    /**
     * @notice Queries a swap operation specifying an exact output token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param userData Additional (optional) data required for the query
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function querySwapExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bytes calldata userData
    ) external returns (uint256 amountIn);
}
