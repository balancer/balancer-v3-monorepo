// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IEIP712 } from "permit2/src/interfaces/IEIP712.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract Permit2Test is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6; // USDC has 6 decimals
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
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
        router.swapSingleTokenExactIn(pool, usdc, dai, DEFAULT_AMOUNT, DEFAULT_AMOUNT, MAX_UINT256, false, bytes(""));
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

        bptAmountOut = DEFAULT_AMOUNT * 2;
        uint256[] memory amountsIn = [uint256(DEFAULT_AMOUNT), uint256(DEFAULT_AMOUNT)].toMemoryArray();

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
            uint160(DEFAULT_AMOUNT),
            type(uint48).max,
            0
        );

        bytes memory permit2Signature = getPermit2BatchSignature(
            address(router),
            [address(usdc), address(dai)].toMemoryArray(),
            uint160(DEFAULT_AMOUNT),
            type(uint48).max,
            0,
            aliceKey
        );

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = abi.encodeCall(
            IRouter.addLiquidityUnbalanced,
            (pool, amountsIn, DEFAULT_BPT_AMOUNT_ROUND_DOWN, false, bytes(""))
        );

        uint256[] memory minAmountsOut = [uint256(DEFAULT_AMOUNT_ROUND_DOWN), uint256(DEFAULT_AMOUNT_ROUND_DOWN)]
            .toMemoryArray();
        multicallData[1] = abi.encodeCall(
            IRouter.removeLiquidityProportional,
            (pool, DEFAULT_BPT_AMOUNT_ROUND_DOWN, minAmountsOut, false, bytes(""))
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

        uint256[] memory amountsIn = [uint256(DEFAULT_AMOUNT), uint256(DEFAULT_AMOUNT)].toMemoryArray();

        multicallData[0] = abi.encodeCall(
            IRouter.addLiquidityUnbalanced,
            (pool, amountsIn, DEFAULT_BPT_AMOUNT_ROUND_DOWN, false, bytes(""))
        );

        vm.expectCall(address(router), multicallData[0]);
        vm.prank(alice);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, bytes(""), multicallData);
    }

    function testPermitBatchAndCallBubbleUpRevert() public {
        uint256 badDeadline = block.timestamp - 1;

        uint256[] memory amountsIn = [uint256(DEFAULT_AMOUNT), uint256(DEFAULT_AMOUNT)].toMemoryArray();
        bptAmountOut = DEFAULT_AMOUNT * 2;

        IRouterCommon.PermitApproval[] memory permitBatch = new IRouterCommon.PermitApproval[](1);
        permitBatch[0] = IRouterCommon.PermitApproval(pool, alice, address(router), bptAmountOut, 0, badDeadline);
        IAllowanceTransfer.PermitBatch memory permit2Batch;

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

        bytes[] memory multicallData = new bytes[](1);
        multicallData[0] = abi.encodeCall(
            IRouter.addLiquidityUnbalanced,
            (pool, amountsIn, bptAmountOut, false, bytes(""))
        );

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, badDeadline));
        vm.prank(alice);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, bytes(""), multicallData);
    }

    function testPermitBatchAndCallDos() public {
        IRouterCommon.PermitApproval[] memory permitBatch = new IRouterCommon.PermitApproval[](1);
        permitBatch[0] = IRouterCommon.PermitApproval(pool, alice, address(router), DEFAULT_AMOUNT, 0, block.timestamp);
        IAllowanceTransfer.PermitBatch memory permit2Batch;
        bytes[] memory multicallData = new bytes[](0);

        bytes[] memory permitSignatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(pool),
            alice,
            address(router),
            DEFAULT_AMOUNT,
            0,
            block.timestamp,
            aliceKey
        );
        permitSignatures[0] = abi.encodePacked(r, s, v);

        // Revoke any existing allowance.
        vm.prank(alice);
        IERC20(pool).approve(address(router), 0);
        assertEq(IERC20(pool).allowance(alice, address(router)), 0, "Router allowance is not zero");

        // Bob can grant allowance for alice, using her signatures.
        vm.prank(bob);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, bytes(""), multicallData);

        assertEq(IERC20(pool).allowance(alice, address(router)), DEFAULT_AMOUNT, "Router allowance not granted");

        // Alice's call still works (error caught).
        vm.prank(alice);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, bytes(""), multicallData);

        assertEq(IERC20(pool).allowance(alice, address(router)), DEFAULT_AMOUNT, "Router allowance was reset");
    }

    function testCustomRemoveBatchAndCall() public {
        IRouterCommon.PermitApproval[] memory permitBatch = new IRouterCommon.PermitApproval[](0);
        bytes[] memory permitSignatures = new bytes[](0);
        IAllowanceTransfer.PermitBatch memory permit2Batch;
        bytes[] memory multicallData = new bytes[](2);

        uint256[] memory amountsIn = [uint256(DEFAULT_AMOUNT), uint256(DEFAULT_AMOUNT)].toMemoryArray();
        bptAmountOut = DEFAULT_BPT_AMOUNT_ROUND_DOWN;

        multicallData[0] = abi.encodeCall(
            IRouter.addLiquidityUnbalanced,
            (pool, amountsIn, bptAmountOut, false, bytes(""))
        );

        uint256[] memory amountsOut = [uint256(DEFAULT_AMOUNT), uint256(DEFAULT_AMOUNT)].toMemoryArray();
        multicallData[1] = abi.encodeCall(
            IRouter.removeLiquidityCustom,
            (pool, bptAmountOut, amountsOut, false, bytes(""))
        );

        vault.manualEnableRecoveryMode(pool);

        vm.expectCall(address(router), multicallData[0]);
        vm.prank(alice);
        router.permitBatchAndCall{ value: 1 ether }(
            permitBatch,
            permitSignatures,
            permit2Batch,
            bytes(""),
            multicallData
        );
    }

    function testRecoveryModeBatchAndCall() public {
        IRouterCommon.PermitApproval[] memory permitBatch = new IRouterCommon.PermitApproval[](0);
        bytes[] memory permitSignatures = new bytes[](0);
        IAllowanceTransfer.PermitBatch memory permit2Batch;
        bytes[] memory multicallData = new bytes[](2);

        uint256[] memory amountsIn = [uint256(DEFAULT_AMOUNT), uint256(DEFAULT_AMOUNT)].toMemoryArray();
        bptAmountOut = DEFAULT_BPT_AMOUNT_ROUND_DOWN;

        multicallData[0] = abi.encodeCall(
            IRouter.addLiquidityUnbalanced,
            (pool, amountsIn, bptAmountOut, false, bytes(""))
        );

        multicallData[1] = abi.encodeCall(
            IRouter.removeLiquidityRecovery,
            (pool, bptAmountOut, new uint256[](amountsIn.length))
        );

        vault.manualEnableRecoveryMode(pool);

        vm.expectCall(address(router), multicallData[0]);
        vm.prank(alice);
        router.permitBatchAndCall{ value: 1 ether }(
            permitBatch,
            permitSignatures,
            permit2Batch,
            bytes(""),
            multicallData
        );
    }

    function testPermitBatchAndCallMismatch() public {
        IRouterCommon.PermitApproval[] memory permitBatch = new IRouterCommon.PermitApproval[](2);
        IAllowanceTransfer.PermitBatch memory permit2Batch;
        bytes[] memory permitSignatures = new bytes[](1);
        bytes[] memory multicallData = new bytes[](1);

        multicallData[0] = abi.encodeCall(
            IRouter.addLiquidityUnbalanced,
            (pool, new uint256[](2), bptAmountOut, false, bytes(""))
        );

        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        vm.prank(alice);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, bytes(""), multicallData);
    }
}
