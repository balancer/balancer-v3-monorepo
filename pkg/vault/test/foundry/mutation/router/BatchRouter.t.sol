// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";

contract BatchRouterMutationTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testQuery() public {
        // create a swap step and query the batch router, where the first token is
        // the bpt. 
        IBatchRouter.SwapPathStep[] memory step = new IBatchRouter.SwapPathStep[](1);
        step[0] = IBatchRouter.SwapPathStep(address(pool), IERC20(address(dai)), false);

        uint256 totalSupply = IERC20(pool).totalSupply();
        console.log("total BPT supply", totalSupply);
        uint256 bptAmountIn = 1e18;

        require(bptAmountIn < totalSupply);

        IBatchRouter.SwapPathExactAmountIn memory path = IBatchRouter.SwapPathExactAmountIn(
            IERC20(address(pool)),
            step,
            bptAmountIn,
            0
        );

        IBatchRouter.SwapPathExactAmountIn[] memory paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = path;
    
        vm.prank(alice, address(0));
        batchRouter.querySwapExactIn(paths, address(0), bytes(""));
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
