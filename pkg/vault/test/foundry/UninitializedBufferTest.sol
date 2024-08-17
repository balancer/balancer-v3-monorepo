// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract UnInitializedBufferTest is BaseVaultTest {
    ERC4626TestToken internal waDAI;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        vm.startPrank(alice);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));
    }

    function testAddLiquidityToBufferUninitialized() public {
        uint256 amountIn = 1e18;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferNotInitialized.selector, waDAI));
        router.addLiquidityToBuffer(waDAI, amountIn, amountIn);
    }

    function testRemoveLiquidityFromBufferUninitialized() public {
        uint256 sharesIn = 1e18;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferNotInitialized.selector, waDAI));
        vault.removeLiquidityFromBuffer(waDAI, sharesIn);
    }

    function testWrapUnwrapBufferUninitialized() public {
        IBatchRouter.SwapPathExactAmountIn[] memory path = _buildSimpleWrapExactInPath();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BufferNotInitialized.selector, waDAI));
        batchRouter.swapExactIn(path, MAX_UINT256, false, bytes(""));
    }

    /// @dev Simple batch swap with single wrap step (waDAI)
    function _buildSimpleWrapExactInPath() private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        uint256 amount = 1e18;
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(waDAI), tokenOut: waDAI, isBuffer: true });
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: dai,
            steps: steps,
            exactAmountIn: amount,
            minAmountOut: amount - 1 // rebalance tests are a wei off
        });
    }
}
