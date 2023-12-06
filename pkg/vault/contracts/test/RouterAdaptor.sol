// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";

library RouterAdaptor {
    function addLiquidity(
        IRouter router,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IVault.AddLiquidityKind kind,
        bytes memory userData
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        return addLiquidity(router, pool, maxAmountsIn, minBptAmountOut, kind, false, userData, 0);
    }

    function addLiquidity(
        IRouter router,
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        IVault.AddLiquidityKind kind,
        bool ethIsWeth,
        bytes memory userData,
        uint256 value
    ) internal returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        if (kind == IVault.AddLiquidityKind.PROPORTIONAL) {
            bptAmountOut = minBptAmountOut;
            amountsIn = router.addLiquidityProportional{ value: value }(
                pool,
                maxAmountsIn,
                minBptAmountOut,
                ethIsWeth,
                userData
            );
        } else if (kind == IVault.AddLiquidityKind.UNBALANCED) {
            amountsIn = maxAmountsIn;
            bptAmountOut = router.addLiquidityUnbalanced{ value: value }(
                pool,
                maxAmountsIn,
                minBptAmountOut,
                ethIsWeth,
                userData
            );
        } else if (kind == IVault.AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            bptAmountOut = minBptAmountOut;
            amountsIn = router.addLiquiditySingleTokenExactOut{ value: value }(
                pool,
                0,
                maxAmountsIn[0],
                minBptAmountOut,
                ethIsWeth,
                userData
            );
        } else if (kind == IVault.AddLiquidityKind.CUSTOM) {
            (amountsIn, bptAmountOut, ) = router.addLiquidityCustom{ value: value }(
                pool,
                maxAmountsIn,
                minBptAmountOut,
                ethIsWeth,
                userData
            );
        } else {
            revert("Unhandled add liquidity kind");
        }
    }

    function removeLiquidity(
        IRouter router,
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        IVault.RemoveLiquidityKind kind,
        bytes memory userData
    ) internal returns (uint256 bptAmountIn, uint256[] memory amountsOut) {
        return removeLiquidity(router, pool, maxBptAmountIn, minAmountsOut, kind, false, userData);
    }

    function removeLiquidity(
        IRouter router,
        address pool,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOut,
        IVault.RemoveLiquidityKind kind,
        bool ethIsWeth,
        bytes memory userData
    ) internal returns (uint256 bptAmountIn, uint256[] memory amountsOut) {
        if (kind == IVault.RemoveLiquidityKind.PROPORTIONAL) {
            bptAmountIn = maxBptAmountIn;
            amountsOut = router.removeLiquidityProportional(pool, maxBptAmountIn, minAmountsOut, ethIsWeth, userData);
        } else if (kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN) {
            bptAmountIn = maxBptAmountIn;
            amountsOut = router.removeLiquiditySingleTokenExactIn(
                pool,
                maxBptAmountIn,
                0,
                minAmountsOut[0],
                ethIsWeth,
                userData
            );
        } else if (kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            amountsOut = minAmountsOut;
            bptAmountIn = router.removeLiquiditySingleTokenExactOut(
                pool,
                maxBptAmountIn,
                0,
                minAmountsOut[0],
                ethIsWeth,
                userData
            );
        } else if (kind == IVault.RemoveLiquidityKind.CUSTOM) {
            (bptAmountIn, amountsOut, ) = router.removeLiquidityCustom(
                pool,
                maxBptAmountIn,
                minAmountsOut,
                ethIsWeth,
                userData
            );
        } else {
            revert("Unhandled remove liquidity kind");
        }
    }

    /// @dev Zero out all components but the first one for `SINGLE_TOKEN_EXACT_OUT`.
    function adaptMaxAmountsIn(
        IVault.AddLiquidityKind kind,
        uint256[] memory maxAmountsIn
    ) internal pure returns (uint256[] memory) {
        if (kind == IVault.AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT) {
            for (uint256 i = 1; i < maxAmountsIn.length; ++i) {
                maxAmountsIn[i] = 0;
            }
        }

        return maxAmountsIn;
    }

    /// @dev Zero out all components but the first one for `SINGLE_TOKEN_EXACT_IN` and `SINGLE_TOKEN_EXACT_OUT`.
    function adaptMinAmountsOut(
        IVault.RemoveLiquidityKind kind,
        uint256[] memory minAmountsOut
    ) internal pure returns (uint256[] memory) {
        if (
            kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN ||
            kind == IVault.RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT
        ) {
            for (uint256 i = 1; i < minAmountsOut.length; ++i) {
                minAmountsOut[i] = 0;
            }
        }

        return minAmountsOut;
    }
}
