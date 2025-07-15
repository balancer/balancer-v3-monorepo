// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

library BalancerLib {
    struct Context {
        IVault vault;
        IAggregatorRouter aggregatorRouter;
    }

    function createContext(address aggregatorRouter) internal view returns (Context memory) {
        return
            Context({
                vault: IRouterCommon(aggregatorRouter).getVault(),
                aggregatorRouter: IAggregatorRouter(aggregatorRouter)
            });
    }

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    function addLiquidityProportional(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut
    ) internal returns (uint256[] memory amountsIn) {
        return _addLiquidityProportional(context, pool, maxAmountsIn, exactBptAmountOut, bytes(""));
    }

    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) internal returns (uint256[] memory amountsIn) {
        return _addLiquidityProportional(createContext(msg.sender), pool, maxAmountsIn, exactBptAmountOut, userData);
    }

    function _addLiquidityProportional(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) private returns (uint256[] memory amountsIn) {
        IERC20[] memory tokens = context.vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeERC20.safeTransfer(tokens[i], address(context.vault), maxAmountsIn[i]);
        }

        return context.aggregatorRouter.addLiquidityProportional(pool, maxAmountsIn, exactBptAmountOut, userData);
    }

    function addLiquidityUnbalanced(
        Context memory context,
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut
    ) internal returns (uint256 bptAmountOut) {
        return _addLiquidityUnbalanced(context, pool, exactAmountsIn, minBptAmountOut, bytes(""));
    }

    function addLiquidityUnbalanced(
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) internal returns (uint256 bptAmountOut) {
        return _addLiquidityUnbalanced(createContext(msg.sender), pool, exactAmountsIn, minBptAmountOut, userData);
    }

    function _addLiquidityUnbalanced(
        Context memory context,
        address pool,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) private returns (uint256 bptAmountOut) {
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

    function addLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        uint256 exactAmountIn,
        uint256 minBptAmountOut
    ) internal returns (uint256 bptAmountOut) {
        return _addLiquiditySingleTokenExactOut(context, pool, tokenIn, exactAmountIn, minBptAmountOut, bytes(""));
    }

    function addLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        uint256 exactAmountIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) internal returns (uint256 bptAmountOut) {
        return _addLiquiditySingleTokenExactOut(context, pool, tokenIn, exactAmountIn, minBptAmountOut, userData);
    }

    function _addLiquiditySingleTokenExactOut(
        Context memory context,
        address pool,
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactBptAmountOut,
        bytes memory userData
    ) private returns (uint256 amountIn) {
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

    function donate(Context memory context, address pool, uint256[] memory amountsIn) internal {
        return _donate(context, pool, amountsIn, bytes(""));
    }

    function donate(Context memory context, address pool, uint256[] memory amountsIn, bytes memory userData) internal {
        return _donate(context, pool, amountsIn, userData);
    }

    function _donate(Context memory context, address pool, uint256[] memory amountsIn, bytes memory userData) private {
        IERC20[] memory tokens = context.vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeERC20.safeTransfer(tokens[i], address(context.vault), amountsIn[i]);
        }

        context.aggregatorRouter.donate(pool, amountsIn, userData);
    }

    function addLiquidityCustom(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return _addLiquidityCustom(context, pool, maxAmountsIn, minBptAmountOut, bytes(""));
    }

    function addLiquidityCustom(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        return _addLiquidityCustom(context, pool, maxAmountsIn, minBptAmountOut, userData);
    }

    function _addLiquidityCustom(
        Context memory context,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    ) private returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData) {
        IERC20[] memory tokens = context.vault.getPoolTokens(pool);
        for (uint256 i = 0; i < tokens.length; i++) {
            SafeERC20.safeTransfer(tokens[i], address(context.vault), maxAmountsIn[i]);
        }

        return context.aggregatorRouter.addLiquidityCustom(pool, maxAmountsIn, minBptAmountOut, userData);
    }
}
