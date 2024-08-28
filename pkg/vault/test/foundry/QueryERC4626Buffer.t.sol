// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";

contract QueryERC4626BufferTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;

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

    function _testQuerySwapExactIn(uint256 amount) private {
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _buildExactInPaths(amount);

        // Snapshots the current state of the network.
        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        // Not using staticCall because it does not allow changes in the transient storage, and reverts with
        // a StateChangeDuringStaticCall error.
        (
            uint256[] memory queryPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = batchRouter.querySwapExactIn(paths, bytes(""));

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
        ) = batchRouter.querySwapExactOut(paths, bytes(""));

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

    function _buildExactInPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        // Since this is exact in, swaps will be executed in the order given.
        // Pre-swap through DAI buffer to get waDAI, then main swap waDAI for waUSDC in the yield-bearing pool,
        // and finally post-swap the waUSDC through the USDC buffer to calculate the USDC amount out.
        // The only token transfers are DAI in (given) and USDC out (calculated).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: amount,
            minAmountOut: amount - MAX_ERROR // Remove a max of 10 wei to compensate for rounding issues and rebalance
        });
    }

    function _buildExactOutPaths(
        uint256 amount
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        // Since this is exact out, swaps will be executed in reverse order (though we submit in logical order).
        // Pre-swap through the USDC buffer to get waUSDC, then main swap waUSDC for waDAI in the yield-bearing pool,
        // and finally post-swap the waDAI for DAI through the DAI buffer to calculate the DAI amount in.
        // The only token transfers are DAI in (calculated) and USDC out (given).
        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        steps[1] = IBatchRouter.SwapPathStep({ pool: erc4626Pool, tokenOut: waUSDC, isBuffer: false });
        steps[2] = IBatchRouter.SwapPathStep({ pool: address(waUSDC), tokenOut: usdc, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: dai,
            steps: steps,
            maxAmountIn: amount + MAX_ERROR, // Add a max of 10 wei to compensate for rounding issues and rebalance
            exactAmountOut: amount
        });
    }

    function _initializeUser() private {
        dai.mint(alice, erc4626PoolInitialAmount);
    }
}
