// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { BaseBatchRouterE2ETest } from "./utils/BaseBatchRouterE2ETest.sol";

contract BatchRouterE2ETest is BaseBatchRouterE2ETest {
    bool private constant USE_ETH_TRUE = true;
    bool private constant USE_ETH_FALSE = false;

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
        _testSinglePath(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testSinglePathExactOut() public {
        _testSinglePath(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testSinglePathExactInETH() public {
        _testSinglePath(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testSinglePathExactOutETH() public {
        _testSinglePath(SwapKind.EXACT_OUT, USE_ETH_TRUE);
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
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testSinglePathExactInIntermediateFinalStepsETH() public {
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testSinglePathExactOutIntermediateFinalSteps() public {
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testSinglePathExactOutIntermediateFinalStepsETH() public {
        _testSinglePathIntermediateFinalSteps(SwapKind.EXACT_OUT, USE_ETH_TRUE);
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
        _testSwapMultiPathSISO(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testSwapExactInMultiPathSISOWithETH() public {
        _testSwapMultiPathSISO(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testSwapExactOutMultiPathSISO() public {
        _testSwapMultiPathSISO(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testSwapExactOutMultiPathSISOWithETH() public {
        _testSwapMultiPathSISO(SwapKind.EXACT_OUT, USE_ETH_TRUE);
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
        _testSwapMultiPathMISO(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testSwapExactInMultiPathMISOWithETH() public {
        _testSwapMultiPathMISO(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testSwapExactOutMultiPathMISO() public {
        _testSwapMultiPathMISO(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testSwapExactOutMultiPathMISOWithETH() public {
        _testSwapMultiPathMISO(SwapKind.EXACT_OUT, USE_ETH_TRUE);
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
        _testSwapMultiPathSIMO(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testSwapExactInMultiPathSIMOWithETH() public {
        _testSwapMultiPathSIMO(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testSwapExactOutMultiPathSIMO() public {
        _testSwapMultiPathSIMO(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testSwapExactOutMultiPathSIMOWithETH() public {
        _testSwapMultiPathSIMO(SwapKind.EXACT_OUT, USE_ETH_TRUE);
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
        _testSwapMultiPathMIMO(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testSwapExactInMultiPathMIMOWithETH() public {
        _testSwapMultiPathMIMO(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testSwapExactOutMultiPathMIMO() public {
        _testSwapMultiPathMIMO(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testSwapExactOutMultiPathMIMOWithETH() public {
        _testSwapMultiPathMIMO(SwapKind.EXACT_OUT, USE_ETH_TRUE);
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
        _testSwapMultiPathCircular(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testSwapExactInMultiPathCircularWithETH() public {
        _testSwapMultiPathCircular(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testSwapExactOutMultiPathCircular() public {
        _testSwapMultiPathCircular(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testSwapExactOutMultiPathCircularWithETH() public {
        _testSwapMultiPathCircular(SwapKind.EXACT_OUT, USE_ETH_TRUE);
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

    /***************************************************************************
                                    Wrap / Unwrap Exact In
    ***************************************************************************/

    function _getWrapExactInAmount(
        IERC4626 token,
        uint256 amountInUnderlying
    ) internal returns (uint256 amountOutWrapped) {
        uint256 snapshot = vm.snapshotState();
        amountOutWrapped = _vaultPreviewDeposit(token, amountInUnderlying);
        vm.revertToState(snapshot);
    }

    function _getWrapExactOutAmount(
        IERC4626 token,
        uint256 amountOutWrapped
    ) internal returns (uint256 amountInUnderlying) {
        uint256 snapshot = vm.snapshotState();
        amountInUnderlying = _vaultPreviewMint(token, amountOutWrapped);
        vm.revertToState(snapshot);
    }

    function _getUnwrapExactInAmount(
        IERC4626 token,
        uint256 amountInWrapped
    ) internal returns (uint256 amountOutUnderlying) {
        uint256 snapshot = vm.snapshotState();
        amountOutUnderlying = _vaultPreviewRedeem(token, amountInWrapped);
        vm.revertToState(snapshot);
    }

    function _getUnwrapExactOutAmount(
        IERC4626 token,
        uint256 amountOutUnderlying
    ) internal returns (uint256 amountInWrapped) {
        uint256 snapshot = vm.snapshotState();
        amountInWrapped = _vaultPreviewWithdraw(token, amountOutUnderlying);
        vm.revertToState(snapshot);
    }

    // ------ testWrapFirst ------
    function testWrapExactInFirst() public {
        _testWrapFirst(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testWrapExactInFirstWithETH() public {
        _testWrapFirst(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function _testWrapFirst(SwapKind kind, bool wethIsEth) internal {
        uint256 givenAmount = DEFAULT_AMOUNT;
        uint256 limit = _getWrapExactInAmount(waUSDC, DEFAULT_AMOUNT);

        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: usdc,
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({ pool: address(waUSDC), tokenOut: waUSDC, isBuffer: true });
        path[0].steps[1] = SwapPathStep({ pool: getPool(waUSDC, weth), tokenOut: weth, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: usdc,
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[1].steps[0] = SwapPathStep({ pool: address(waUSDC), tokenOut: waUSDC, isBuffer: true });
        path[1].steps[1] = SwapPathStep({ pool: getPool(waUSDC, weth), tokenOut: weth, isBuffer: false });

        // Ignore these tokens because the operation causes a rebalancing inside the Vault.
        ignoreVaultChangesForTokens[address(usdc)] = true;
        ignoreVaultChangesForTokens[address(waUSDC)] = true;
        generateSimpleDiffs(path, kind);

        testSwap(path, kind, wethIsEth, 0, 0);
    }

    // ------ testUnwrapFirst ------
    function testUnwrapExactInFirst() public {
        _testUnwrapFirst(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testUnwrapExactInFirstWithETH() public {
        _testUnwrapFirst(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function _testUnwrapFirst(SwapKind kind, bool wethIsEth) internal {
        uint256 givenAmount = DEFAULT_AMOUNT;
        uint256 limit = _getUnwrapExactInAmount(waDAI, DEFAULT_AMOUNT);

        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: waDAI,
            steps: new SwapPathStep[](3),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        path[0].steps[1] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        path[0].steps[2] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: waDAI,
            steps: new SwapPathStep[](3),
            givenAmount: givenAmount,
            limit: limit
        });
        path[1].steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: dai, isBuffer: true });
        path[1].steps[1] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        path[1].steps[2] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, 0, 0);
    }

    /***************************************************************************
                                    Add Liquidity
    ***************************************************************************/

    // ------ _testJoinSwapSinglePathAndInitialAddLiquidityStep ------
    function testJoinSwapExactInSinglePathAndInitialAddLiquidityStep() public {
        _testJoinSwapSinglePathAndInitialAddLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testJoinSwapExactInSinglePathAndInitialAddLiquidityStepETH() public {
        _testJoinSwapSinglePathAndInitialAddLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testJoinSwapExactOutSinglePathAndInitialAddLiquidityStep() public {
        _testJoinSwapSinglePathAndInitialAddLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testJoinSwapExactOutSinglePathAndInitialAddLiquidityStepETH() public {
        _testJoinSwapSinglePathAndInitialAddLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testJoinSwapSinglePathAndInitialAddLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 givenAmount = kind == SwapKind.EXACT_IN
            ? DEFAULT_AMOUNT
            : DEFAULT_AMOUNT - ADD_LIQUIDITY_ROUNDING_ERROR;
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - ADD_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](1);
        path[0] = UniversalSwapPath({
            tokenIn: weth,
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        path[0].steps[1] = SwapPathStep({
            pool: getPool(getPool(weth, usdc), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });

        generateSimpleDiffs(path, kind);

        // We add additional diffs on top of the standard ones. This is related to the fact that we work with BPTs.
        addDiffForVault(IERC20(getPool(weth, usdc)), int256(limit));

        uint256 ethAmount = kind == SwapKind.EXACT_IN ? givenAmount : limit;
        testSwap(path, kind, wethIsEth, wethIsEth ? ethAmount : 0, ADD_LIQUIDITY_ROUNDING_ERROR);
    }

    // ------ _testJoinSwapSinglePathAndIntermediateAddLiquidityStep ------
    function testJoinSwapExactInSinglePathAndIntermediateAddLiquidityStep() public {
        _testJoinSwapSinglePathAndIntermediateAddLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testJoinSwapExactInSinglePathAndIntermediateAddLiquidityStepETH() public {
        _testJoinSwapSinglePathAndIntermediateAddLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testJoinSwapExactOutSinglePathAndIntermediateAddLiquidityStep() public {
        _testJoinSwapSinglePathAndIntermediateAddLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testJoinSwapExactOutSinglePathAndIntermediateAddLiquidityStepETH() public {
        _testJoinSwapSinglePathAndIntermediateAddLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testJoinSwapSinglePathAndIntermediateAddLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 givenAmount = kind == SwapKind.EXACT_IN
            ? DEFAULT_AMOUNT
            : DEFAULT_AMOUNT - ADD_LIQUIDITY_ROUNDING_ERROR;
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - ADD_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](1);
        path[0] = UniversalSwapPath({
            tokenIn: usdc,
            steps: new SwapPathStep[](3),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });
        path[0].steps[1] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        path[0].steps[2] = SwapPathStep({
            pool: getPool(getPool(weth, dai), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });

        generateSimpleDiffs(path, kind);

        // We add additional diffs on top of the standard ones. This is related to the fact that we work with BPTs.
        addDiffForVault(IERC20(getPool(weth, dai)), int256(limit));

        testSwap(path, kind, wethIsEth, 0, ADD_LIQUIDITY_ROUNDING_ERROR);
    }

    // ------ _testJoinSwapMultiPathAndInitialFinalAddLiquidityStep ------
    function testJoinSwapExactInMultiPathAndInitialFinalAddLiquidityStep() public {
        _testJoinSwapMultiPathAndInitialFinalAddLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testJoinSwapExactInMultiPathAndInitialFinalAddLiquidityStepETH() public {
        _testJoinSwapMultiPathAndInitialFinalAddLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testJoinSwapExactOutMultiPathAndInitialFinalAddLiquidityStep() public {
        _testJoinSwapMultiPathAndInitialFinalAddLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testJoinSwapExactOutMultiPathAndInitialFinalAddLiquidityStepETH() public {
        _testJoinSwapMultiPathAndInitialFinalAddLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testJoinSwapMultiPathAndInitialFinalAddLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 givenAmount = DEFAULT_AMOUNT;
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - ADD_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({
            pool: getPool(dai, usdc),
            tokenOut: IERC20(getPool(dai, usdc)),
            isBuffer: false
        });
        path[0].steps[1] = SwapPathStep({
            pool: getPool(getPool(dai, usdc), getPool(weth, usdc)),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        addExpectedPathAmount(limit);

        path[1] = UniversalSwapPath({
            tokenIn: dai,
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[1].steps[0] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });
        path[1].steps[1] = SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        addExpectedPathAmount(limit);

        addDiffForAlice(dai, -int256(givenAmount * 2));
        addDiffForAlice(IERC20(getPool(weth, usdc)), int256(limit * 2));
        addExpectedAmount(IERC20(getPool(weth, usdc)), limit * 2);

        addDiffForVault(dai, int256(givenAmount * 2));
        addDiffForVault(IERC20(getPool(weth, usdc)), -int256(limit));
        addDiffForVault(IERC20(getPool(dai, usdc)), int256(limit));

        testSwap(path, kind, wethIsEth, 0, 0);
    }

    /***************************************************************************
                                    Remove Liquidity
    ***************************************************************************/

    // ------ testExitSwapSinglePathAndInitialRemoveLiquidityStep ------
    function testExitSwapExactInSinglePathAndInitialRemoveLiquidityStep() public {
        _testExitSwapSinglePathAndInitialRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testExitSwapExactInSinglePathAndInitialRemoveLiquidityStepETH() public {
        _testExitSwapSinglePathAndInitialRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testExitSwapExactOutSinglePathAndInitialRemoveLiquidityStep() public {
        _testExitSwapSinglePathAndInitialRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testExitSwapExactOutSinglePathAndInitialRemoveLiquidityStepETH() public {
        _testExitSwapSinglePathAndInitialRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testExitSwapSinglePathAndInitialRemoveLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;
        uint256 givenAmount = kind == SwapKind.EXACT_IN
            ? DEFAULT_AMOUNT
            : DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](1);
        path[0] = UniversalSwapPath({
            tokenIn: IERC20(getPool(weth, usdc)),
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: weth, isBuffer: false });
        path[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: dai, isBuffer: false });
        addExpectedPathAmount(DEFAULT_AMOUNT);

        addDiffForAlice(IERC20(getPool(weth, usdc)), -int256(DEFAULT_AMOUNT));
        addDiffForAlice(dai, int256(DEFAULT_AMOUNT));

        addDiffForVault(dai, -int256(DEFAULT_AMOUNT));

        addExpectedAmount(dai, DEFAULT_AMOUNT);

        testSwap(path, kind, wethIsEth, 0, REMOVE_LIQUIDITY_ROUNDING_ERROR);
    }

    // ------ testExitSwapSinglePathAndIntermediateRemoveLiquidityStep ------
    function testExitSwapExactInSinglePathAndIntermediateRemoveLiquidityStep() public {
        _testExitSwapSinglePathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testExitSwapExactInSinglePathAndIntermediateRemoveLiquidityStepETH() public {
        _testExitSwapSinglePathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testExitSwapExactOutSinglePathAndIntermediateRemoveLiquidityStep() public {
        _testExitSwapSinglePathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testExitSwapExactOutSinglePathAndIntermediateRemoveLiquidityStepETH() public {
        _testExitSwapSinglePathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testExitSwapSinglePathAndIntermediateRemoveLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;
        uint256 givenAmount = kind == SwapKind.EXACT_IN
            ? DEFAULT_AMOUNT
            : DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](1);
        path[0] = UniversalSwapPath({
            tokenIn: IERC20(weth),
            steps: new SwapPathStep[](3),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        path[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: dai, isBuffer: false });
        path[0].steps[2] = SwapPathStep({ pool: getPool(dai, usdc), tokenOut: usdc, isBuffer: false });

        generateSimpleDiffs(path, kind);

        uint256 ethAmount = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT : limit;
        testSwap(path, kind, wethIsEth, wethIsEth ? ethAmount : 0, REMOVE_LIQUIDITY_DELTA);
    }

    // ------ testExitSwapSinglePathAndFinalRemoveLiquidityStep ------
    function testExitSwapExactInSinglePathAndFinalRemoveLiquidityStep() public {
        _testExitSwapSinglePathAndFinalRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testExitSwapExactInSinglePathAndFinalRemoveLiquidityStepETH() public {
        _testExitSwapSinglePathAndFinalRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testExitSwapExactOutSinglePathAndFinalRemoveLiquidityStep() public {
        _testExitSwapSinglePathAndFinalRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testExitSwapExactOutSinglePathAndFinalRemoveLiquidityStepETH() public {
        _testExitSwapSinglePathAndFinalRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testExitSwapSinglePathAndFinalRemoveLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;
        uint256 givenAmount = kind == SwapKind.EXACT_IN
            ? DEFAULT_AMOUNT
            : DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](1);
        path[0] = UniversalSwapPath({
            tokenIn: IERC20(dai),
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        path[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(path, kind);
        testSwap(path, kind, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }

    // ------ testExitSwapMultiPathAndFinalRemoveLiquidityStep ------
    function testExitSwapExactInMultiPathAndFinalRemoveLiquidityStep() public {
        _testExitSwapMultiPathAndFinalRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testExitSwapExactInMultiPathAndFinalRemoveLiquidityStepETH() public {
        _testExitSwapMultiPathAndFinalRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testExitSwapExactOutMultiPathAndFinalRemoveLiquidityStep() public {
        _testExitSwapMultiPathAndFinalRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testExitSwapExactOutMultiPathAndFinalRemoveLiquidityStepETH() public {
        _testExitSwapMultiPathAndFinalRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testExitSwapMultiPathAndFinalRemoveLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;
        uint256 givenAmount = kind == SwapKind.EXACT_IN
            ? DEFAULT_AMOUNT
            : DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: IERC20(dai),
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        path[0].steps[1] = SwapPathStep({ pool: getPool(weth, dai), tokenOut: weth, isBuffer: false });

        path[1] = UniversalSwapPath({
            tokenIn: IERC20(dai),
            steps: new SwapPathStep[](3),
            givenAmount: givenAmount,
            limit: limit
        });
        path[1].steps[0] = SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });
        path[1].steps[1] = SwapPathStep({
            pool: getPool(getPool(usdc, dai), getPool(weth, usdc)),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        path[1].steps[2] = SwapPathStep({ pool: getPool(weth, usdc), tokenOut: weth, isBuffer: false });

        generateSimpleDiffs(path, kind);

        // We add additional diffs on top of the standard ones. This is related to the fact that we work with BPTs.
        addDiffForVault(IERC20(getPool(usdc, dai)), int256(limit));
        addDiffForVault(IERC20(getPool(weth, usdc)), -int256(limit));

        testSwap(path, kind, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }

    // ------ testExitSwapMultiPathAndIntermediateRemoveLiquidityStep ------
    function testExitSwapExactInMultiPathAndIntermediateRemoveLiquidityStep() public {
        _testExitSwapMultiPathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_FALSE);
    }

    function testExitSwapExactInMultiPathAndIntermediateRemoveLiquidityStepETH() public {
        _testExitSwapMultiPathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_IN, USE_ETH_TRUE);
    }

    function testExitSwapExactOutMultiPathAndIntermediateRemoveLiquidityStep() public {
        _testExitSwapMultiPathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_FALSE);
    }

    function testExitSwapExactOutMultiPathAndIntermediateRemoveLiquidityStepETH() public {
        _testExitSwapMultiPathAndIntermediateRemoveLiquidityStep(SwapKind.EXACT_OUT, USE_ETH_TRUE);
    }

    function _testExitSwapMultiPathAndIntermediateRemoveLiquidityStep(SwapKind kind, bool wethIsEth) internal virtual {
        uint256 limit = kind == SwapKind.EXACT_IN ? DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR : DEFAULT_AMOUNT;
        uint256 givenAmount = kind == SwapKind.EXACT_IN
            ? DEFAULT_AMOUNT
            : DEFAULT_AMOUNT - REMOVE_LIQUIDITY_ROUNDING_ERROR;

        UniversalSwapPath[] memory path = new UniversalSwapPath[](2);
        path[0] = UniversalSwapPath({
            tokenIn: IERC20(getPool(usdc, weth)),
            steps: new SwapPathStep[](1),
            givenAmount: givenAmount,
            limit: limit
        });
        path[0].steps[0] = SwapPathStep({
            pool: getPool(getPool(usdc, weth), getPool(weth, dai)),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        addExpectedPathAmount(limit);

        path[1] = UniversalSwapPath({
            tokenIn: IERC20(getPool(dai, usdc)),
            steps: new SwapPathStep[](2),
            givenAmount: givenAmount,
            limit: limit
        });
        path[1].steps[0] = SwapPathStep({
            pool: getPool(getPool(dai, usdc), getPool(usdc, weth)),
            tokenOut: IERC20(getPool(usdc, weth)),
            isBuffer: false
        });
        path[1].steps[1] = SwapPathStep({ pool: getPool(usdc, weth), tokenOut: weth, isBuffer: false });
        addExpectedPathAmount(limit);

        addDiffForAlice(IERC20(getPool(usdc, weth)), -int256(givenAmount));
        addDiffForAlice(IERC20(getPool(weth, dai)), int256(limit));

        addDiffForAlice(IERC20(getPool(dai, usdc)), -int256(givenAmount));
        addDiffForAlice(weth, int256(limit));

        addDiffForVault(IERC20(getPool(weth, dai)), -int256(limit));
        addDiffForVault(IERC20(getPool(dai, usdc)), int256(givenAmount));
        addDiffForVault(weth, -int256(limit));

        addExpectedAmount(IERC20(getPool(weth, dai)), limit);
        addExpectedAmount(weth, limit);

        testSwap(path, kind, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }
}
