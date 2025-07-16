// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

struct Context {
    IVault vault;
    IAggregatorRouter aggregatorRouter;
}

library BalancerLibOperations {
    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /**
     * @notice Adds liquidity to a pool with proportional token amounts, receiving an exact amount of pool tokens.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     */
    function addLiquidityProportional(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut
    ) internal returns (uint256[] memory amountsIn) {
        return addLiquidityProportional(context, pool, maxAmountsIn, exactBptAmountOut, bytes(""));
    }

    /**
     * @notice Adds liquidity to a pool with proportional token amounts, receiving an exact amount of pool tokens.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     */
    function addLiquidityProportional(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) internal returns (uint256[] memory amountsIn) {
        IERC20[] memory tokens = context.vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeERC20.safeTransfer(tokens[i], address(context.vault), maxAmountsIn[i]);
        }

        return context.aggregatorRouter.addLiquidityProportional(pool, maxAmountsIn, exactBptAmountOut, userData);
    }

    /**
     * @notice Adds liquidity to a pool with arbitrary token amounts.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalanced(
        Context memory context,
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut
    ) internal returns (uint256 bptAmountOut) {
        return addLiquidityUnbalanced(context, pool, exactAmountsIn, minBptAmountOut, bytes(""));
    }

    /**
     * @notice Adds liquidity to a pool with arbitrary token amounts.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return bptAmountOut Actual amount of pool tokens received
     */
    function addLiquidityUnbalanced(
        Context memory context,
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) internal returns (uint256 bptAmountOut) {
        IERC20[] memory tokens = context.vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 amountIn = exactAmountsIn[i];
            if (amountIn == 0) {
                continue;
            }

            SafeERC20.safeTransfer(tokens[i], address(context.vault), amountIn);
        }

        return context.aggregatorRouter.addLiquidityUnbalanced(pool, exactAmountsIn, minBptAmountOut, userData);
    }

    /**
     * @notice Adds liquidity to a pool in a single token, receiving an exact amount of pool tokens.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param maxAmountIn Maximum amount of tokens to be added
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @return amountIn Actual amount of tokens added
     */
    function addLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut
    ) internal returns (uint256 amountIn) {
        return addLiquiditySingleTokenExactOut(context, pool, tokenIn, maxAmountIn, exactBptAmountOut, bytes(""));
    }

    /**
     * @notice Adds liquidity to a pool in a single token, receiving an exact amount of pool tokens.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param maxAmountIn Maximum amount of tokens to be added
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountIn Actual amount of tokens added
     */
    function addLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        SafeERC20.safeTransfer(tokenIn, address(context.vault), maxAmountIn);

        return
            context.aggregatorRouter.addLiquiditySingleTokenExactOut(
                pool,
                tokenIn,
                maxAmountIn,
                exactBptAmountOut,
                userData
            );
    }

    /**
     * @notice Adds liquidity to a pool by donating the amounts in (no BPT out).
     * @dev To support donation, the pool config `enableDonation` flag must be set to true.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param amountsIn Amounts of tokens to be donated, sorted in token registration order
     */
    function donate(Context memory context, address pool, uint256[] memory amountsIn) internal {
        return donate(context, pool, amountsIn, bytes(""));
    }

    /**
     * @notice Adds liquidity to a pool by donating the amounts in (no BPT out).
     * @dev To support donation, the pool config `enableDonation` flag must be set to true.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param amountsIn Amounts of tokens to be donated, sorted in token registration order
     * @param userData Additional (optional) data sent with the request to donate liquidity
     */
    function donate(Context memory context, address pool, uint256[] memory amountsIn, bytes memory userData) internal {
        IERC20[] memory tokens = context.vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeERC20.safeTransfer(tokens[i], address(context.vault), amountsIn[i]);
        }

        context.aggregatorRouter.donate(pool, amountsIn, userData);
    }

    /**
     * @notice Adds liquidity to a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     * @return bptAmountOut Actual amount of pool tokens received
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function addLiquidityCustom(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return addLiquidityCustom(context, pool, maxAmountsIn, minBptAmountOut, bytes(""));
    }

    /**
     * @notice Adds liquidity to a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Minimum amount of pool tokens to be received
     * @param userData Additional (optional) data sent with the request to add liquidity
     * @return amountsIn Actual amounts of tokens added, sorted in token registration order
     * @return bptAmountOut Actual amount of pool tokens received
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function addLiquidityCustom(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        IERC20[] memory tokens = context.vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeERC20.safeTransfer(tokens[i], address(context.vault), maxAmountsIn[i]);
        }

        return context.aggregatorRouter.addLiquidityCustom(pool, maxAmountsIn, minBptAmountOut, userData);
    }

    /***************************************************************************
                                   Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Removes liquidity with proportional token amounts from a pool, burning an exact pool token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquidityProportional(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut
    ) internal returns (uint256[] memory amountsOut) {
        return removeLiquidityProportional(context, pool, exactBptAmountIn, minAmountsOut, bytes(""));
    }

    /**
     * @notice Removes liquidity with proportional token amounts from a pool, burning an exact pool token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     */
    function removeLiquidityProportional(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) internal returns (uint256[] memory amountsOut) {
        IERC20(pool).approve(address(context.aggregatorRouter), exactBptAmountIn);

        return context.aggregatorRouter.removeLiquidityProportional(pool, exactBptAmountIn, minAmountsOut, userData);
    }

    /**
     * @notice Removes liquidity from a pool via a single token, burning an exact pool token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param minAmountOut Minimum amount of tokens to be received
     * @return amountOut Actual amount of tokens received
     */
    function removeLiquiditySingleTokenExactIn(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        return removeLiquiditySingleTokenExactIn(context, pool, exactBptAmountIn, tokenOut, minAmountOut, bytes(""));
    }

    /**
     * @notice Removes liquidity from a pool via a single token, burning an exact pool token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param minAmountOut Minimum amount of tokens to be received
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return amountOut Actual amount of tokens received
     */
    function removeLiquiditySingleTokenExactIn(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        uint256 minAmountOut,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        IERC20(pool).approve(address(context.aggregatorRouter), exactBptAmountIn);

        return
            context.aggregatorRouter.removeLiquiditySingleTokenExactIn(
                pool,
                exactBptAmountIn,
                tokenOut,
                minAmountOut,
                userData
            );
    }

    /**
     * @notice Removes liquidity from a pool via a single token, specifying the exact amount of tokens to receive.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Exact amount of tokens to be received
     * @return bptAmountIn Actual amount of pool tokens burned
     */
    function removeLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        uint256 maxBptAmountIn,
        IERC20 tokenOut,
        uint256 exactAmountOut
    ) internal returns (uint256 bptAmountIn) {
        return removeLiquiditySingleTokenExactOut(context, pool, maxBptAmountIn, tokenOut, exactAmountOut, bytes(""));
    }

    /**
     * @notice Removes liquidity from a pool via a single token, specifying the exact amount of tokens to receive.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Exact amount of tokens to be received
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return bptAmountIn Actual amount of pool tokens burned
     */
    function removeLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        uint256 maxBptAmountIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        bytes memory userData
    ) internal returns (uint256 bptAmountIn) {
        IERC20(pool).approve(address(context.aggregatorRouter), maxBptAmountIn);

        return
            context.aggregatorRouter.removeLiquiditySingleTokenExactOut(
                pool,
                maxBptAmountIn,
                tokenOut,
                exactAmountOut,
                userData
            );
    }

    /**
     * @notice Removes liquidity from a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @return bptAmountIn Actual amount of pool tokens burned
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function removeLiquidityCustom(
        Context memory context,
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut
    ) internal returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        return removeLiquidityCustom(context, pool, maxBptAmountIn, minAmountsOut, bytes(""));
    }

    /**
     * @notice Removes liquidity from a pool with a custom request.
     * @dev The given maximum and minimum amounts given may be interpreted as exact depending on the pool type.
     * In any case the caller can expect them to be hard boundaries for the request.
     *
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Minimum amounts of tokens to be received, sorted in token registration order
     * @param userData Additional (optional) data sent with the request to remove liquidity
     * @return bptAmountIn Actual amount of pool tokens burned
     * @return amountsOut Actual amounts of tokens received, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function removeLiquidityCustom(
        Context memory context,
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) internal returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        IERC20(pool).approve(address(context.aggregatorRouter), maxBptAmountIn);

        return context.aggregatorRouter.removeLiquidityCustom(pool, maxBptAmountIn, minAmountsOut, userData);
    }

    /***************************************************************************
                                   Swaps
    ***************************************************************************/

    /**
     * @notice Executes a swap operation specifying an exact input token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap, after which it will revert
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) internal returns (uint256 amountOut) {
        return
            swapSingleTokenExactIn(context, pool, tokenIn, tokenOut, exactAmountIn, minAmountOut, deadline, bytes(""));
    }

    /**
     * @notice Executes a swap operation specifying an exact input token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param minAmountOut Minimum amount of tokens to be received
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data sent with the swap request
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function swapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        SafeERC20.safeTransfer(tokenIn, address(context.vault), exactAmountIn);

        return
            context.aggregatorRouter.swapSingleTokenExactIn(
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                minAmountOut,
                deadline,
                userData
            );
    }

    /**
     * @notice Executes a swap operation specifying an exact output token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param maxAmountIn Maximum amount of tokens to be sent
     * @param deadline Deadline for the swap, after which it will revert
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline
    ) internal returns (uint256 amountIn) {
        return
            swapSingleTokenExactOut(context, pool, tokenIn, tokenOut, exactAmountOut, maxAmountIn, deadline, bytes(""));
    }

    /**
     * @notice Executes a swap operation specifying an exact output token amount.
     * @param context Struct containing references required for Balancer interactions.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param maxAmountIn Maximum amount of tokens to be sent
     * @param deadline Deadline for the swap, after which it will revert
     * @param userData Additional (optional) data sent with the swap request
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function swapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        SafeERC20.safeTransfer(tokenIn, address(context.vault), maxAmountIn);

        return
            context.aggregatorRouter.swapSingleTokenExactOut(
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                maxAmountIn,
                deadline,
                userData
            );
    }
}

library BalancerLibQueries {
    /***************************************************************************
                                    Add liquidity
    ***************************************************************************/

    /**
     * @notice Queries an `addLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     */
    function queryAddLiquidityProportional(
        Context memory context,
        address pool,
        uint256 exactBptAmountOut,
        address sender
    ) internal returns (uint256[] memory amountsIn) {
        return queryAddLiquidityProportional(context, pool, exactBptAmountOut, sender, bytes(""));
    }

    /**
     * @notice Queries an `addLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountOut Exact amount of pool tokens to be received
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     */
    function queryAddLiquidityProportional(
        Context memory context,
        address pool,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256[] memory amountsIn) {
        return context.aggregatorRouter.queryAddLiquidityProportional(pool, exactBptAmountOut, sender, userData);
    }

    /**
     * @notice Queries an `addLiquidityUnbalanced` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalanced(
        Context memory context,
        address pool,
        uint256[] memory exactAmountsIn,
        address sender
    ) internal returns (uint256 bptAmountOut) {
        return queryAddLiquidityUnbalanced(context, pool, exactAmountsIn, sender);
    }

    /**
     * @notice Queries an `addLiquidityUnbalanced` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactAmountsIn Exact amounts of tokens to be added, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountOut Expected amount of pool tokens to receive
     */
    function queryAddLiquidityUnbalanced(
        Context memory context,
        address pool,
        uint256[] memory exactAmountsIn,
        address sender,
        bytes memory userData
    ) internal returns (uint256 bptAmountOut) {
        return context.aggregatorRouter.queryAddLiquidityUnbalanced(pool, exactAmountsIn, sender, userData);
    }

    /**
     * @notice Queries an `addLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param exactBptAmountOut Expected exact amount of pool tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return amountIn Expected amount of tokens to add
     */
    function queryAddLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        uint256 exactBptAmountOut,
        address sender
    ) internal returns (uint256 amountIn) {
        return queryAddLiquiditySingleTokenExactOut(context, pool, tokenIn, exactBptAmountOut, sender, bytes(""));
    }

    /**
     * @notice Queries an `addLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token used to add liquidity
     * @param exactBptAmountOut Expected exact amount of pool tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountIn Expected amount of tokens to add
     */
    function queryAddLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        uint256 exactBptAmountOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        return
            context.aggregatorRouter.queryAddLiquiditySingleTokenExactOut(
                pool,
                tokenIn,
                exactBptAmountOut,
                sender,
                userData
            );
    }

    /**
     * @notice Queries an `addLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Expected minimum amount of pool tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     * @return bptAmountOut Expected amount of pool tokens to receive
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryAddLiquidityCustom(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        address sender
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return queryAddLiquidityCustom(context, pool, maxAmountsIn, minBptAmountOut, sender, bytes(""));
    }

    /**
     * @notice Queries an `addLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxAmountsIn Maximum amounts of tokens to be added, sorted in token registration order
     * @param minBptAmountOut Expected minimum amount of pool tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsIn Expected amounts of tokens to add, sorted in token registration order
     * @return bptAmountOut Expected amount of pool tokens to receive
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryAddLiquidityCustom(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return context.aggregatorRouter.queryAddLiquidityCustom(pool, maxAmountsIn, minBptAmountOut, sender, userData);
    }

    /***************************************************************************
                                    Remove liquidity
    ***************************************************************************/

    /**
     * @notice Queries a `removeLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityProportional(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        address sender
    ) internal returns (uint256[] memory amountsOut) {
        return queryRemoveLiquidityProportional(context, pool, exactBptAmountIn, sender, bytes(""));
    }

    /**
     * @notice Queries a `removeLiquidityProportional` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     */
    function queryRemoveLiquidityProportional(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        address sender,
        bytes memory userData
    ) internal returns (uint256[] memory amountsOut) {
        return context.aggregatorRouter.queryRemoveLiquidityProportional(pool, exactBptAmountIn, sender, userData);
    }

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param tokenOut Token used to remove liquidity
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return amountOut Expected amount of tokens to receive
     */
    function queryRemoveLiquiditySingleTokenExactIn(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        address sender
    ) internal returns (uint256 amountOut) {
        return queryRemoveLiquiditySingleTokenExactIn(context, pool, exactBptAmountIn, tokenOut, sender, bytes(""));
    }

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactIn` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param exactBptAmountIn Exact amount of pool tokens provided for the query
     * @param tokenOut Token used to remove liquidity
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Expected amount of tokens to receive
     */
    function queryRemoveLiquiditySingleTokenExactIn(
        Context memory context,
        address pool,
        uint256 exactBptAmountIn,
        IERC20 tokenOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        return
            context.aggregatorRouter.queryRemoveLiquiditySingleTokenExactIn(
                pool,
                exactBptAmountIn,
                tokenOut,
                sender,
                userData
            );
    }

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Expected exact amount of tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return bptAmountIn Expected amount of pool tokens to burn
     */
    function queryRemoveLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender
    ) internal returns (uint256 bptAmountIn) {
        return queryRemoveLiquiditySingleTokenExactOut(context, pool, tokenOut, exactAmountOut, sender, bytes(""));
    }

    /**
     * @notice Queries a `removeLiquiditySingleTokenExactOut` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenOut Token used to remove liquidity
     * @param exactAmountOut Expected exact amount of tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountIn Expected amount of pool tokens to burn
     */
    function queryRemoveLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256 bptAmountIn) {
        return
            context.aggregatorRouter.queryRemoveLiquiditySingleTokenExactOut(
                pool,
                tokenOut,
                exactAmountOut,
                sender,
                userData
            );
    }

    /**
     * @notice Queries a `removeLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Expected minimum amounts of tokens to receive, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return bptAmountIn Expected amount of pool tokens to burn
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryRemoveLiquidityCustom(
        Context memory context,
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        address sender
    ) internal returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        return queryRemoveLiquidityCustom(context, pool, maxBptAmountIn, minAmountsOut, sender, bytes(""));
    }

    /**
     * @notice Queries a `removeLiquidityCustom` operation without actually executing it.
     * @param pool Address of the liquidity pool
     * @param maxBptAmountIn Maximum amount of pool tokens provided
     * @param minAmountsOut Expected minimum amounts of tokens to receive, sorted in token registration order
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return bptAmountIn Expected amount of pool tokens to burn
     * @return amountsOut Expected amounts of tokens to receive, sorted in token registration order
     * @return returnData Arbitrary (optional) data with an encoded response from the pool
     */
    function queryRemoveLiquidityCustom(
        Context memory context,
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData) {
        return
            context.aggregatorRouter.queryRemoveLiquidityCustom(pool, maxBptAmountIn, minAmountsOut, sender, userData);
    }

    /***************************************************************************
                                    Swap
    ***************************************************************************/

    /**
     * @notice Queries a swap operation specifying an exact input token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function querySwapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        address sender
    ) internal returns (uint256 amountOut) {
        return querySwapSingleTokenExactIn(context, pool, tokenIn, tokenOut, exactAmountIn, sender, bytes(""));
    }

    /**
     * @notice Queries a swap operation specifying an exact input token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountIn Exact amounts of input tokens to send
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountOut Calculated amount of output tokens to be received in exchange for the given input tokens
     */
    function querySwapSingleTokenExactIn(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        address sender,
        bytes memory userData
    ) internal returns (uint256 amountOut) {
        return
            context.aggregatorRouter.querySwapSingleTokenExactIn(
                pool,
                tokenIn,
                tokenOut,
                exactAmountIn,
                sender,
                userData
            );
    }

    /**
     * @notice Queries a swap operation specifying an exact output token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function querySwapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender
    ) internal returns (uint256 amountIn) {
        return querySwapSingleTokenExactOut(context, pool, tokenIn, tokenOut, exactAmountOut, sender, bytes(""));
    }

    /**
     * @notice Queries a swap operation specifying an exact output token amount without actually executing it.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amounts of input tokens to receive
     * @param sender The sender passed to the operation. It can influence results (e.g., with user-dependent hooks)
     * @param userData Additional (optional) data sent with the query request
     * @return amountIn Calculated amount of input tokens to be sent in exchange for the requested output tokens
     */
    function querySwapSingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        address sender,
        bytes memory userData
    ) internal returns (uint256 amountIn) {
        return
            context.aggregatorRouter.querySwapSingleTokenExactOut(
                pool,
                tokenIn,
                tokenOut,
                exactAmountOut,
                sender,
                userData
            );
    }
}
