// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {
    ICompositeLiquidityRouterQueries
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterQueries.sol";
import { IVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";

import { AggregatorCompositeLiquidityRouter } from "../../contracts/AggregatorCompositeLiquidityRouter.sol";
import { CompositeLiquidityRouterNestedPoolsTest } from "./CompositeLiquidityRouterNestedPools.t.sol";

contract AggregatorCompositeLiquidityRouterNestedPoolsTest is CompositeLiquidityRouterNestedPoolsTest {
    function skipETHTests() internal pure override returns (bool) {
        return true;
    }

    // Virtual function
    function _addLiquidityUnbalancedNestedPool(
        address pool,
        address[] memory tokensIn,
        uint256[] memory exactAmountsIn,
        address[] memory tokensToWrap,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData,
        bytes memory expectedError
    ) internal override returns (uint256) {
        require(!wethIsEth, "WETH is not supported in this test");

        for (uint256 i = 0; i < tokensIn.length; i++) {
            if (exactAmountsIn[i] == 0) {
                continue;
            }

            IERC20(tokensIn[i]).transfer(address(vault), exactAmountsIn[i]);
        }

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            aggregatorCompositeLiquidityRouter.addLiquidityUnbalancedNestedPool(
                pool,
                tokensIn,
                exactAmountsIn,
                tokensToWrap,
                minBptAmountOut,
                userData
            );
    }

    function _removeLiquidityProportionalNestedPool(
        address pool,
        uint256 exactBptAmountIn,
        address[] memory tokensOut,
        uint256[] memory minAmountsOut,
        address[] memory tokensToUnwrap,
        bool wethIsEth,
        bytes memory userData,
        bytes memory expectedError
    ) internal override returns (uint256[] memory amountsOut) {
        require(!wethIsEth, "WETH is not supported in this test");

        IERC20(pool).approve(address(aggregatorCompositeLiquidityRouter), exactBptAmountIn);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            aggregatorCompositeLiquidityRouter.removeLiquidityProportionalNestedPool(
                pool,
                exactBptAmountIn,
                tokensOut,
                minAmountsOut,
                tokensToUnwrap,
                userData
            );
    }
}
