// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IEIP712 } from "permit2/src/interfaces/IEIP712.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract Permit2Test is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6;
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
    uint256 internal ethAmountIn = 1e3 ether;
    uint256 internal initBpt = 10e18;
    uint256 internal bptAmountOut = 1e18;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testNoPermitCall() public {
        // Revoke allowance.
        vm.prank(alice);
        permit2.approve(address(usdc), address(router), 0, 0);

        (uint160 amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        assertEq(amount, 0);

        vm.expectRevert(abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0));
        router.swapSingleTokenExactIn(pool, usdc, dai, defaultAmount, defaultAmount, MAX_UINT256, false, bytes(""));
    }

    function testPermitBatchAndCall() public {
        // Revoke allowance.
        vm.prank(alice);
        permit2.approve(address(usdc), address(router), 0, 0);
        vm.prank(alice);
        permit2.approve(address(dai), address(router), 0, 0);
        vm.prank(alice);
        IERC20(pool).approve(address(router), 0);

        (uint160 amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        assertEq(amount, 0);
        (amount, , ) = permit2.allowance(alice, address(dai), address(router));
        assertEq(amount, 0);
        assertEq(IERC20(pool).allowance(alice, address(router)), 0, "Router allowance is not zero");

        bptAmountOut = defaultAmount * 2;
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        IRouterCommon.PermitApproval[] memory permitBatch = new IRouterCommon.PermitApproval[](1);
        permitBatch[0] = IRouterCommon.PermitApproval(pool, alice, address(router), bptAmountOut, 0, block.timestamp);

        bytes[] memory permitSignatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(pool),
            alice,
            address(router),
            bptAmountOut,
            0,
            block.timestamp,
            aliceKey
        );
        permitSignatures[0] = abi.encodePacked(r, s, v);

        IAllowanceTransfer.PermitBatch memory permit2Batch = getPermit2Batch(
            address(router),
            [address(usdc), address(dai)].toMemoryArray(),
            uint160(defaultAmount),
            type(uint48).max,
            0
        );

        bytes memory permit2Signature = getPermit2BatchSignature(
            address(router),
            [address(usdc), address(dai)].toMemoryArray(),
            uint160(defaultAmount),
            type(uint48).max,
            0,
            aliceKey
        );

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = abi.encodeWithSelector(
            IRouter.addLiquidityUnbalanced.selector,
            pool,
            amountsIn,
            bptAmountOut,
            false,
            bytes("")
        );

        uint256[] memory minAmountsOut = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();
        multicallData[1] = abi.encodeWithSelector(
            IRouter.removeLiquidityProportional.selector,
            pool,
            bptAmountOut,
            minAmountsOut,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, permit2Signature, multicallData);

        // Alice has no BPT.
        assertEq(IERC20(pool).balanceOf(alice), 0, "Alice has pool tokens");

        (amount, , ) = permit2.allowance(alice, address(dai), address(router));
        // Allowance is spent.
        assertEq(amount, 0, "DAI allowance is not spent");

        (amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        // Allowance is spent.
        assertEq(amount, 0, "USDC allowance is not spent");
    }

    function testEmptyBatchAndCall() public {
        IRouterCommon.PermitApproval[] memory permitBatch = new IRouterCommon.PermitApproval[](0);
        bytes[] memory permitSignatures = new bytes[](0);
        IAllowanceTransfer.PermitBatch memory permit2Batch;
        bytes[] memory multicallData = new bytes[](1);

        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();
        bptAmountOut = defaultAmount * 2;

        multicallData[0] = abi.encodeWithSelector(
            IRouter.addLiquidityUnbalanced.selector,
            pool,
            amountsIn,
            bptAmountOut,
            false,
            bytes("")
        );

        vm.expectCall(address(router), multicallData[0]);
        vm.prank(alice);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, "", multicallData);
    }
}
