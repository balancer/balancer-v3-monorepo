// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { BaseBatchRouterE2ETest } from "./utils/BaseBatchRouterE2ETest.sol";

contract BatchRouterE2ETest is BaseBatchRouterE2ETest {
    /***************************************************************************
                                Test restrictions
    ***************************************************************************/

    function testSwapExactInDeadline() public {
        uint256 deadline = block.timestamp - 1;

        SwapPathExactAmountIn[] memory path = new SwapPathExactAmountIn[](0);

        expectRevertSwapExactIn(path, deadline, false, 0, abi.encodePacked(ISenderGuard.SwapDeadline.selector));
        expectRevertSwapExactIn(path, deadline, true, 0, abi.encodePacked(ISenderGuard.SwapDeadline.selector));
    }

    function testSwapExactOutDeadline() public {
        uint256 deadline = block.timestamp - 1;

        SwapPathExactAmountOut[] memory path = new SwapPathExactAmountOut[](0);

        expectRevertSwapExactOut(path, deadline, false, 0, abi.encodePacked(ISenderGuard.SwapDeadline.selector));
        expectRevertSwapExactOut(path, deadline, true, 0, abi.encodePacked(ISenderGuard.SwapDeadline.selector));
    }

    function testSwapExactInIfAmountOutLessThenMin() public {
        SwapPathExactAmountIn[] memory path = new SwapPathExactAmountIn[](1);
        path[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](1),
            exactAmountIn: DEFAULT_AMOUNT,
            minAmountOut: MAX_UINT256
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });

        expectRevertSwapExactIn(
            path,
            MAX_UINT128,
            false,
            0,
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT, MAX_UINT256)
        );
        expectRevertSwapExactIn(
            path,
            MAX_UINT128,
            true,
            DEFAULT_AMOUNT,
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT, MAX_UINT256)
        );
    }

    function testSwapExactOutIfAmountInMoreThanMax() public {
        SwapPathExactAmountOut[] memory path = new SwapPathExactAmountOut[](1);
        path[0] = SwapPathExactAmountOut({
            tokenIn: weth,
            steps: new SwapPathStep[](1),
            exactAmountOut: DEFAULT_AMOUNT,
            maxAmountIn: 0
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });

        expectRevertSwapExactOut(
            path,
            MAX_UINT128,
            false,
            0,
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT, 0)
        );
        expectRevertSwapExactOut(
            path,
            MAX_UINT128,
            true,
            DEFAULT_AMOUNT,
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT, 0)
        );
    }

    /***************************************************************************
                                    Swap
    ***************************************************************************/

    // ------ testSinglePath ------
    function testSinglePathExactIn() public {
        _testSinglePath(SwapKind.EXACT_IN, false);
    }

    function testSinglePathExactOut() public {
        _testSinglePath(SwapKind.EXACT_OUT, false);
    }

    function testSinglePathExactInETH() public {
        _testSinglePath(SwapKind.EXACT_IN, true);
    }

    function testSinglePathExactOutETH() public {
        _testSinglePath(SwapKind.EXACT_OUT, true);
    }

    function _testSinglePath(SwapKind kind, bool wethIsEth) internal {
        UniversalSwapPath[] memory path = new UniversalSwapPath[](1);
        path[0] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, wethIsEth ? DEFAULT_AMOUNT : 0, 0);
    }

    // ------ testSinglePathIntermediateFinalSteps ------
    function testSinglePathExactInIntermediateFinalSteps() public {
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_IN, false);
    }

    function testSinglePathExactInIntermediateFinalStepsETH() public {
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_IN, true);
    }

    function testSinglePathExactOutIntermediateFinalSteps() public {
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_OUT, false);
    }

    function testSinglePathExactOutIntermediateFinalStepsETH() public {
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_OUT, true);
    }

    function _testSinglePathIntermediateFinalSteps(SwapKind kind, bool wethIsEth) internal {
        UniversalSwapPath[] memory path = new UniversalSwapPath[](1);
        path[0] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](5),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });

        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });
        path[0].steps[2] = SwapPathStep({ pool: getPool(dai, weth), tokenOut: weth, isBuffer: false });
        path[0].steps[3] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[4] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, wethIsEth ? DEFAULT_AMOUNT : 0, 0);
    }

    // ------ testSwapMultiPathSISO ------
    function testSwapExactInMultiPathSISO() public {
        _testSwapMultiPathSISO(SwapKind.EXACT_IN, false);
    }

    function testSwapExactInMultiPathSISOWithETH() public {
        _testSwapMultiPathSISO(SwapKind.EXACT_IN, true);
    }

    function testSwapExactOutMultiPathSISO() public {
        _testSwapMultiPathSISO(SwapKind.EXACT_OUT, false);
    }

    function testSwapExactOutMultiPathSISOWithETH() public {
        _testSwapMultiPathSISO(SwapKind.EXACT_OUT, true);
    }

    function _testSwapMultiPathSISO(SwapKind kind, bool wethIsEth) internal {
        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](1),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[1].steps[0] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: dai, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, wethIsEth ? (2 * DEFAULT_AMOUNT) : 0, 0);
    }

    // ------ testSwapMultiPathMISO ------
    function testSwapExactInMultiPathMISO() public {
        _testSwapMultiPathMISO(SwapKind.EXACT_IN, false);
    }

    function testSwapExactInMultiPathMISOWithETH() public {
        _testSwapMultiPathMISO(SwapKind.EXACT_IN, true);
    }

    function testSwapExactOutMultiPathMISO() public {
        _testSwapMultiPathMISO(SwapKind.EXACT_OUT, false);
    }

    function testSwapExactOutMultiPathMISOWithETH() public {
        _testSwapMultiPathMISO(SwapKind.EXACT_OUT, true);
    }

    function _testSwapMultiPathMISO(SwapKind kind, bool wethIsEth) internal {
        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: dai,
            steps: new SwapPathStep[](1),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[1].steps[0] = SwapPathStep({ pool: getPool(dai, weth), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, 0, 0);
    }

    // ------ testSwapMultiPathSIMO ------
    function testSwapExactInMultiPathSIMO() public {
        _testSwapMultiPathSIMO(SwapKind.EXACT_IN, false);
    }

    function testSwapExactInMultiPathSIMOWithETH() public {
        _testSwapMultiPathSIMO(SwapKind.EXACT_IN, true);
    }

    function testSwapExactOutMultiPathSIMO() public {
        _testSwapMultiPathSIMO(SwapKind.EXACT_OUT, false);
    }

    function testSwapExactOutMultiPathSIMOWithETH() public {
        _testSwapMultiPathSIMO(SwapKind.EXACT_OUT, true);
    }

    function _testSwapMultiPathSIMO(SwapKind kind, bool wethIsEth) internal {
        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](1),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[1].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, wethIsEth ? (2 * DEFAULT_AMOUNT) : 0, 0);
    }

    // ------ testSwapMultiPathSIMO ------
    function testSwapExactInMultiPathMIMO() public {
        _testSwapMultiPathMIMO(SwapKind.EXACT_IN, false);
    }

    function testSwapExactInMultiPathMIMOWithETH() public {
        _testSwapMultiPathMIMO(SwapKind.EXACT_IN, true);
    }

    function testSwapExactOutMultiPathMIMO() public {
        _testSwapMultiPathMIMO(SwapKind.EXACT_OUT, false);
    }

    function testSwapExactOutMultiPathMIMOWithETH() public {
        _testSwapMultiPathMIMO(SwapKind.EXACT_OUT, true);
    }

    function _testSwapMultiPathMIMO(SwapKind kind, bool wethIsEth) internal {
        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: IERC20(getPool(weth, usdc)),
            steps: new SwapPathStep[](2),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });

        path[1].steps[0] = SwapPathStep({
            pool: getPool(getPool(weth, usdc), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });
        path[1].steps[1] = SwapPathStep({
            pool: getPool(getPool(usdc, dai), getPool(weth, dai)),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, 0, 0);
    }

    // ------ testSwapMultiPathCircular ------
    function testSwapExactInMultiPathCircular() public {
        _testSwapMultiPathCircular(SwapKind.EXACT_IN, false);
    }

    function testSwapExactInMultiPathCircularWithETH() public {
        _testSwapMultiPathCircular(SwapKind.EXACT_IN, true);
    }

    function testSwapExactOutMultiPathCircular() public {
        _testSwapMultiPathCircular(SwapKind.EXACT_OUT, false);
    }

    function testSwapExactOutMultiPathCircularWithETH() public {
        _testSwapMultiPathCircular(SwapKind.EXACT_OUT, true);
    }

    function _testSwapMultiPathCircular(SwapKind kind, bool wethIsEth) internal {
        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: dai,
            steps: new SwapPathStep[](1),
            givenAmount: DEFAULT_AMOUNT,
            limit: DEFAULT_AMOUNT
        });
        path[1].steps[0] = SwapPathStep({ pool: getPool(dai, weth), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, wethIsEth ? DEFAULT_AMOUNT : 0, 0);
    }
}
