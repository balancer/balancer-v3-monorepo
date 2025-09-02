// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { MOCK_BATCH_ROUTER_VERSION } from "../../contracts/test/BatchRouterMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchSwapBaseTest is BaseVaultTest {
    using ArrayHelpers for *;
    using EnumerableSet for *;
    using EnumerableMap for *;

    uint256 constant DEFAULT_EXACT_AMOUNT_IN = 1e18;
    uint256 constant DEFAULT_MIN_AMOUNT_OUT = 1e18;
    uint256 constant ROUNDING_ERROR = 2;
    uint256 constant REMOVE_LIQUIDITY_ROUNDING_ERROR = 4000;
    uint256 constant REMOVE_LIQUIDITY_DELTA = 1e4;
    uint256 constant WRAPPED_TOKEN_AMOUNT = 1e6 * 1e18;

    mapping(address => mapping(address => address)) _pools; // TODO:

    EnumerableMap.AddressToUintMap _amountsOut;
    uint256[] _pathAmountsOut;

    IERC20[] _tokens;
    mapping(address => int256) _vaultTokenBalancesDiff;
    mapping(address => int256) _aliceTokenBalancesDiff;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _createTokens();
        _deployPools();
    }

    // function isPrepaid() internal virtual returns (bool);

    function getPool(IERC20 tokenA, IERC20 tokenB) internal view returns (address) {
        return getPool(address(tokenA), address(tokenB));
    }

    function getPool(address tokenA, address tokenB) internal view returns (address pool) {
        pool = _pools[tokenA][tokenB];
        if (pool != address(0)) {
            return pool;
        }

        pool = _pools[tokenB][tokenA];
        if (pool != address(0)) {
            return pool;
        }

        if (pool == address(0)) {
            revert("Test error: Pool not found");
        }

        return pool;
    }

    function _createTokens() private {
        _tokens.push(dai);
        _tokens.push(usdc);
        _tokens.push(weth);

        vm.startPrank(lp);
        bufferRouter.initializeBuffer(waDAI, WRAPPED_TOKEN_AMOUNT, 0, 0);
        bufferRouter.initializeBuffer(waUSDC, WRAPPED_TOKEN_AMOUNT, 0, 0);
        vm.stopPrank();
    }

    function _createPoolAndSet(address tokenA, address tokenB, string memory poolName) private returns (address pool) {
        (pool, ) = _createPool([tokenA, tokenB].toMemoryArray(), poolName);
        _pools[tokenA][tokenB] = pool;
        _pools[tokenB][tokenA] = pool;

        approveForPool(IERC20(pool));
        _tokens.push(IERC20(pool));

        return pool;
    }

    function _deployPools() internal {
        // Create test pools
        address poolWethDai = _createPoolAndSet(address(weth), address(dai), "Pool WETH/DAI");
        address poolDaiUsdc = _createPoolAndSet(address(dai), address(usdc), "Pool DAI/USDC");
        address poolWethUsdc = _createPoolAndSet(address(weth), address(usdc), "Pool WETH/USDC");

        // address firstPoolWithWrappedAsset = _createPoolAndSet(address(wrappedUsdc), address(weth), "wUSDC/WETH Pool");
        // address secondPoolWithWrappedAsset = _createPoolAndSet(address(wrappedDai), address(weth), "wDAI/WETH Pool");

        address firstNestedPool = _createPoolAndSet(poolWethDai, poolDaiUsdc, "firstNestedPool");
        address secondNestedPool = _createPoolAndSet(poolDaiUsdc, poolWethUsdc, "secondNestedPool");
        address thirdNestedPool = _createPoolAndSet(poolWethDai, poolWethUsdc, "thirdNestedPool");

        vm.startPrank(lp);
        _initPool(poolWethDai, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);
        _initPool(poolDaiUsdc, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);
        _initPool(poolWethUsdc, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);

        // _initPool(firstPoolWithWrappedAsset, [WRAPPED_TOKEN_AMOUNT, WRAPPED_TOKEN_AMOUNT].toMemoryArray(), 0);
        // _initPool(secondPoolWithWrappedAsset, [WRAPPED_TOKEN_AMOUNT, WRAPPED_TOKEN_AMOUNT].toMemoryArray(), 0);

        _initPool(firstNestedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(secondNestedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(thirdNestedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);

        IERC20(poolWethDai).transfer(alice, IERC20(poolWethDai).balanceOf(lp));
        IERC20(poolDaiUsdc).transfer(alice, IERC20(poolDaiUsdc).balanceOf(lp));
        IERC20(poolWethUsdc).transfer(alice, IERC20(poolWethUsdc).balanceOf(lp));

        vm.stopPrank();
    }

    function _queryExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn
    ) internal returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) {
        uint256 snapshot = vm.snapshotState();

        _prankStaticCall();
        (pathAmountsOut, tokensOut, amountsOut) = batchRouter.querySwapExactIn(pathsExactIn, address(0), bytes(""));

        vm.revertToState(snapshot);
    }

    /***************************************************************************
                                    Swap Exact In
    ***************************************************************************/

    function testSwapExactInDeadline() public {
        uint256 deadline = block.timestamp - 1;

        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](0);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        batchRouter.swapExactIn(pathsExactIn, deadline, false, bytes(""));

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        batchRouter.swapExactIn(pathsExactIn, deadline, true, bytes(""));
    }

    function testSwapExactInIfAmountOutLessThenMin() public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: MAX_UINT256
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });

        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_EXACT_AMOUNT_IN, MAX_UINT256));
        batchRouter.swapExactIn(pathsExactIn, MAX_UINT128, false, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_EXACT_AMOUNT_IN, MAX_UINT256));
        batchRouter.swapExactIn(pathsExactIn, MAX_UINT128, true, bytes(""));

        vm.stopPrank();
    }

    function testSinglePathExactIn__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: dai,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    function testSinglePathExactInIntermediateFinalSteps__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](5),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });

        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: dai,
            isBuffer: false
        });
        pathsExactIn[0].steps[2] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, weth),
            tokenOut: weth,
            isBuffer: false
        });
        pathsExactIn[0].steps[3] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[4] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: dai,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    function testExactInMultiPathSISO__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: dai,
            isBuffer: false
        });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: dai,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? (2 * DEFAULT_EXACT_AMOUNT_IN) : 0, 0);
    }

    function testExactInMultiPathMISO__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, weth),
            tokenOut: weth,
            isBuffer: false
        });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, weth),
            tokenOut: weth,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testExactInMultiPathSIMO__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: dai,
            isBuffer: false
        });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? (2 * DEFAULT_EXACT_AMOUNT_IN) : 0, 0);
    }

    function testExactInMultiPathMIMO__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, weth),
            tokenOut: weth,
            isBuffer: false
        });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(weth, usdc)),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });

        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(weth, usdc), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(usdc, dai), getPool(weth, dai)),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testExactInMultiPathCircular__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: dai,
            isBuffer: false
        });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, weth),
            tokenOut: weth,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    /***************************************************************************
                                    Wrap / Unwrap Exact In
    ***************************************************************************/

    function testExactInWrapFirst() public {}

    function testExactInUnwrapFirst() public {}

    function testExactInUnwrapFirstWrapEnd() public {}

    function testExactInWrapFirstUnwrapEnd() public {}

    /***************************************************************************
                                    Add Liquidity Exact In
    ***************************************************************************/

    function testJoinSwapExactInSinglePathAndInitialAddLiquidityStep__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - ROUNDING_ERROR;
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: weth,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(weth, usdc), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn); // TODO
        _addDiffForVault(IERC20(getPool(weth, usdc)), int256(minAmountOut)); // TODO

        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, 0);
    }

    function testJoinSwapExactInSinglePathAndIntermediateAddLiquidityStep__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - ROUNDING_ERROR;
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: usdc,
            steps: new IBatchRouter.SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, weth),
            tokenOut: weth,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[2] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(weth, dai), getPool(usdc, dai)),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn); // TODO
        _addDiffForVault(IERC20(getPool(weth, dai)), int256(minAmountOut)); // TODO

        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testJoinSwapExactInMultiPathAndInitialFinalAddLiquidityStep__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - ROUNDING_ERROR;

        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, usdc),
            tokenOut: IERC20(getPool(dai, usdc)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(dai, usdc), getPool(weth, usdc)),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        _addPathAmountOut(minAmountOut);

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, usdc),
            tokenOut: usdc,
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        _addPathAmountOut(minAmountOut);

        _addDiffForAlice(dai, -int256(DEFAULT_EXACT_AMOUNT_IN * 2));
        _addDiffForAlice(IERC20(getPool(weth, usdc)), int256(minAmountOut * 2));
        _addAmountOut(IERC20(getPool(weth, usdc)), minAmountOut * 2);

        _addDiffForVault(dai, int256(DEFAULT_EXACT_AMOUNT_IN * 2));
        _addDiffForVault(IERC20(getPool(weth, usdc)), -int256(minAmountOut)); //TODO
        _addDiffForVault(IERC20(getPool(dai, usdc)), int256(minAmountOut)); //TODO

        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    /***************************************************************************
                                    Remove Liquidity Exact In
    ***************************************************************************/

    function testExitSwapExactInSinglePathAndInitialRemoveLiquidityStep__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(weth, usdc)),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: weth,
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: dai,
            isBuffer: false
        });
        _addPathAmountOut(DEFAULT_MIN_AMOUNT_OUT);

        _addDiffForAlice(IERC20(getPool(weth, usdc)), -int256(DEFAULT_EXACT_AMOUNT_IN));
        _addDiffForAlice(dai, int256(DEFAULT_MIN_AMOUNT_OUT));

        _addDiffForVault(dai, -int256(DEFAULT_MIN_AMOUNT_OUT));

        _addAmountOut(dai, DEFAULT_MIN_AMOUNT_OUT);

        testSwapExactIn(pathsExactIn, wethIsEth, 0, 0);
    }

    function testExitSwapExactInSinglePathAndIntermediateRemoveLiquidityStep__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR;
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(weth),
            steps: new IBatchRouter.SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: dai,
            isBuffer: false
        });
        pathsExactIn[0].steps[2] = IBatchRouter.SwapPathStep({
            pool: getPool(dai, usdc),
            tokenOut: usdc,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, wethIsEth ? DEFAULT_EXACT_AMOUNT_IN : 0, REMOVE_LIQUIDITY_DELTA);
    }

    function testExitSwapExactInSinglePathAndFinalRemoveLiquidityStep__Fuzz(bool wethIsEth) public {
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](1);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(dai),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: weth,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn);
        testSwapExactIn(pathsExactIn, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }

    function testExitSwapExactInMultiPathAndFinalRemoveLiquidityStep__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR;
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(dai),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        pathsExactIn[0].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, dai),
            tokenOut: weth,
            isBuffer: false
        });

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(dai),
            steps: new IBatchRouter.SwapPathStep[](3),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, dai),
            tokenOut: IERC20(getPool(usdc, dai)),
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(usdc, dai), getPool(weth, usdc)),
            tokenOut: IERC20(getPool(weth, usdc)),
            isBuffer: false
        });
        pathsExactIn[1].steps[2] = IBatchRouter.SwapPathStep({
            pool: getPool(weth, usdc),
            tokenOut: weth,
            isBuffer: false
        });

        _generateSimpleDiffs(pathsExactIn); // TODO
        _addDiffForVault(IERC20(getPool(usdc, dai)), int256(minAmountOut)); //TODO
        _addDiffForVault(IERC20(getPool(weth, usdc)), -int256(minAmountOut)); //TODO

        testSwapExactIn(pathsExactIn, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }

    function testExitSwapExactInMultiPathAndIntermediateRemoveLiquidityStep__Fuzz(bool wethIsEth) public {
        uint256 minAmountOut = DEFAULT_MIN_AMOUNT_OUT - REMOVE_LIQUIDITY_ROUNDING_ERROR;
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn = new IBatchRouter.SwapPathExactAmountIn[](2);
        pathsExactIn[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(usdc, weth)),
            steps: new IBatchRouter.SwapPathStep[](1),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[0].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(usdc, weth), getPool(weth, dai)),
            tokenOut: IERC20(getPool(weth, dai)),
            isBuffer: false
        });
        _addPathAmountOut(minAmountOut);

        pathsExactIn[1] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(getPool(dai, usdc)),
            steps: new IBatchRouter.SwapPathStep[](2),
            exactAmountIn: DEFAULT_EXACT_AMOUNT_IN,
            minAmountOut: minAmountOut
        });
        pathsExactIn[1].steps[0] = IBatchRouter.SwapPathStep({
            pool: getPool(getPool(dai, usdc), getPool(usdc, weth)),
            tokenOut: IERC20(getPool(usdc, weth)),
            isBuffer: false
        });
        pathsExactIn[1].steps[1] = IBatchRouter.SwapPathStep({
            pool: getPool(usdc, weth),
            tokenOut: weth,
            isBuffer: false
        });
        _addPathAmountOut(minAmountOut);

        //TODO: about getPool(usdc, weth)
        _addDiffForAlice(IERC20(getPool(usdc, weth)), -int256(DEFAULT_EXACT_AMOUNT_IN));
        _addDiffForAlice(IERC20(getPool(weth, dai)), int256(minAmountOut));

        _addDiffForAlice(IERC20(getPool(dai, usdc)), -int256(DEFAULT_EXACT_AMOUNT_IN));
        _addDiffForAlice(weth, int256(minAmountOut));

        _addDiffForVault(IERC20(getPool(weth, dai)), -int256(minAmountOut));
        _addDiffForVault(IERC20(getPool(dai, usdc)), int256(DEFAULT_EXACT_AMOUNT_IN));
        _addDiffForVault(weth, -int256(minAmountOut));

        _addAmountOut(IERC20(getPool(weth, dai)), minAmountOut);
        _addAmountOut(weth, minAmountOut);

        testSwapExactIn(pathsExactIn, wethIsEth, 0, REMOVE_LIQUIDITY_DELTA);
    }

    function _generateSimpleDiffs(IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn) private {
        for (uint256 i = 0; i < pathsExactIn.length; i++) {
            IBatchRouter.SwapPathExactAmountIn memory pathExactIn = pathsExactIn[i];

            IBatchRouter.SwapPathStep memory lastStep = pathExactIn.steps[pathExactIn.steps.length - 1];

            _addDiffForVault(pathExactIn.tokenIn, int256(pathExactIn.exactAmountIn));
            _addDiffForVault(lastStep.tokenOut, -int256(pathExactIn.minAmountOut));

            _addDiffForAlice(pathExactIn.tokenIn, -int256(pathExactIn.exactAmountIn));
            _addDiffForAlice(lastStep.tokenOut, int256(pathExactIn.minAmountOut));

            _addAmountOut(lastStep.tokenOut, pathExactIn.minAmountOut);
            _addPathAmountOut(pathExactIn.minAmountOut);
        }
    }

    function _addPathAmountOut(uint256 amount) private {
        _pathAmountsOut.push(amount);
    }

    function _addAmountOut(IERC20 token, uint256 amount) private {
        (, uint256 currentAmountOut) = _amountsOut.tryGet(address(token));
        _amountsOut.set(address(token), currentAmountOut + amount);
    }

    function _addDiffForVault(IERC20 token, int256 diff) private {
        _vaultTokenBalancesDiff[address(token)] += diff;
    }

    function _addDiffForAlice(IERC20 token, int256 diff) private {
        _aliceTokenBalancesDiff[address(token)] += diff;
    }

    function testSwapExactIn(
        IBatchRouter.SwapPathExactAmountIn[] memory pathsExactIn,
        bool wethIsEth,
        uint256 ethAmount,
        uint256 delta
    ) internal {
        (
            uint256[] memory queryCalculatedPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = _queryExactIn(pathsExactIn);

        bool _wethIsEth = wethIsEth;
        IBatchRouter.SwapPathExactAmountIn[] memory _pathsExactIn = pathsExactIn;
        Balances memory balancesBefore = getBalances(alice, _tokens);

        vm.prank(alice);
        (
            uint256[] memory calculatedPathAmountsOut,
            address[] memory tokensOut,
            uint256[] memory amountsOut
        ) = batchRouter.swapExactIn{ value: ethAmount }(_pathsExactIn, MAX_UINT256, _wethIsEth, bytes(""));

        Balances memory balancesAfter = getBalances(alice, _tokens);

        uint256 _delta = delta;
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);

            if (_wethIsEth && address(token) == address(weth)) {
                assertApproxEqAbs(
                    balancesAfter.aliceEth,
                    uint256(int256(balancesBefore.aliceEth) + _aliceTokenBalancesDiff[address(token)]),
                    _delta,
                    "alice ETH balance mismatch"
                );
                assertApproxEqAbs(
                    balancesAfter.aliceTokens[i],
                    balancesBefore.aliceTokens[i],
                    _delta,
                    "The WETH balance of Alice should not be changed"
                );
            } else {
                assertApproxEqAbs(
                    balancesAfter.aliceTokens[i],
                    uint256(int256(balancesBefore.aliceTokens[i]) + _aliceTokenBalancesDiff[address(token)]),
                    _delta,
                    "alice token balance mismatch"
                );
            }

            assertApproxEqAbs(
                balancesAfter.vaultTokens[i],
                uint256(int256(balancesBefore.vaultTokens[i]) + _vaultTokenBalancesDiff[address(token)]),
                _delta,
                "vault token balance mismatch"
            );
            assertEq(balancesAfter.vaultEth, balancesBefore.vaultEth, "The ETH balance of Vault should not be changed");
        }

        assertEq(calculatedPathAmountsOut.length, _pathAmountsOut.length, "expected path amounts out length mismatch");
        assertEq(tokensOut.length, _amountsOut.length(), "expected tokens out length mismatch");
        assertEq(queryAmountsOut.length, _amountsOut.length(), "expected amounts out length mismatch");

        assertEq(
            queryCalculatedPathAmountsOut.length,
            calculatedPathAmountsOut.length,
            "query path amounts out length mismatch"
        );
        assertEq(queryTokensOut.length, tokensOut.length, "query tokens out length mismatch");
        assertEq(queryAmountsOut.length, amountsOut.length, "query amounts out length mismatch");

        for (uint256 i = 0; i < calculatedPathAmountsOut.length; i++) {
            assertApproxEqAbs(
                calculatedPathAmountsOut[i],
                _pathAmountsOut[i],
                _delta,
                "expected path amounts out different than actual"
            );

            assertEq(
                calculatedPathAmountsOut[i],
                queryCalculatedPathAmountsOut[i],
                "query expected path amounts out different than actual"
            );
        }

        for (uint256 i = 0; i < tokensOut.length; i++) {
            assertApproxEqAbs(
                amountsOut[i],
                _amountsOut.get(tokensOut[i]),
                _delta,
                "expected amounts out different than actual"
            );

            assertEq(tokensOut[i], queryTokensOut[i], "query expected tokens out different than actual");
            assertEq(amountsOut[i], queryAmountsOut[i], "query expected amounts out different than actual");
        }
    }
}
