// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract BatchRouterMutationTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testSwapExactInHookWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths;

        IBatchRouter.SwapExactInHookParams memory params = IBatchRouter.SwapExactInHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.swapExactInHook(params);
    }

    function testSwapExactOutHookWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths;
        IBatchRouter.SwapExactOutHookParams memory params = IBatchRouter.SwapExactOutHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.swapExactOutHook(params);
    }

    function testQuerySwapExactInHookWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths;

        IBatchRouter.SwapExactInHookParams memory params = IBatchRouter.SwapExactInHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.querySwapExactInHook(params);
    }

    function testQuerySwapExactOutWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths;
        IBatchRouter.SwapExactOutHookParams memory params = IBatchRouter.SwapExactOutHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.querySwapExactOutHook(params);
    }
}
