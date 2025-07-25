// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    ICompositeLiquidityRouterQueries
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterQueries.sol";
import { ICompositeLiquidityRouter } from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouter.sol";
import {
    ICompositeLiquidityRouterErrors
} from "@balancer-labs/v3-interfaces/contracts/vault/ICompositeLiquidityRouterErrors.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { AggregatorCompositeLiquidityRouter } from "../../contracts/AggregatorCompositeLiquidityRouter.sol";
import { CompositeLiquidityRouterNestedPoolsTest } from "./CompositeLiquidityRouterNestedPools.t.sol";

contract AggregatorCompositeLiquidityRouterNestedPoolsTest is CompositeLiquidityRouterNestedPoolsTest {
    mapping(address => bool) public _tokensToWrap;

    function initCLRouter() internal override {
        clrRouter = ICompositeLiquidityRouterQueries(address(aggregatorCompositeLiquidityRouter));
    }

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

            IERC20 effectiveToken = _tokensToWrap[tokensIn[i]] ? IERC20(tokensToWrap[i]) : IERC20(tokensIn[i]);
            effectiveToken.transfer(address(vault), exactAmountsIn[i]);
        }

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            AggregatorCompositeLiquidityRouter(payable(address(clrRouter))).addLiquidityUnbalancedNestedPool(
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

        IERC20(pool).approve(address(clrRouter), exactBptAmountIn);

        if (expectedError.length > 0) {
            vm.expectRevert(expectedError);
        }

        return
            AggregatorCompositeLiquidityRouter(payable(address(clrRouter))).removeLiquidityProportionalNestedPool(
                pool,
                exactBptAmountIn,
                tokensOut,
                minAmountsOut,
                tokensToUnwrap,
                userData
            );
    }
}
