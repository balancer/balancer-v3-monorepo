// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";

contract QueryERC4626BufferTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    uint256 internal tooLargeSwapAmount = erc4626PoolInitialAmount / 2;
    // We will swap with 10% of the buffer.
    uint256 internal swapAmount;
    uint256 internal constant MAX_ERROR = 10;

    function setUp() public virtual override {
        bufferInitialAmount = erc4626PoolInitialAmount / 100;
        swapAmount = bufferInitialAmount / 10;
        BaseERC4626BufferTest.setUp();
        _initializeUser();
    }

    function testQuerySwapWithinBufferRangeExactIn() public {
        _testQuerySwapExactIn(swapAmount);
    }

    function testQuerySwapWithinBufferRangeExactOut() public {
        _testQuerySwapExactOut(swapAmount);
    }

    function testQuerySwapOutOfBufferRangeExactIn() public {
        _testQuerySwapExactIn(tooLargeSwapAmount);
    }

    function testQuerySwapOutOfBufferRangeExactOut() public {
        _testQuerySwapExactOut(tooLargeSwapAmount);
    }

    function _testQuerySwapExactIn(uint256 amountIn) private {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(amountIn);

        // Snapshots the current state of the network.
        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        // Not using staticCall because it does not allow changes in the transient storage, and reverts with
        // a StateChangeDuringStaticCall error.
        (
            uint256[] memory queryPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = batchRouter.querySwapExactIn(paths, address(this), bytes(""));

        // Restores the network state to snapshot.
        vm.revertTo(snapshotId);

        // Executes the actual operation.
        vm.prank(alice);
        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // Check if results of query and actual operations are equal
        assertApproxEqRel(pathAmountsOut[0], queryPathAmountsOut[0], errorTolerance, "pathAmountsOut's do not match");
        assertEq(tokensOut[0], queryTokensOut[0], "tokensOut's do not match");
        assertApproxEqRel(amountsOut[0], queryAmountsOut[0], errorTolerance, "amountsOut's do not match");
    }

    function _testQuerySwapExactOut(uint256 amount) private {
        IBatchRouter.SwapPathExactAmountOut[] memory paths = _buildExactOutPaths(amount);

        // Snapshots the current state of the network.
        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        // Not using staticCall because it does not allow changes in the transient storage, and reverts with
        // a StateChangeDuringStaticCall error.
        (
            uint256[] memory queryPathAmountsIn,
            address[] memory queryTokensIn,
            uint256[] memory queryAmountsIn
        ) = batchRouter.querySwapExactOut(paths, address(this), bytes(""));

        // Restores the network state to snapshot.
        vm.revertTo(snapshotId);

        // Executes the actual operation.
        vm.prank(alice);
        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = batchRouter
            .swapExactOut(paths, MAX_UINT256, false, bytes(""));

        // Check if results of query and actual operations are equal.
        assertApproxEqRel(pathAmountsIn[0], queryPathAmountsIn[0], errorTolerance, "pathAmountsIn's do not match");
        assertEq(tokensIn[0], queryTokensIn[0], "tokensIn's do not match");
        assertApproxEqRel(amountsIn[0], queryAmountsIn[0], errorTolerance, "amountsIn's do not match");
    }

    function _buildExactInPaths(uint256 amountIn) private returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waWETH in the yield-bearing pool,
        // and finally post-swap the waWETH through the WETH buffer to calculate the WETH amount out.
        // The only token transfers are DAI in (given) and WETH out (calculated).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waWETH, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waWETH), tokenOut: weth, isBuffer: true });

        // For ExactIn, the steps are computed in order (Wrap -> Swap -> Unwrap).
        // Compute Wrap. The exact amount is `swapAmount`. The token in is DAI, so the wrap occurs in the waDAI buffer.
        // `waDaiAmountInRaw` is the output of the wrap.
        uint256 waDaiAmountInRaw = _vaultPreviewDeposit(waDAI, amountIn);
        // Compute Swap. `waDaiAmountInRaw` is the amount in of pool swap. To compute the swap with precision, we
        // need to take into account the rates used by the Vault, instead of using a wrapper "preview" function.
        uint256 waDaiAmountInScaled18 = waDaiAmountInRaw.mulDown(waDAI.getRate());
        // Since the pool is linear, waDaiAmountInScaled18 = waWethAmountOutScaled18. Besides, since we're scaling a
        // tokenOut amount, we need to round the rate up.
        uint256 waWethAmountOutRaw = waDaiAmountInScaled18.divDown(waWETH.getRate().computeRateRoundUp());
        // Compute Unwrap. `waWethAmountOutRaw` is the output of the swap and the input of the unwrap. The amount out
        // WETH is calculated by the waWETH buffer.
        uint256 wethAmountOutRaw = _vaultPreviewRedeem(waWETH, waWethAmountOutRaw);

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: amountIn,
            minAmountOut: wethAmountOutRaw
        });
    }

    function _buildExactOutPaths(
        uint256 amountOut
    ) private returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the WETH buffer to get waWETH, then main swap waWETH for waDAI in the yield-bearing pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and WETH out (given).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waWETH, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waWETH), tokenOut: weth, isBuffer: true });

        // For ExactOut, the last step is computed first (Unwrap -> Swap -> Wrap).
        // Compute Unwrap. The exact amount out in WETH is `swapAmount` and the token out is WETH, so the unwrap
        // occurs in the waWETH buffer.
        uint256 waWethAmountOutRaw = _vaultPreviewWithdraw(waWETH, amountOut);
        // Compute Swap. `waWethAmountOutRaw` is the ExactOut amount of the pool swap. To compute the swap with
        // precision, we need to take into account the rates used by the Vault, instead of using a wrapper "preview"
        // function. Besides, since we're scaling a tokenOut amount, we need to round the rate up. Adds 1e6 to cover
        // any rate change when wrapping/unwrapping. (It tolerates a bigger amountIn, which is in favor of the Vault).
        uint256 waWethAmountOutScaled18 = waWethAmountOutRaw.mulDown(waWETH.getRate().computeRateRoundUp()) + 1e6;
        // Since the pool is linear, waWethAmountOutScaled18 = waDaiAmountInScaled18. `waDaiAmountInRaw` is the
        // calculated amount in of the pool swap, and the ExactOut value of the wrap operation.
        uint256 waDaiAmountInRaw = waWethAmountOutScaled18.divDown(waDAI.getRate());
        // Compute Wrap. The amount in DAI is calculated by the waDAI buffer.
        uint256 daiAmountInRaw = _vaultPreviewMint(waDAI, waDaiAmountInRaw);

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            maxAmountIn: daiAmountInRaw,
            exactAmountOut: amountOut
        });
    }

    function _initializeUser() private {
        dai.mint(alice, erc4626PoolInitialAmount);
    }
}
