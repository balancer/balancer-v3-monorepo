// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";
import { IVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";

import { CompositeLiquidityRouterERC4626PoolTest } from "./CompositeLiquidityRouterERC4626Pool.t.sol";

contract PrepaidCompositeLiquidityRouterERC4626PoolTest is CompositeLiquidityRouterERC4626PoolTest {
    function initQueryClrRouter() internal view override returns (ICompositeLiquidityRouter) {
        return ICompositeLiquidityRouter(address(prepaidCompositeLiquidityRouter));
    }

    function testCompositeLiquidityRouterVersion() public view override {
        assertEq(
            prepaidCompositeLiquidityRouter.version(),
            "Mock CompositeLiquidityRouter v1",
            "CL BatchRouter version mismatch"
        );
    }

    // Virtual functions

    function _addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        uint256 ethValue,
        bool wethIsEth,
        bytes memory userData,
        bytes memory expectedError
    ) internal override returns (uint256 bptAmountOut) {
        _sendTokensToVault(pool, wrapUnderlying, exactAmountsIn, wethIsEth);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            prepaidCompositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool{ value: ethValue }(
                pool,
                wrapUnderlying,
                exactAmountsIn,
                minBptAmountOut,
                wethIsEth,
                userData
            );
    }

    function _addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        uint256 ethValue,
        bool wethIsEth,
        bytes memory userData,
        bytes memory expectedError
    ) internal override returns (uint256[] memory) {
        _sendTokensToVault(pool, wrapUnderlying, maxAmountsIn, wethIsEth);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            prepaidCompositeLiquidityRouter.addLiquidityProportionalToERC4626Pool{ value: ethValue }(
                pool,
                wrapUnderlying,
                maxAmountsIn,
                exactBptAmountOut,
                wethIsEth,
                userData
            );
    }

    function _removeLiquidityProportionalFromERC4626Pool(
        address pool,
        bool[] memory unwrapWrapped,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData,
        bytes memory expectedError
    ) internal override returns (uint256[] memory) {
        IERC20(pool).approve(address(prepaidCompositeLiquidityRouter), exactBptAmountIn);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            prepaidCompositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
                pool,
                unwrapWrapped,
                exactBptAmountIn,
                minAmountsOut,
                wethIsEth,
                userData
            );
    }

    function _sendTokensToVault(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory amountsIn,
        bool wethIsEth
    ) private {
        IERC20[] memory poolTokens = vault.getPoolTokens(pool);

        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (amountsIn[i] == 0) {
                continue;
            }

            IERC20 effectiveToken = wrapUnderlying[i]
                ? IERC20(vault.getERC4626BufferAsset(IERC4626(address(poolTokens[i]))))
                : poolTokens[i];

            if (wethIsEth && address(effectiveToken) == address(weth)) {
                continue;
            }

            effectiveToken.transfer(address(vault), amountsIn[i]);
        }
    }
}
