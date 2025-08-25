// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";


import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract UnInitializedBufferTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();

        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));
    }

    function testAddLiquidityToBufferUninitialized() public {
        uint256 exactSharesToIssue = 1e18;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferNotInitialized.selector, waDAI));
        bufferRouter.addLiquidityToBuffer(waDAI, MAX_UINT128, MAX_UINT128, exactSharesToIssue);
    }

    function testRemoveLiquidityFromBufferUninitialized() public {
        uint256 sharesIn = 1e18;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferNotInitialized.selector, waDAI));
        vault.removeLiquidityFromBuffer(waDAI, sharesIn, 0, 0);
    }

    function testWrapUnwrapBufferUninitialized() public {
        SwapPathExactAmountIn[] memory path = _buildSimpleWrapExactInPath();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferNotInitialized.selector, waDAI));
        batchRouter.swapExactIn(path, MAX_UINT256, false, bytes(""));
    }

    /// @dev Simple batch swap with single wrap step (waDAI)
    function _buildSimpleWrapExactInPath() private view returns (SwapPathExactAmountIn[] memory paths) {
        uint256 amount = 1e18;
        SwapPathStep[] memory steps = new SwapPathStep[](1);
        paths = new SwapPathExactAmountIn[](1);

        steps[0] = SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        paths[0] = SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: amount,
            minAmountOut: amount - 1 // rebalance tests are a wei off
        });
    }
}
