// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseBatchRouterE2ETest } from "./utils/BaseBatchRouterE2ETest.sol";

contract BatchRouterE2ETest is BaseBatchRouterE2ETest {
    /***************************************************************************
                                    Swap Exact In
    ***************************************************************************/

    function testSwapExactInDeadline() public {
        uint256 deadline = block.timestamp - 1;

        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](0);

        expectRevertSwapExactIn(pathsExactIn, deadline, false, 0, abi.encodePacked(ISenderGuard.SwapDeadline.selector));
        expectRevertSwapExactIn(pathsExactIn, deadline, true, 0, abi.encodePacked(ISenderGuard.SwapDeadline.selector));
    }

    function testSwapExactInIfAmountOutLessThenMin() public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: MAX_UINT256
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });

        expectRevertSwapExactIn(
            pathsExactIn,
            MAX_UINT128,
            false,
            0,
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_EXACT_AMOUNT_IN, MAX_UINT256)
        );
        expectRevertSwapExactIn(
            pathsExactIn,
            MAX_UINT128,
            true,
            DEFAULT_EXACT_AMOUNT_IN,
            abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_EXACT_AMOUNT_IN, MAX_UINT256)
        );
    }

    function testSinglePathExactIn__Fuzz(bool wethIsEth) public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    function testSinglePathExactInIntermediateFinalSteps__Fuzz(bool wethIsEth) public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](5),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });

        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });
        pathsExactIn[0].steps[2] = SwapPathStep({ pool: getPool(dai, weth), tokenOut: weth, isBuffer: false });
        pathsExactIn[0].steps[3] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[4] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    function testExactInMultiPathSISO__Fuzz(bool wethIsEth) public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: dai, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? (2 * DEFAULT_EXACT_AMOUNT_IN) : 0, 0);
    }

    function testExactInMultiPathMISO__Fuzz(bool wethIsEth) public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = SwapPathStep({ pool: getPool(dai, weth), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testExactInMultiPathSIMO__Fuzz(bool wethIsEth) public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? (2 * DEFAULT_EXACT_AMOUNT_IN) : 0, 0);
    }

    function testExactInMultiPathMIMO__Fuzz(bool wethIsEth) public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(weth, usdc)),
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });

        pathsExactIn[1].steps[0] = SwapPathStep({
            pool: getPool(getPool(weth, usdc), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = SwapPathStep({
            pool: getPool(getPool(usdc, dai), getPool(weth, dai)),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testExactInMultiPathCircular__Fuzz(bool wethIsEth) public {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(usdc, dai), tokenOut: dai, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = SwapPathStep({ pool: getPool(dai, weth), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    /***************************************************************************
                                    Wrap / Unwrap Exact In
    ***************************************************************************/

    function _getWrapMinAmount(IERC4626 token, uint256 amountInUnderlying) internal returns (uint256 minAmountOut) {
        uint256 snapshot = vm.snapshotState();
        minAmountOut = _vaultPreviewDeposit(token, amountInUnderlying);
        vm.revertToState(snapshot);
    }

    function _getUnwrapMinAmount(IERC4626 token, uint256 amountInWrapped) internal returns (uint256 minAmountOut) {
        uint256 snapshot = vm.snapshotState();
        minAmountOut = _vaultPreviewRedeem(token, amountInWrapped);
        vm.revertToState(snapshot);
    }

    function testExactInWrapFirst__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = _getWrapMinAmount(waUSDC, DEFAULT_EXACT_AMOUNT_IN);

        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: address(waUSDC), tokenOut: waUSDC, isBuffer: true });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(waUSDC, weth), tokenOut: weth, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = SwapPathStep({ pool: address(waUSDC), tokenOut: waUSDC, isBuffer: true });
        pathsExactIn[1].steps[1] = SwapPathStep({ pool: getPool(waUSDC, weth), tokenOut: weth, isBuffer: false });

        // Ignore these tokens because the operation causes a rebalancing inside the Vault.
        ignoreVaultChangesForTokens[address(usdc)] = true;
        ignoreVaultChangesForTokens[address(waUSDC)] = true;
        generateSimpleDiffs(pathsExactIn);

        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testExactInUnwrapFirst__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = _getUnwrapMinAmount(waDAI, DEFAULT_EXACT_AMOUNT_IN);

        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: waDAI,
            steps: new SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[0].steps[2] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: waDAI,
            steps: new SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        pathsExactIn[1].steps[1] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[1].steps[2] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    /***************************************************************************
                                    Add Liquidity Exact In
    ***************************************************************************/

    function testJoinSwapExactInSinglePathAndInitialAddLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - ADD_LIQUIDITY_ROUNDING_ERROR;
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = SwapPathStep({
            pool: getPool(getPool(weth, usdc), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });

        generateSimpleDiffs(pathsExactIn);

        // We add additional diffs on top of the standard ones. This is related to the fact that we work with BPTs.
        addDiffForVault(IERC20(getPool(weth, usdc)), int256(minAmountOut));

        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    function testJoinSwapExactInSinglePathAndIntermediateAddLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - ADD_LIQUIDITY_ROUNDING_ERROR;
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: new SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[2] = SwapPathStep({
            pool: getPool(getPool(weth, dai), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });

        generateSimpleDiffs(pathsExactIn);

        // We add additional diffs on top of the standard ones. This is related to the fact that we work with BPTs.
        addDiffForVault(IERC20(getPool(weth, dai)), int256(minAmountOut));

        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testJoinSwapExactInMultiPathAndInitialFinalAddLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - ADD_LIQUIDITY_ROUNDING_ERROR;

        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({
            pool: getPool(dai, usdc),
            tokenOut: IERC20(getPool(dai, usdc)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = SwapPathStep({
            pool: getPool(getPool(dai, usdc), getPool(weth, usdc)),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        addPathAmountOut(minAmountOut);

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        pathsExactIn[1].steps[1] = SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        addPathAmountOut(minAmountOut);

        addDiffForAlice(dai, -int256(DEFAULT_EXACT_AMOUNT_IN * 2));
        addDiffForAlice(IERC20(getPool(weth, usdc)), int256(minAmountOut * 2));
        addAmountOut(IERC20(getPool(weth, usdc)), minAmountOut * 2);

        addDiffForVault(dai, int256(DEFAULT_EXACT_AMOUNT_IN * 2));
        addDiffForVault(IERC20(getPool(weth, usdc)), -int256(minAmountOut));
        addDiffForVault(IERC20(getPool(dai, usdc)), int256(minAmountOut));

        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    /***************************************************************************
                                    Remove Liquidity Exact In
    ***************************************************************************/

    function testExitSwapExactInSinglePathAndInitialRemoveLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(weth, usdc)),
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: weth, isBuffer: false });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: dai, isBuffer: false });
        addPathAmountOut(DEFAULT_MIN_AMOUNT_OUT);

        addDiffForAlice(IERC20(getPool(weth, usdc)), -int256(DEFAULT_EXACT_AMOUNT_IN));
        addDiffForAlice(dai, int256(DEFAULT_MIN_AMOUNT_OUT));

        addDiffForVault(dai, -int256(DEFAULT_MIN_AMOUNT_OUT));

        addAmountOut(dai, DEFAULT_MIN_AMOUNT_OUT);

        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testExitSwapExactInSinglePathAndIntermediateRemoveLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR;
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: IERC20(weth),
            steps: new SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: dai, isBuffer: false });
        pathsExactIn[0].steps[2] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, REMOVE_LIQUIDITY_DELTA);
    }

    function testExitSwapExactInSinglePathAndFinalRemoveLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](1);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: IERC20(dai),
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR
        });
        pathsExactIn[0].steps[0] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }

    function testExitSwapExactInMultiPathAndFinalRemoveLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR;
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: IERC20(dai),
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: weth, isBuffer: false });

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: IERC20(dai),
            steps: new SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = SwapPathStep({
            pool: getPool(getPool(usdc, dai), getPool(weth, usdc)),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        pathsExactIn[1].steps[2] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(pathsExactIn);

        // We add additional diffs on top of the standard ones. This is related to the fact that we work with BPTs.
        addDiffForVault(IERC20(getPool(usdc, dai)), int256(minAmountOut));
        addDiffForVault(IERC20(getPool(weth, usdc)), -int256(minAmountOut));

        testSwapExactIn(pathsExactIn, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }

    function testExitSwapExactInMultiPathAndIntermediateRemoveLiquidityStep__Fuzz(bool wethIsEth) public virtual {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR;
        SwapPathExactAmountIn[] memory pathsExactIn = new SwapPathExactAmountIn[](2);
        pathsExactIn[0] = SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(usdc, weth)),
            steps: new SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = SwapPathStep({
            pool: getPool(getPool(usdc, weth), getPool(weth, dai)),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        addPathAmountOut(minAmountOut);

        pathsExactIn[1] = SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(dai, usdc)),
            steps: new SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = SwapPathStep({
            pool: getPool(getPool(dai, usdc), getPool(usdc, weth)),
            tokenOut: IERC20(getPool(usdc, weth)),
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });
        addPathAmountOut(minAmountOut);

        addDiffForAlice(IERC20(getPool(usdc, weth)), -int256(DEFAULT_EXACT_AMOUNT_IN));
        addDiffForAlice(IERC20(getPool(weth, dai)), int256(minAmountOut));

        addDiffForAlice(IERC20(getPool(dai, usdc)), -int256(DEFAULT_EXACT_AMOUNT_IN));
        addDiffForAlice(weth, int256(minAmountOut));

        addDiffForVault(IERC20(getPool(weth, dai)), -int256(minAmountOut));
        addDiffForVault(IERC20(getPool(dai, usdc)), int256(DEFAULT_EXACT_AMOUNT_IN));
        addDiffForVault(weth, -int256(minAmountOut));

        addAmountOut(IERC20(getPool(weth, dai)), minAmountOut);
        addAmountOut(weth, minAmountOut);

        testSwapExactIn(pathsExactIn, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }
}
