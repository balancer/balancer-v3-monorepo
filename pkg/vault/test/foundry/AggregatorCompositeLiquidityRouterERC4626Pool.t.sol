// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {
    ICompositeLiquidityRouterQueries
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterQueries.sol";
import { IVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";

import { AggregatorCompositeLiquidityRouter } from "../../contracts/AggregatorCompositeLiquidityRouter.sol";
import { CompositeLiquidityRouterERC4626PoolTest } from "./CompositeLiquidityRouterERC4626Pool.t.sol";

contract AggregatorCompositeLiquidityRouterERC4626PoolTest is CompositeLiquidityRouterERC4626PoolTest {
    function skipETHTests() internal pure override returns (bool) {
        return true;
    }

    function initQueryClrRouter() internal view override returns (ICompositeLiquidityRouterQueries) {
        return ICompositeLiquidityRouterQueries(address(aggregatorCompositeLiquidityRouter));
    }

    function testCompositeLiquidityRouterVersion() public view override {
        assertEq(
            aggregatorCompositeLiquidityRouter.version(),
            "Aggregator CompositeLiquidityRouter v1",
            "CL BatchRouter version mismatch"
        );
    }

    // Virtual functions

    function _addLiquidityUnbalancedToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory exactAmountsIn,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData,
        bytes memory expectedError
    ) internal override returns (uint256 bptAmountOut) {
        require(!wethIsEth, "WETH is not supported in this test");

        _sendTokensToVault(pool, wrapUnderlying, exactAmountsIn);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            aggregatorCompositeLiquidityRouter.addLiquidityUnbalancedToERC4626Pool(
                pool,
                wrapUnderlying,
                exactAmountsIn,
                minBptAmountOut,
                userData
            );
    }

    function _addLiquidityProportionalToERC4626Pool(
        address pool,
        bool[] memory wrapUnderlying,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData,
        bytes memory expectedError
    ) internal override returns (uint256[] memory) {
        require(!wethIsEth, "WETH is not supported in this test");

        _sendTokensToVault(pool, wrapUnderlying, maxAmountsIn);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            aggregatorCompositeLiquidityRouter.addLiquidityProportionalToERC4626Pool(
                pool,
                wrapUnderlying,
                maxAmountsIn,
                exactBptAmountOut,
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
        require(!wethIsEth, "WETH is not supported in this test");

        IERC20(pool).approve(address(aggregatorCompositeLiquidityRouter), exactBptAmountIn);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            aggregatorCompositeLiquidityRouter.removeLiquidityProportionalFromERC4626Pool(
                pool,
                unwrapWrapped,
                exactBptAmountIn,
                minAmountsOut,
                userData
            );
    }

    function _sendTokensToVault(address pool, bool[] memory wrapUnderlying, uint256[] memory amountsIn) private {
        IERC20[] memory poolTokens = vault.getPoolTokens(pool);

        for (uint256 i = 0; i < poolTokens.length; i++) {
            if (amountsIn[i] == 0) {
                continue;
            }

            IERC20 effectiveToken = wrapUnderlying[i]
                ? IERC20(vault.getERC4626BufferAsset(IERC4626(address(poolTokens[i]))))
                : poolTokens[i];

            effectiveToken.transfer(address(vault), amountsIn[i]);
        }
    }
}
