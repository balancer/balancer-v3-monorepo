// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

library RouterAdaptor {

    function addLiquidity(
        IRouter router,
        address _pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IVault.AddLiquidityKind kind,
        bytes memory userData
    ) internal  returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        if (kind == IVault.AddLiquidityKind.PROPORTIONAL) {
            bptAmountOut = minBptAmountOut;
            amountsIn = router.addLiquidityProportional(_pool, maxAmountsIn, minBptAmountOut, false, userData);
        } else if (kind == IVault.AddLiquidityKind.UNBALANCED) {
            amountsIn = maxAmountsIn;
            bptAmountOut = router.addLiquidityUnbalanced(_pool, maxAmountsIn, minBptAmountOut, false, userData);
        } else if (kind == IVault.AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            bptAmountOut = minBptAmountOut;
            amountsIn = router.addLiquiditySingleTokenExactOut(_pool, 0, maxAmountsIn[0], minBptAmountOut, false, userData);
        } else if (kind == IVault.AddLiquidityKind.CUSTOM) {
            (amountsIn, bptAmountOut,) = router.addLiquidityCustom(_pool, maxAmountsIn, minBptAmountOut, false, userData);
        } else {
            revert("Unhandled add liquidity kind");
        }
    }

    function removeLiquidity(
        IRouter router,
        address _pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        IVault.RemoveLiquidityKind kind,
        bytes memory userData
    ) internal returns (uint256 bptAmountIn, uint256[] memory amountsOut) {
        if (kind == IVault.RemoveLiquidityKind.PROPORTIONAL) {
            bptAmountIn = maxBptAmountIn;
            amountsOut = router.removeLiquidityProportional(_pool, maxBptAmountIn, minAmountsOut, false, userData);
        } else if (kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN) {
            bptAmountIn = maxBptAmountIn;
            amountsOut = router.removeLiquiditySingleTokenExactIn(_pool, maxBptAmountIn, 0, minAmountsOut[0], false, userData);
        } else if (kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            amountsOut = minAmountsOut;
            bptAmountIn = router.removeLiquiditySingleTokenExactOut(_pool, maxBptAmountIn, 0, minAmountsOut[0], false, userData);
        } else if (kind == IVault.RemoveLiquidityKind.CUSTOM) {
            (bptAmountIn, amountsOut, ) = router.removeLiquidityCustom(_pool, maxBptAmountIn, minAmountsOut, false, userData);
        } else {
            revert("Unhandled remove liquidity kind");
        }
    }
}
