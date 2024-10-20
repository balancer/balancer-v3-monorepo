// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

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
}
