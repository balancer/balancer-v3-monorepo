// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BufferHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/BufferHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

abstract contract YieldBearingPoolSwapBase is BaseVaultTest {
    using SafeERC20 for IERC20;
    using BufferHelpers for bytes32;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    string internal network;
    uint256 internal blockNumber;

    IERC4626 internal ybToken1;
    IERC4626 internal ybToken2;
    address internal donorToken1;
    address internal donorToken2;

    IERC20 private _token1Fork;
    IERC20 private _token2Fork;

    address private yieldBearingPool;

    // For two-token pools with waDAI/waUSDC, keep track of sorted token order.
    uint256 internal _ybToken1Idx;
    uint256 private _ybToken2Idx;

    uint256 private constant ROUNDING_TOLERANCE = 5;
    uint256 private constant BUFFER_INIT_AMOUNT = 100;
    uint256 private constant YIELD_BEARING_POOL_INIT_AMOUNT = BUFFER_INIT_AMOUNT * 5;

    uint256 private _token1Factor;
    uint256 private _token2Factor;
    uint256 private _ybToken1Factor;
    uint256 private _ybToken2Factor;
    uint256 private _token1BufferInitAmount;
    uint256 private _token2BufferInitAmount;

    uint256 private _token1YieldBearingPoolInitAmount;
    uint256 private _token2YieldBearingPoolInitAmount;

    function setUp() public virtual override {
        setUpForkTestVariables();

        vm.createSelectFork({ blockNumber: blockNumber, urlOrAlias: network });

        _token1Fork = IERC20(ybToken1.asset());
        _token2Fork = IERC20(ybToken2.asset());

        // The token factor used by the vault in poolData to upscale and downscale token amounts to scaled18 is
        // calculated as `10^(18 + decimalDifference)`, where `decimalDifference = 18 - tokenDecimals`. Therefore,
        // `tokenFactor = 10^(18 + (18 - tokenDecimals)) = 10^(36 - tokenDecimals)`.
        // For example, a token with 8 decimals will have a `tokenFactor` of 10^(36-8), or 10^(28).
        _ybToken1Factor = 10 ** (36 - IERC20Metadata(address(ybToken1)).decimals());
        _ybToken2Factor = 10 ** (36 - IERC20Metadata(address(ybToken2)).decimals());

        (_ybToken2Idx, _ybToken1Idx) = getSortedIndexes(address(ybToken2), address(ybToken1));

        _token1Factor = 10 ** IERC20Metadata(address(_token1Fork)).decimals();
        _token2Factor = 10 ** IERC20Metadata(address(_token2Fork)).decimals();
        _token1BufferInitAmount = BUFFER_INIT_AMOUNT * _token1Factor;
        _token2BufferInitAmount = BUFFER_INIT_AMOUNT * _token2Factor;

        _token1YieldBearingPoolInitAmount = YIELD_BEARING_POOL_INIT_AMOUNT * _token1Factor;
        _token2YieldBearingPoolInitAmount = YIELD_BEARING_POOL_INIT_AMOUNT * _token2Factor;

        BaseVaultTest.setUp();

        _setupTokens();
        _setupLPAndVault();
        _setupBuffers();
        _createAndInitializeYieldBearingPool();
    }

    function setUpForkTestVariables() internal virtual;

    function testSwapPreconditions__Fork() public view {
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(yieldBearingPool));
        // The yield-bearing pool should have `initAmount` of both tokens.
        assertEq(address(tokens[_ybToken1Idx]), address(ybToken1), "Wrong yield-bearing pool token (ybToken1)");
        assertEq(address(tokens[_ybToken2Idx]), address(ybToken2), "Wrong yield-bearing pool token (ybToken2)");

        uint256 yieldBearingPoolAmountToken1 = ybToken1.previewDeposit(_token1YieldBearingPoolInitAmount);
        uint256 yieldBearingPoolAmountToken2 = ybToken2.previewDeposit(_token2YieldBearingPoolInitAmount);

        assertEq(
            balancesRaw[_ybToken1Idx],
            yieldBearingPoolAmountToken1,
            "Wrong yield-bearing pool balance [ybToken1]"
        );
        assertEq(
            balancesRaw[_ybToken2Idx],
            yieldBearingPoolAmountToken2,
            "Wrong yield-bearing pool balance [ybToken2]"
        );

        // LP should have correct amount of shares from buffer (invested amount in underlying minus burned "BPTs")
        assertApproxEqAbs(
            vault.getBufferOwnerShares(ybToken1, lp),
            _token1BufferInitAmount * 2 - BUFFER_MINIMUM_TOTAL_SUPPLY,
            1,
            "Wrong share of ybToken1 buffer belonging to LP"
        );
        assertApproxEqAbs(
            vault.getBufferOwnerShares(ybToken2, lp),
            (_token2BufferInitAmount * 2) - BUFFER_MINIMUM_TOTAL_SUPPLY,
            1,
            "Wrong share of ybToken2 buffer belonging to LP"
        );

        // Buffer should have the correct amount of issued shares
        assertApproxEqAbs(
            vault.getBufferTotalShares(ybToken1),
            _token1BufferInitAmount * 2,
            1,
            "Wrong issued shares of ybToken1 buffer"
        );
        assertApproxEqAbs(
            vault.getBufferTotalShares(ybToken2),
            (_token2BufferInitAmount * 2),
            1,
            "Wrong issued shares of ybToken2 buffer"
        );

        uint256 underlyingBalance;
        uint256 wrappedBalance;

        // The vault buffers should each have `bufferAmount` of their respective tokens.
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(ybToken1);
        assertEq(underlyingBalance, _token1BufferInitAmount, "Wrong ybToken1 buffer balance for underlying token");
        assertEq(
            wrappedBalance,
            ybToken1.previewDeposit(_token1BufferInitAmount),
            "Wrong ybToken1 buffer balance for wrapped token"
        );

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(ybToken2);
        assertEq(underlyingBalance, _token2BufferInitAmount, "Wrong ybToken2 buffer balance for underlying token");
        assertEq(
            wrappedBalance,
            ybToken2.previewDeposit(_token2BufferInitAmount),
            "Wrong ybToken2 buffer balance for wrapped token"
        );
    }

    function testToken1InToken2OutWithinBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        // Test from 10% to 50% of tokenIn's buffer to avoid exceeding the limit of tokenOut's buffer.
        amountIn = bound(amountIn, (_token1BufferInitAmount) / 10, _token1BufferInitAmount / 2);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths, true);
    }

    function testToken1InToken2OutWithinBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        // Test from 10% to 50% of tokenOut's buffer to avoid exceeding the limit of tokenIn's buffer.
        amountOut = bound(amountOut, (_token2BufferInitAmount) / 10, _token2BufferInitAmount / 2);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths, true);
    }

    function testToken1InToken2OutOutOfBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        // Test from 2x to 4x of tokenIn's buffer to make sure it's out of both buffer ranges but yield-bearing pool
        // has enough tokens to trade (5x buffer init amount).
        amountIn = bound(amountIn, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths, false);
    }

    function testToken1InToken2OutOutOfBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        // Test from 2x to 4x of tokenOut's buffer to make sure it's out of both buffer ranges but yield-bearing pool
        // has enough tokens to trade (5x buffer init amount).
        amountOut = bound(amountOut, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths, false);
    }

    function testToken1InToken2OutBufferUnbalancedExactIn__Fork__Fuzz(
        uint256 amountIn,
        uint256 unbalancedToken1,
        uint256 unbalancedToken2
    ) public {
        unbalancedToken1 = bound(unbalancedToken1, 0, _token1BufferInitAmount);
        unbalancedToken2 = bound(unbalancedToken2, 0, _token2BufferInitAmount);
        _unbalanceBuffers(unbalancedToken1, unbalancedToken2);

        amountIn = bound(amountIn, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token1Fork, amountIn, 0);

        _testExactIn(paths, false);
    }

    function testToken1InToken2OutBufferUnbalancedExactOut__Fork__Fuzz(
        uint256 amountOut,
        uint256 unbalancedToken1,
        uint256 unbalancedToken2
    ) public {
        unbalancedToken1 = bound(unbalancedToken1, 0, _token1BufferInitAmount);
        unbalancedToken2 = bound(unbalancedToken2, 0, _token2BufferInitAmount);
        _unbalanceBuffers(unbalancedToken1, unbalancedToken2);

        amountOut = bound(amountOut, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token1Fork,
            (2 * amountOut * _token1Factor) / _token2Factor,
            amountOut
        );

        _testExactOut(paths, false);
    }

    function testToken2InToken1OutWithinBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        // Test from 10% to 50% of tokenOut's buffer to avoid exceeding the limit of tokenIn's buffer.
        amountIn = bound(amountIn, _token2BufferInitAmount / 10, _token2BufferInitAmount / 2);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths, true);
    }

    function testToken2InToken1OutWithinBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        // Test from 10% to 50% of tokenOut's buffer to avoid exceeding the limit of tokenIn's buffer.
        amountOut = bound(amountOut, _token1BufferInitAmount / 10, _token1BufferInitAmount / 2);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths, true);
    }

    function testToken2InToken1OutOutOfBufferExactIn__Fork__Fuzz(uint256 amountIn) public {
        amountIn = bound(amountIn, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths, false);
    }

    function testToken2InToken1OutOutOfBufferExactOut__Fork__Fuzz(uint256 amountOut) public {
        amountOut = bound(amountOut, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths, false);
    }

    function testToken2InToken1OutBufferUnbalancedExactIn__Fork__Fuzz(
        uint256 amountIn,
        uint256 unbalancedToken1,
        uint256 unbalancedToken2
    ) public {
        unbalancedToken1 = bound(unbalancedToken1, 0, _token1BufferInitAmount);
        unbalancedToken2 = bound(unbalancedToken2, 0, _token2BufferInitAmount);
        _unbalanceBuffers(unbalancedToken1, unbalancedToken2);

        amountIn = bound(amountIn, 2 * _token2BufferInitAmount, 4 * _token2BufferInitAmount);
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(_token2Fork, amountIn, 0);

        _testExactIn(paths, false);
    }

    function testToken2InToken1OutBufferUnbalancedExactOut__Fork__Fuzz(
        uint256 amountOut,
        uint256 unbalancedToken1,
        uint256 unbalancedToken2
    ) public {
        unbalancedToken1 = bound(unbalancedToken1, 0, _token1BufferInitAmount);
        unbalancedToken2 = bound(unbalancedToken2, 0, _token2BufferInitAmount);
        _unbalanceBuffers(unbalancedToken1, unbalancedToken2);

        amountOut = bound(amountOut, 2 * _token1BufferInitAmount, 4 * _token1BufferInitAmount);
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(
            _token2Fork,
            (2 * amountOut * _token2Factor) / _token1Factor,
            amountOut
        );

        _testExactOut(paths, false);
    }

    function _testExactIn(IBatchRouter.SwapPathExactAmountIn[] memory paths, bool withBufferLiquidity) private {
        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (
            uint256[] memory queryPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = batchRouter.querySwapExactIn(paths, bytes(""));
        vm.revertTo(snapshotId);

        // Measure tokens before actual swap
        SwapResultLocals memory vars = _createSwapResultLocals(
            SwapKind.EXACT_IN,
            IERC4626(address(paths[0].steps[0].tokenOut)),
            IERC4626(address(paths[0].steps[1].tokenOut)),
            withBufferLiquidity
        );

        vars.expectedUnderlyingDeltaTokenIn = paths[0].exactAmountIn;

        if (paths[0].tokenIn == _token1Fork) {
            (
                vars.expectedWrappedDeltaTokenIn,
                vars.expectedUnderlyingSurplusTokenIn,
                vars.expectedWrappedSurplusTokenIn
            ) = _previewWrapExactIn(ybToken1, vars.expectedUnderlyingDeltaTokenIn, withBufferLiquidity);
            uint256 wrappedAmountInScaled18 = vars.expectedWrappedDeltaTokenIn.mulDown(_ybToken1Factor);
            // PoolMock is linear, so wrappedAmountInScaled18 = wrappedAmountOutScaled18
            vars.expectedWrappedDeltaTokenOut = wrappedAmountInScaled18.divDown(_ybToken2Factor);

            (
                vars.expectedUnderlyingDeltaTokenOut,
                vars.expectedUnderlyingSurplusTokenOut,
                vars.expectedWrappedSurplusTokenOut
            ) = _previewUnwrapExactIn(ybToken2, vars.expectedWrappedDeltaTokenOut, withBufferLiquidity);
        } else {
            (
                vars.expectedWrappedDeltaTokenIn,
                vars.expectedUnderlyingSurplusTokenIn,
                vars.expectedWrappedSurplusTokenIn
            ) = _previewWrapExactIn(ybToken2, vars.expectedUnderlyingDeltaTokenIn, withBufferLiquidity);
            uint256 wrappedAmountInScaled18 = vars.expectedWrappedDeltaTokenIn.mulDown(_ybToken2Factor);
            // PoolMock is linear, so wrappedAmountInScaled18 = wrappedAmountOutScaled18
            vars.expectedWrappedDeltaTokenOut = wrappedAmountInScaled18.divDown(_ybToken1Factor);

            (
                vars.expectedUnderlyingDeltaTokenOut,
                vars.expectedUnderlyingSurplusTokenOut,
                vars.expectedWrappedSurplusTokenOut
            ) = _previewUnwrapExactIn(ybToken1, vars.expectedWrappedDeltaTokenOut, withBufferLiquidity);
        }

        vm.prank(lp);
        (
            uint256[] memory actualPathAmountsOut,
            address[] memory actualTokensOut,
            uint256[] memory actualAmountsOut
        ) = batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        assertEq(actualPathAmountsOut.length, 1, "actualPathAmountsOut length is wrong");
        assertEq(actualTokensOut.length, 1, "actualTokensOut length is wrong");
        assertEq(actualAmountsOut.length, 1, "actualAmountsOut length is wrong");
        assertEq(
            actualPathAmountsOut.length,
            queryPathAmountsOut.length,
            "actual and query pathAmountsOut lengths do not match"
        );
        assertEq(actualTokensOut.length, queryTokensOut.length, "actual and query tokensOut lengths do not match");
        assertEq(actualAmountsOut.length, queryAmountsOut.length, "actual and query amountsOut lengths do not match");

        assertEq(queryTokensOut[0], actualTokensOut[0], "Query and actual tokensOut do not match");

        // The error between the query and the actual operation is proportional to the amount of decimals of token in
        // and token out. If tokenIn has 6 decimals and tokenOut has 18 decimals, an error of 1 wei in amountOut of
        // the first buffer generates an error in the order of 1e12 (1e18/1e6) in amountOut of the last buffer.
        // But, if it's the opposite case, 1e6/1e18 is rounded to 0, but the max error is actually 1 (the error in the
        // tokenOut token itself), so the division is incremented by 1.
        uint256 decimalError = (
            paths[0].tokenIn == _token1Fork ? _token2Factor / _token1Factor : _token1Factor / _token2Factor
        ) + 1;

        // Query and actual operation can return different results, depending on the difference of decimals. The error
        // is amplified by the rate of the token out.
        uint256 absTolerance = vars.ybTokenOut.previewMint(decimalError);
        // If previewRedeem return 0, absTolerance may be smaller than the error introduced by the difference of
        // decimals, so keep the decimalError.
        absTolerance = absTolerance > decimalError ? absTolerance : decimalError;

        assertApproxEqAbs(
            queryPathAmountsOut[0],
            actualPathAmountsOut[0],
            absTolerance,
            "Query and actual pathAmountsOut difference is bigger than absolute tolerance"
        );

        assertApproxEqAbs(
            queryAmountsOut[0],
            actualAmountsOut[0],
            absTolerance,
            "Query and actual amountsOut difference is bigger than absolute tolerance"
        );

        // 0.01% relative error tolerance.
        uint256 relTolerance = 0.01e16;

        assertApproxEqRel(
            queryPathAmountsOut[0],
            actualPathAmountsOut[0],
            relTolerance,
            "Query and actual pathAmountsOut difference is bigger than relative tolerance"
        );
        assertApproxEqRel(
            queryAmountsOut[0],
            actualAmountsOut[0],
            relTolerance,
            "Query and actual amountsOut difference is bigger than relative tolerance"
        );

        _verifySwapResult(actualPathAmountsOut, actualTokensOut, actualAmountsOut, vars);
    }

    function _testExactOut(IBatchRouter.SwapPathExactAmountOut[] memory paths, bool withBufferLiquidity) private {
        uint256 snapshotId = vm.snapshot();
        _prankStaticCall();
        (
            uint256[] memory queryPathAmountsIn,
            address[] memory queryTokensIn,
            uint256[] memory queryAmountsIn
        ) = batchRouter.querySwapExactOut(paths, bytes(""));
        vm.revertTo(snapshotId);

        // Measure tokens before actual swap
        SwapResultLocals memory vars = _createSwapResultLocals(
            SwapKind.EXACT_OUT,
            IERC4626(address(paths[0].steps[0].tokenOut)),
            IERC4626(address(paths[0].steps[1].tokenOut)),
            withBufferLiquidity
        );

        vars.expectedUnderlyingDeltaTokenOut = paths[0].exactAmountOut;

        if (paths[0].tokenIn == _token1Fork) {
            (
                vars.expectedWrappedDeltaTokenOut,
                vars.expectedUnderlyingSurplusTokenOut,
                vars.expectedWrappedSurplusTokenOut
            ) = _previewUnwrapExactOut(ybToken2, vars.expectedUnderlyingDeltaTokenOut, withBufferLiquidity);

            uint256 wrappedAmountOutScaled18 = vars.expectedWrappedDeltaTokenOut.mulUp(_ybToken2Factor);
            // PoolMock is linear, so wrappedAmountInScaled18 = wrappedAmountOutScaled18
            vars.expectedWrappedDeltaTokenIn = wrappedAmountOutScaled18.divUp(_ybToken1Factor);
            (
                vars.expectedUnderlyingDeltaTokenIn,
                vars.expectedUnderlyingSurplusTokenIn,
                vars.expectedWrappedSurplusTokenIn
            ) = _previewWrapExactOut(ybToken1, vars.expectedWrappedDeltaTokenIn, withBufferLiquidity);
        } else {
            (
                vars.expectedWrappedDeltaTokenOut,
                vars.expectedUnderlyingSurplusTokenOut,
                vars.expectedWrappedSurplusTokenOut
            ) = _previewUnwrapExactOut(ybToken1, vars.expectedUnderlyingDeltaTokenOut, withBufferLiquidity);

            uint256 wrappedAmountOutScaled18 = vars.expectedWrappedDeltaTokenOut.mulUp(_ybToken1Factor);
            // PoolMock is linear, so wrappedAmountInScaled18 = wrappedAmountOutScaled18
            vars.expectedWrappedDeltaTokenIn = wrappedAmountOutScaled18.divUp(_ybToken2Factor);
            (
                vars.expectedUnderlyingDeltaTokenIn,
                vars.expectedUnderlyingSurplusTokenIn,
                vars.expectedWrappedSurplusTokenIn
            ) = _previewWrapExactOut(ybToken2, vars.expectedWrappedDeltaTokenIn, withBufferLiquidity);
        }

        vm.prank(lp);
        (
            uint256[] memory actualPathAmountsIn,
            address[] memory actualTokensIn,
            uint256[] memory actualAmountsIn
        ) = batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        assertEq(actualPathAmountsIn.length, 1, "actualPathAmountsIn length is wrong");
        assertEq(actualTokensIn.length, 1, "actualTokensIn length is wrong");
        assertEq(actualAmountsIn.length, 1, "actualAmountsIn length is wrong");

        assertEq(actualTokensIn.length, queryTokensIn.length, "actual and query tokensIn lengths do not match");
        assertEq(actualAmountsIn.length, queryAmountsIn.length, "actual and query amountsIn lengths do not match");
        assertEq(
            actualPathAmountsIn.length,
            queryPathAmountsIn.length,
            "actual and query pathAmountsIn lengths do not match"
        );

        assertEq(queryTokensIn[0], actualTokensIn[0], "Query and actual tokensIn do not match");

        // The error between the query and the actual operation is proportional to the amount of decimals of token in
        // and token out. If tokenIn has 6 decimals and tokenOut has 18 decimals, an error of 1 wei in amountOut of
        // the first buffer generates an error in the order of 1e12 (1e18/1e6) in amountOut of the last buffer.
        // But, if it's the opposite case, 1e6/1e18 is rounded to 0, but the max error is actually 1 (the error in the
        // tokenOut token itself), so the division is incremented by 1.
        uint256 decimalError = (
            paths[0].tokenIn == _token1Fork ? _token1Factor / _token2Factor : _token2Factor / _token1Factor
        ) + 1;

        // Query and actual operation can return different results, depending on the difference of decimals. The error
        // is amplified by the rate of the token in.
        uint256 absTolerance = vars.ybTokenIn.previewMint(decimalError);
        // If previewMint return 0, absTolerance may be smaller than the error introduced by the difference of
        // decimals, so keep the decimalError.
        absTolerance = absTolerance > decimalError ? absTolerance : decimalError;

        assertApproxEqAbs(
            queryPathAmountsIn[0],
            actualPathAmountsIn[0],
            absTolerance,
            "Query and actual pathAmountsIn difference is bigger than absolute tolerance"
        );

        assertApproxEqAbs(
            queryAmountsIn[0],
            actualAmountsIn[0],
            absTolerance,
            "Query and actual amountsIn difference is bigger than absolute tolerance"
        );

        // 0.01% relative error tolerance.
        uint256 relTolerance = 0.01e16;

        assertApproxEqRel(
            queryPathAmountsIn[0],
            actualPathAmountsIn[0],
            relTolerance,
            "Query and actual pathAmountsIn difference is bigger than relative tolerance"
        );
        assertApproxEqRel(
            queryAmountsIn[0],
            actualAmountsIn[0],
            relTolerance,
            "Query and actual amountsIn difference is bigger than relative tolerance"
        );

        _verifySwapResult(actualPathAmountsIn, actualTokensIn, actualAmountsIn, vars);
    }

    function _verifySwapResult(
        uint256[] memory paths,
        address[] memory tokens,
        uint256[] memory amounts,
        SwapResultLocals memory vars
    ) private view {
        assertEq(paths.length, 1, "Incorrect output array length");

        assertEq(paths.length, tokens.length, "Output array length mismatch");
        assertEq(tokens.length, amounts.length, "Output array length mismatch");

        // Check results
        if (vars.kind == SwapKind.EXACT_IN) {
            // Rounding issues occurs in favor of the Vault.
            assertLe(paths[0], vars.expectedUnderlyingDeltaTokenOut, "paths AmountOut must be <= expected amountOut");
            assertLe(
                amounts[0],
                vars.expectedUnderlyingDeltaTokenOut,
                "amounts AmountOut must be <= expected amountOut"
            );

            // Rounding issues are very small.
            assertApproxEqAbs(paths[0], vars.expectedUnderlyingDeltaTokenOut, ROUNDING_TOLERANCE, "Wrong path count");
            assertApproxEqAbs(
                amounts[0],
                vars.expectedUnderlyingDeltaTokenOut,
                ROUNDING_TOLERANCE,
                "Wrong amounts count"
            );
            assertEq(tokens[0], address(vars.tokenOut), "Wrong token for SwapKind");
        } else {
            // Rounding issues occurs in favor of the Vault.
            assertGe(paths[0], vars.expectedUnderlyingDeltaTokenIn, "paths AmountIn must be >= expected amountIn");
            assertGe(amounts[0], vars.expectedUnderlyingDeltaTokenIn, "amounts AmountIn must be >= expected amountIn");

            // Rounding issues are very small.
            assertApproxEqAbs(paths[0], vars.expectedUnderlyingDeltaTokenIn, ROUNDING_TOLERANCE, "Wrong path count");
            assertApproxEqAbs(
                amounts[0],
                vars.expectedUnderlyingDeltaTokenIn,
                ROUNDING_TOLERANCE,
                "Wrong amounts count"
            );
            assertEq(tokens[0], address(vars.tokenIn), "Wrong token for SwapKind");
        }

        // If there were rounding issues, make sure it's in favor of the vault (lp balance of tokenIn is <= expected,
        // meaning vault's tokenIn is >= expected).
        assertLe(
            vars.tokenIn.balanceOf(lp),
            vars.lpBeforeSwapTokenIn - vars.expectedUnderlyingDeltaTokenIn,
            "LP balance tokenIn must be <= expected balance"
        );
        // If there were rounding issues, make sure it's not a big one (less than 5 wei).
        assertApproxEqAbs(
            vars.tokenIn.balanceOf(lp),
            vars.lpBeforeSwapTokenIn - vars.expectedUnderlyingDeltaTokenIn,
            ROUNDING_TOLERANCE,
            "Wrong ending balance of tokenIn for LP"
        );

        // If there were rounding issues, make sure it's in favor of the vault (lp balance of tokenOut is <= expected,
        // meaning vault's tokenOut is >= expected).
        assertLe(
            vars.tokenOut.balanceOf(lp),
            vars.lpBeforeSwapTokenOut + vars.expectedUnderlyingDeltaTokenOut,
            "LP balance tokenOut must be <= expected balance"
        );
        // If there were rounding issues, make sure it's not a big one (less than 5 wei).
        assertApproxEqAbs(
            vars.tokenOut.balanceOf(lp),
            vars.lpBeforeSwapTokenOut + vars.expectedUnderlyingDeltaTokenOut,
            ROUNDING_TOLERANCE,
            "Wrong ending balance of tokenOut for LP"
        );

        uint256[] memory balancesRaw;

        (, , balancesRaw, ) = vault.getPoolTokenInfo(address(yieldBearingPool));
        assertEq(
            balancesRaw[vars.indexYbTokenIn],
            vars.poolBeforeSwapYbTokenIn + vars.expectedWrappedDeltaTokenIn,
            "Wrong yield-bearing pool tokenIn balance"
        );
        assertEq(
            balancesRaw[vars.indexYbTokenOut],
            vars.poolBeforeSwapYbTokenOut - vars.expectedWrappedDeltaTokenOut,
            "Wrong yield-bearing pool tokenOut balance"
        );

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(vars.ybTokenIn);

        assertEq(
            underlyingBalance,
            uint256(
                int256(vars.bufferBeforeSwapTokenIn) -
                    vars.expectedUnderlyingSurplusTokenIn +
                    int256(vars.withBufferLiquidity ? vars.expectedUnderlyingDeltaTokenIn : 0)
            ),
            "Wrong underlying balance for tokenIn buffer"
        );

        assertEq(
            wrappedBalance,
            uint256(
                int256(vars.bufferBeforeSwapYbTokenIn) +
                    vars.expectedWrappedSurplusTokenIn -
                    int256(vars.withBufferLiquidity ? vars.expectedWrappedDeltaTokenIn : 0)
            ),
            "Wrong wrapped balance for tokenIn buffer"
        );

        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(vars.ybTokenOut);

        assertEq(
            underlyingBalance,
            uint256(
                int256(vars.bufferBeforeSwapTokenOut) +
                    vars.expectedUnderlyingSurplusTokenOut -
                    int256(vars.withBufferLiquidity ? vars.expectedUnderlyingDeltaTokenOut : 0)
            ),
            "Wrong underlying balance for tokenOut buffer"
        );
        assertEq(
            wrappedBalance,
            uint256(
                int256(vars.bufferBeforeSwapYbTokenOut) -
                    vars.expectedWrappedSurplusTokenOut +
                    int256(vars.withBufferLiquidity ? vars.expectedWrappedDeltaTokenOut : 0)
            ),
            "Wrong wrapped balance for tokenOut buffer"
        );
    }

    function _createSwapResultLocals(
        SwapKind kind,
        IERC4626 ybTokenIn,
        IERC4626 ybTokenOut,
        bool withBufferLiquidity
    ) private view returns (SwapResultLocals memory vars) {
        vars.kind = kind;

        vars.ybTokenIn = ybTokenIn;
        vars.ybTokenOut = ybTokenOut;

        vars.tokenIn = IERC4626(ybTokenIn.asset());
        vars.tokenOut = IERC4626(ybTokenOut.asset());

        vars.lpBeforeSwapTokenIn = vars.tokenIn.balanceOf(lp);
        vars.lpBeforeSwapTokenOut = vars.tokenOut.balanceOf(lp);

        uint256 underlyingBalance;
        uint256 wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(ybTokenIn);
        vars.bufferBeforeSwapTokenIn = underlyingBalance;
        vars.bufferBeforeSwapYbTokenIn = wrappedBalance;
        (underlyingBalance, wrappedBalance) = vault.getBufferBalance(ybTokenOut);
        vars.bufferBeforeSwapTokenOut = underlyingBalance;
        vars.bufferBeforeSwapYbTokenOut = wrappedBalance;

        uint256[] memory balancesRaw;
        (, , balancesRaw, ) = vault.getPoolTokenInfo(address(yieldBearingPool));
        if (vars.tokenIn == _token1Fork) {
            vars.indexYbTokenIn = _ybToken1Idx;
            vars.indexYbTokenOut = _ybToken2Idx;
        } else {
            vars.indexYbTokenIn = _ybToken2Idx;
            vars.indexYbTokenOut = _ybToken1Idx;
        }
        vars.poolBeforeSwapYbTokenIn = balancesRaw[vars.indexYbTokenIn];
        vars.poolBeforeSwapYbTokenOut = balancesRaw[vars.indexYbTokenOut];

        vars.withBufferLiquidity = withBufferLiquidity;
    }

    function _buildExactInPaths(
        IERC20 tokenIn,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: _getSwapSteps(tokenIn),
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }

    function _buildExactOutPaths(
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: _getSwapSteps(tokenIn),
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }

    function _getSwapSteps(IERC20 tokenIn) private view returns (IBatchRouter.SwapPathStep[] memory steps) {
        steps = new IBatchRouter.SwapPathStep[](3);

        if (tokenIn == _token2Fork) {
            steps[0] = IBatchRouter.SwapPathStep({
                pool: address(ybToken2),
                tokenOut: IERC20(address(ybToken2)),
                isBuffer: true
            });
            steps[1] = IBatchRouter.SwapPathStep({
                pool: address(yieldBearingPool),
                tokenOut: IERC20(address(ybToken1)),
                isBuffer: false
            });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(ybToken1), tokenOut: _token1Fork, isBuffer: true });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({
                pool: address(ybToken1),
                tokenOut: IERC20(address(ybToken1)),
                isBuffer: true
            });
            steps[1] = IBatchRouter.SwapPathStep({
                pool: address(yieldBearingPool),
                tokenOut: IERC20(address(ybToken2)),
                isBuffer: false
            });
            steps[2] = IBatchRouter.SwapPathStep({ pool: address(ybToken2), tokenOut: _token2Fork, isBuffer: true });
        }
    }

    /**
     * @notice Unbalance buffers of ybToken1 and ybToken2.
     * @dev This function can unbalance buffers to both sides, up to 50% of buffer initial liquidity.
     * If the amount to unbalance token is smaller than 50% of buffer initial liquidity, underlying are wrapped, else
     * wrapped are transformed to underlying.
     */
    function _unbalanceBuffers(uint256 unbalancedToken1, uint256 unbalancedToken2) private {
        if (unbalancedToken1 > _token1BufferInitAmount / 2) {
            _unbalanceBuffer(WrappingDirection.WRAP, ybToken1, unbalancedToken1 - _token1BufferInitAmount / 2);
        } else {
            _unbalanceBuffer(WrappingDirection.UNWRAP, ybToken1, _token1BufferInitAmount / 2 - unbalancedToken1);
        }

        if (unbalancedToken2 > _token2BufferInitAmount / 2) {
            _unbalanceBuffer(WrappingDirection.WRAP, ybToken2, unbalancedToken2 - _token2BufferInitAmount / 2);
        } else {
            _unbalanceBuffer(WrappingDirection.UNWRAP, ybToken2, _token2BufferInitAmount / 2 - unbalancedToken2);
        }
    }

    function _unbalanceBuffer(WrappingDirection direction, IERC4626 wToken, uint256 amountToUnbalance) private {
        if (amountToUnbalance < PRODUCTION_MIN_TRADE_AMOUNT) {
            // If amountToUnbalance is very low, returns without unbalancing the buffer.
            return;
        }

        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 exactAmountIn;

        if (direction == WrappingDirection.WRAP) {
            tokenIn = IERC20(wToken.asset());
            tokenOut = IERC20(address(wToken));
            exactAmountIn = amountToUnbalance;
        } else {
            tokenIn = IERC20(address(wToken));
            tokenOut = IERC20(wToken.asset());
            exactAmountIn = wToken.previewDeposit(amountToUnbalance);
        }

        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wToken), tokenOut: tokenOut, isBuffer: true });

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: 0
        });

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    function _setupTokens() private {
        // Label deployed wrapped tokens.
        vm.label(address(ybToken1), "ybToken1");
        vm.label(address(ybToken2), "ybToken2");

        // Identify and label underlying tokens.
        _token1Fork = IERC20(ybToken1.asset());
        vm.label(address(_token1Fork), "token1");
        _token2Fork = IERC20(ybToken2.asset());
        vm.label(address(_token2Fork), "token2");
    }

    function _setupLPAndVault() private {
        vm.startPrank(donorToken1);
        // Donate token1 (underlying) to LP.
        _token1Fork.safeTransfer(lp, 100 * _token1BufferInitAmount);
        vm.stopPrank();

        vm.startPrank(donorToken2);
        // Donate token2 (underlying) to LP.
        _token2Fork.safeTransfer(lp, 100 * _token2BufferInitAmount);
        vm.stopPrank();

        vm.startPrank(lp);
        // Allow Permit2 to get tokens from LP.
        _token1Fork.forceApprove(address(permit2), type(uint256).max);
        _token2Fork.forceApprove(address(permit2), type(uint256).max);
        ybToken2.approve(address(permit2), type(uint256).max);
        ybToken1.approve(address(permit2), type(uint256).max);
        // Allow Permit2 to move DAI and USDC from LP to Router.
        permit2.approve(address(_token2Fork), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(_token1Fork), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken2), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken1), address(router), type(uint160).max, type(uint48).max);
        // Allow Permit2 to move DAI and USDC from LP to BatchRouter.
        permit2.approve(address(_token2Fork), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(_token1Fork), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken2), address(batchRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(ybToken1), address(batchRouter), type(uint160).max, type(uint48).max);
        // Wrap part of LP balances.
        _token1Fork.forceApprove(address(ybToken1), 4 * _token1YieldBearingPoolInitAmount);
        ybToken1.deposit(4 * _token1YieldBearingPoolInitAmount, lp);
        _token2Fork.forceApprove(address(ybToken2), 4 * _token2YieldBearingPoolInitAmount);
        ybToken2.deposit(4 * _token2YieldBearingPoolInitAmount, lp);
        vm.stopPrank();
    }

    function _setupBuffers() private {
        vm.startPrank(lp);
        router.initializeBuffer(ybToken2, _token2BufferInitAmount, ybToken2.previewDeposit(_token2BufferInitAmount));
        router.initializeBuffer(ybToken1, _token1BufferInitAmount, ybToken1.previewDeposit(_token1BufferInitAmount));
        vm.stopPrank();
    }

    function _createAndInitializeYieldBearingPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[_ybToken2Idx].token = IERC20(address(ybToken2));
        tokenConfig[_ybToken1Idx].token = IERC20(address(ybToken1));
        // Not using RateProviders simplifies the calculation of the yield-bearing pool swap, since amountIn and
        // amountOut are the same using PoolMock's linear math.
        tokenConfig[0].tokenType = TokenType.STANDARD;
        tokenConfig[1].tokenType = TokenType.STANDARD;

        PoolMock newPool = new PoolMock(IVault(address(vault)), "Yield-Bearing Pool", "YBPOOL");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

        vm.label(address(newPool), "yield-bearing pool");
        yieldBearingPool = address(newPool);

        vm.startPrank(lp);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[_ybToken1Idx] = ybToken1.previewDeposit(_token1YieldBearingPoolInitAmount);
        tokenAmounts[_ybToken2Idx] = ybToken2.previewDeposit(_token2YieldBearingPoolInitAmount);
        _initPool(address(yieldBearingPool), tokenAmounts, 0);
        vm.stopPrank();
    }

    function _previewWrapExactIn(
        IERC4626 wToken,
        uint256 amountInUnderlying,
        bool withBufferLiquidity
    ) private returns (uint256 amountOutWrapped, int256 bufferUnderlyingSurplus, int256 bufferWrappedSurplus) {
        amountOutWrapped = wToken.previewDeposit(amountInUnderlying);
        bufferUnderlyingSurplus = 0;
        bufferWrappedSurplus = 0;

        // If operation is out of buffer liquidity, we need to wrap the underlying tokens in the wrapper protocol. But,
        // if the buffer has enough liquidity, return the amountOutWrapped calculated by previewDeposit and surplus 0.
        if (withBufferLiquidity == false) {
            bytes32 bufferBalances = vault.getBufferTokenBalancesBytes(wToken);
            // Deposit converts underlying to wrapped. The rebalance logic can introduce rounding issues, so we
            // should consider it in our result preview. The logic below reproduces Vault's rebalance logic.
            bufferUnderlyingSurplus = bufferBalances.getBufferUnderlyingSurplus(wToken);

            uint256 vaultUnderlyingDeltaHint = uint256(int256(amountInUnderlying) + bufferUnderlyingSurplus);
            uint256 vaultWrappedDeltaHint = wToken.previewDeposit(vaultUnderlyingDeltaHint);
            bufferWrappedSurplus = int256(vaultWrappedDeltaHint) - int256(amountOutWrapped);
        }
    }

    function _previewUnwrapExactIn(
        IERC4626 wToken,
        uint256 amountInWrapped,
        bool withBufferLiquidity
    ) private returns (uint256 amountOutUnderlying, int256 bufferUnderlyingSurplus, int256 bufferWrappedSurplus) {
        amountOutUnderlying = wToken.previewRedeem(amountInWrapped);
        bufferUnderlyingSurplus = 0;
        bufferWrappedSurplus = 0;

        // If operation is out of buffer liquidity, we need to unwrap the wrapped tokens in the wrapper protocol. But,
        // if the buffer has enough liquidity, return the amountOutUnderlying calculated by previewRedeem and surplus 0.
        if (withBufferLiquidity == false) {
            bytes32 bufferBalances = vault.getBufferTokenBalancesBytes(wToken);
            // Redeem converts wrapped to underlying. The rebalance logic can introduce rounding issues, so we
            // should consider it in our result preview. The logic below reproduces Vault's rebalance logic.
            bufferWrappedSurplus = bufferBalances.getBufferWrappedSurplus(wToken);

            uint256 vaultWrappedDeltaHint = uint256(int256(amountInWrapped) + bufferWrappedSurplus);
            uint256 vaultUnderlyingDeltaHint = wToken.previewRedeem(vaultWrappedDeltaHint);
            bufferUnderlyingSurplus = int256(vaultUnderlyingDeltaHint) - int256(amountOutUnderlying);
        }
    }

    function _previewWrapExactOut(
        IERC4626 wToken,
        uint256 amountOutWrapped,
        bool withBufferLiquidity
    ) private returns (uint256 amountInUnderlying, int256 bufferUnderlyingSurplus, int256 bufferWrappedSurplus) {
        amountInUnderlying = wToken.previewMint(amountOutWrapped);
        bufferUnderlyingSurplus = 0;
        bufferWrappedSurplus = 0;

        // If operation is out of buffer liquidity, we need to wrap the underlying tokens in the wrapper protocol. But,
        // if the buffer has enough liquidity, return the amountInUnderlying calculated by previewMint and surplus 0.
        if (withBufferLiquidity == false) {
            bytes32 bufferBalances = vault.getBufferTokenBalancesBytes(wToken);
            // Mint converts underlying to wrapped. The rebalance logic can introduce rounding issues, so we
            // should consider it in our result preview. The logic below reproduces Vault's rebalance logic.
            bufferUnderlyingSurplus = bufferBalances.getBufferUnderlyingSurplus(wToken);
            uint256 vaultUnderlyingDeltaHint = uint256(int256(amountInUnderlying) + bufferUnderlyingSurplus);
            uint256 vaultWrappedDeltaHint = wToken.previewDeposit(vaultUnderlyingDeltaHint);

            vaultUnderlyingDeltaHint = wToken.previewMint(vaultWrappedDeltaHint);

            if (bufferUnderlyingSurplus != 0) {
                bufferUnderlyingSurplus = int256(vaultUnderlyingDeltaHint) - int256(amountInUnderlying);
                bufferWrappedSurplus = int256(vaultWrappedDeltaHint) - int256(amountOutWrapped);
            }
        }
    }

    function _previewUnwrapExactOut(
        IERC4626 wToken,
        uint256 amountOutUnderlying,
        bool withBufferLiquidity
    ) private returns (uint256 amountInWrapped, int256 bufferUnderlyingSurplus, int256 bufferWrappedSurplus) {
        amountInWrapped = wToken.previewWithdraw(amountOutUnderlying);
        bufferUnderlyingSurplus = 0;
        bufferWrappedSurplus = 0;

        // If operation is out of buffer liquidity, we need to unwrap the wrapped tokens in the wrapper protocol. But,
        // if the buffer has enough liquidity, return the amountInWrapped calculated by previewWithdraw and surplus 0.
        if (withBufferLiquidity == false) {
            bytes32 bufferBalances = vault.getBufferTokenBalancesBytes(wToken);
            // Withdraw converts wrapped to underlying. The rebalance logic can introduce rounding issues, so we
            // should consider it in our result preview. The logic below reproduces Vault's rebalance logic.
            bufferWrappedSurplus = bufferBalances.getBufferWrappedSurplus(wToken);
            uint256 vaultWrappedDeltaHint = uint256(int256(amountInWrapped) + bufferWrappedSurplus);
            uint256 vaultUnderlyingDeltaHint = wToken.previewRedeem(vaultWrappedDeltaHint);

            vaultWrappedDeltaHint = wToken.previewWithdraw(vaultUnderlyingDeltaHint);

            if (bufferWrappedSurplus != 0) {
                bufferWrappedSurplus = int256(vaultWrappedDeltaHint) - int256(amountInWrapped);
                bufferUnderlyingSurplus = int256(vaultUnderlyingDeltaHint) - int256(amountOutUnderlying);
            }
        }
    }

    struct SwapResultLocals {
        SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        IERC4626 ybTokenIn;
        IERC4626 ybTokenOut;
        uint256 indexYbTokenIn;
        uint256 indexYbTokenOut;
        uint256 lpBeforeSwapTokenIn;
        uint256 lpBeforeSwapTokenOut;
        uint256 bufferBeforeSwapTokenIn;
        uint256 bufferBeforeSwapYbTokenIn;
        uint256 bufferBeforeSwapTokenOut;
        uint256 bufferBeforeSwapYbTokenOut;
        uint256 poolBeforeSwapYbTokenIn;
        uint256 poolBeforeSwapYbTokenOut;
        uint256 expectedUnderlyingDeltaTokenIn;
        uint256 expectedWrappedDeltaTokenIn;
        uint256 expectedUnderlyingDeltaTokenOut;
        uint256 expectedWrappedDeltaTokenOut;
        // Underlying may be positive or negative.
        int256 expectedUnderlyingSurplusTokenIn;
        int256 expectedWrappedSurplusTokenIn;
        int256 expectedUnderlyingSurplusTokenOut;
        int256 expectedWrappedSurplusTokenOut;
        bool withBufferLiquidity;
    }
}
