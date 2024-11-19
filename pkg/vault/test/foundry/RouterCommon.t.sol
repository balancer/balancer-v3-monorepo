// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ReentrancyAttack } from "@balancer-labs/v3-solidity-utils/contracts/test/ReentrancyAttack.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { RouterCommonMock } from "../../contracts/test/RouterCommonMock.sol";

contract RouterCommonTest is BaseVaultTest {
    ReentrancyAttack internal reentrancyAttack;
    RouterCommonMock internal routerMock;

    function setUp() public virtual override {
        super.setUp();

        routerMock = deployRouterCommonMock(IVault(address(vault)), weth, permit2);
        reentrancyAttack = new ReentrancyAttack();
    }

    function testConstructor() external {
        RouterCommonMock anotherRouter = deployRouterCommonMock(IVault(address(vault)), weth, permit2);
        assertEq(address(anotherRouter.getVault()), address(vault), "Vault is wrong");
        assertEq(address(anotherRouter.getWeth()), address(weth), "Weth is wrong");
        assertEq(address(anotherRouter.getPermit2()), address(permit2), "Permit2 is wrong");
    }

    function testSaveSenderAndCall() external {
        vm.expectEmit();
        emit RouterCommonMock.CurrentSenderMock(address(this));
        routerMock.call(address(routerMock), abi.encodeWithSelector(RouterCommonMock.emitSender.selector));
    }

    function testSenderSlot() external view {
        assertEq(
            StorageSlotExtension.AddressSlotType.unwrap(routerMock.manualGetSenderSlot()),
            keccak256(abi.encode(uint256(keccak256("balancer-labs.v3.storage.RouterCommon.sender")) - 1)) &
                ~bytes32(uint256(0xff))
        );
    }

    // This test verifies that the sender does not change when another sender reenter.
    function testSaveSenderAndCallWithReentrancyAttack() external {
        vm.expectEmit();
        emit RouterCommonMock.CurrentSenderMock(address(this));

        routerMock.call(
            address(reentrancyAttack),
            abi.encodeWithSelector(
                ReentrancyAttack.callSender.selector,
                abi.encodeWithSelector(
                    RouterCommonMock.call.selector,
                    routerMock,
                    abi.encodeWithSelector(RouterCommonMock.emitSender.selector)
                )
            )
        );
    }

    function testTakeTokenInWethIsEth() public {
        uint256 routerEthBalance = address(routerMock).balance;

        vm.expectRevert(RouterCommon.InsufficientEth.selector);
        routerMock.mockTakeTokenIn(bob, IERC20(weth), routerEthBalance + 1, true);
    }

    function testTakeTokenInWethIsNotEth() public {
        vault.forceUnlock();

        uint256 amountToDeposit = weth.balanceOf(bob) / 100;

        EthStateTest memory vars = _createEthStateTest();

        vm.startPrank(bob);
        IERC20(weth).approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(routerMock), type(uint160).max, type(uint48).max);

        routerMock.mockTakeTokenIn(bob, IERC20(weth), amountToDeposit, false);
        vm.stopPrank();

        _fillEthStateTestAfter(vars);

        assertEq(vars.bobEthAfter, vars.bobEthBefore, "Bob ETH balance is wrong");
        assertEq(vars.vaultEthBefore, 0, "Vault had ETH balance before");
        assertEq(vars.vaultEthAfter, 0, "Vault has ETH balance after");
        assertEq(vars.bobWethAfter, vars.bobWethBefore - amountToDeposit, "Bob WETH balance is wrong");
        assertEq(vars.vaultWethAfter, vars.vaultWethBefore + amountToDeposit, "Vault WETH balance is wrong");
        assertEq(vars.wethDeltaAfter, vars.wethDeltaBefore - int256(amountToDeposit), "Vault delta is wrong");
    }

    function testTakeTokenInTooLarge() public {
        vault.forceUnlock();

        uint256 amountToDeposit = type(uint168).max;

        vm.startPrank(bob);
        IERC20(weth).approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(routerMock), type(uint160).max, type(uint48).max);

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 160, amountToDeposit));
        routerMock.mockTakeTokenIn(bob, IERC20(weth), amountToDeposit, false);
        vm.stopPrank();
    }

    function testSendTokenOutWethIsEth() public {
        vault.forceUnlock();

        vm.startPrank(lp);
        uint256 wethDeposit = lp.balance / 10;
        weth.deposit{ value: wethDeposit }();
        weth.transfer(address(vault), wethDeposit);
        vault.settle(weth, wethDeposit);
        vm.stopPrank();

        EthStateTest memory vars = _createEthStateTest();

        uint256 amountToWithdraw = vars.vaultWethBefore / 100;
        assertGt(amountToWithdraw, 0, "Amount to withdraw is 0");

        routerMock.mockSendTokenOut(bob, IERC20(weth), amountToWithdraw, true);

        _fillEthStateTestAfter(vars);

        assertEq(vars.bobEthAfter, vars.bobEthBefore + amountToWithdraw, "Bob ETH balance is wrong");
        assertEq(vars.vaultEthBefore, 0, "Vault had ETH balance before");
        assertEq(vars.vaultEthAfter, 0, "Vault has ETH balance after");
        assertEq(vars.bobWethAfter, vars.bobWethBefore, "Bob WETH balance is wrong");
        assertEq(vars.vaultWethAfter, vars.vaultWethBefore - amountToWithdraw, "Vault WETH balance is wrong");
        assertEq(vars.wethDeltaAfter, vars.wethDeltaBefore + int256(amountToWithdraw), "Vault delta is wrong");
    }

    function testSendTokenOutWethIsNotEth() public {
        vault.forceUnlock();

        EthStateTest memory vars = _createEthStateTest();

        uint256 amountToWithdraw = vars.vaultWethBefore / 100;

        routerMock.mockSendTokenOut(bob, IERC20(weth), amountToWithdraw, false);

        _fillEthStateTestAfter(vars);

        assertEq(vars.bobEthAfter, vars.bobEthBefore, "Bob ETH balance is wrong");
        assertEq(vars.vaultEthAfter, vars.vaultEthBefore, "Vault ETH balance is wrong");
        assertEq(vars.bobWethAfter, vars.bobWethBefore + amountToWithdraw, "Bob WETH balance is wrong");
        assertEq(vars.vaultWethAfter, vars.vaultWethBefore - amountToWithdraw, "Vault WETH balance is wrong");
        assertEq(vars.wethDeltaAfter, vars.wethDeltaBefore + int256(amountToWithdraw), "Vault delta is wrong");
    }

    function testSaveSenderAndManageEthModifierWithSingleFunction() public {
        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        routerMock.multicall{ value: 1 ether }(new bytes[](0));
        uint256 balanceAfter = alice.balance;

        assertEq(balanceAfter, balanceBefore, "Value wasn't returned");
    }

    function testSaveSenderAndManageEthModifierWithMultipleFunctions() public {
        uint256 extraAmount = 0.5 ether;
        uint256 balanceBefore = alice.balance;

        bytes[] memory calls = new bytes[](3);
        // Send extra ETH to the mock contract
        calls[0] = abi.encodeWithSelector(RouterCommonMock.sendExtraEth.selector, alice, extraAmount);
        // Try to return the extra ETH but this function will ignore sending the ETH back
        calls[1] = abi.encodeWithSelector(RouterCommonMock.manualReturnETH.selector);
        // Assert that the manualReturnETH function didn't send the ETH back
        calls[2] = abi.encodeWithSelector(RouterCommonMock.assertETHBalance.selector, balanceBefore - extraAmount);

        vm.prank(alice);
        routerMock.multicall{ value: 1 ether }(calls);
        uint256 balanceAfter = alice.balance;

        assertEq(balanceAfter, balanceBefore, "Value wasn't returned");
    }

    function testPermitBatchReentrancy() public {
        IRouterCommon.PermitApproval[] memory permitBatch;
        bytes[] memory permitSignatures;
        IAllowanceTransfer.PermitBatch memory permit2Batch;
        bytes memory permit2Signature;

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        routerMock.manualPermitBatchReentrancy(permitBatch, permitSignatures, permit2Batch, permit2Signature);
    }

    struct EthStateTest {
        uint256 bobEthBefore;
        uint256 bobEthAfter;
        uint256 bobWethBefore;
        uint256 bobWethAfter;
        uint256 vaultEthBefore;
        uint256 vaultEthAfter;
        uint256 vaultWethBefore;
        uint256 vaultWethAfter;
        int256 wethDeltaBefore;
        int256 wethDeltaAfter;
    }

    function _createEthStateTest() private view returns (EthStateTest memory vars) {
        vars.bobEthBefore = bob.balance;
        vars.bobWethBefore = IERC20(address(weth)).balanceOf(bob);

        vars.vaultEthBefore = address(vault).balance;
        vars.vaultWethBefore = IERC20(address(weth)).balanceOf(address(vault));
        vars.wethDeltaBefore = vault.getTokenDelta(weth);
    }

    function _fillEthStateTestAfter(EthStateTest memory vars) private view {
        vars.bobEthAfter = bob.balance;
        vars.bobWethAfter = IERC20(address(weth)).balanceOf(bob);

        vars.vaultEthAfter = address(vault).balance;
        vars.vaultWethAfter = IERC20(address(weth)).balanceOf(address(vault));
        vars.wethDeltaAfter = vault.getTokenDelta(weth);
    }
}
