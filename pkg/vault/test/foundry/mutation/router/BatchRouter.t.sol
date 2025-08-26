// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract BatchRouterMutationTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testSwapExactInHookWhenNotVault() public {
        SwapPathExactAmountIn[] memory paths;

        SwapExactInHookParams memory params = SwapExactInHookParams(address(0), paths, 0, false, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.swapExactInHook(params);
    }

    function testSwapExactOutHookWhenNotVault() public {
        SwapPathExactAmountOut[] memory paths;
        SwapExactOutHookParams memory params = SwapExactOutHookParams(address(0), paths, 0, false, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.swapExactOutHook(params);
    }

    function testQuerySwapExactInHookWhenNotVault() public {
        SwapPathExactAmountIn[] memory paths;

        SwapExactInHookParams memory params = SwapExactInHookParams(address(0), paths, 0, false, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.querySwapExactInHook(params);
    }

    function testQuerySwapExactOutWhenNotVault() public {
        SwapPathExactAmountOut[] memory paths;
        SwapExactOutHookParams memory params = SwapExactOutHookParams(address(0), paths, 0, false, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.querySwapExactOutHook(params);
    }
}
