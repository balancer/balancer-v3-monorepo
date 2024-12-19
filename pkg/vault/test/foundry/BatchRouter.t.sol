// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { MOCK_BATCH_ROUTER_VERSION } from "../../contracts/test/BatchRouterMock.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testSwapDeadlineExactIn() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths;

        vm.expectRevert(RouterCommon.SwapDeadline.selector);
        batchRouter.swapExactIn(paths, block.timestamp - 1, false, bytes(""));
    }

    function testSwapDeadlineExactOut() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths;

        vm.expectRevert(RouterCommon.SwapDeadline.selector);
        batchRouter.swapExactOut(paths, block.timestamp - 1, false, bytes(""));
    }

    function testBatchRouterVersion() public view {
        assertEq(batchRouter.version(), MOCK_BATCH_ROUTER_VERSION, "BatchRouter version mismatch");
    }

    function testQuerySingleStepRemove() public {
        // create a swap step and query the batch router, where the first token is the bpt.
        IBatchRouter.SwapPathStep[] memory step = new IBatchRouter.SwapPathStep[](1);
        step[0] = IBatchRouter.SwapPathStep(address(pool()), IERC20(address(dai)), false);

        uint256 totalSupply = IERC20(pool()).totalSupply();
        uint256 bptAmountIn = 1e18;

        require(bptAmountIn < totalSupply);

        IBatchRouter.SwapPathExactAmountIn memory path = IBatchRouter.SwapPathExactAmountIn(
            IERC20(address(pool())),
            step,
            bptAmountIn,
            0
        );

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = path;

        vm.prank(alice, address(0));
        batchRouter.querySwapExactIn(paths, address(0), bytes(""));
    }
}
