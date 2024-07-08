// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ReentrancyAttack } from "@balancer-labs/v3-solidity-utils/contracts/test/ReentrancyAttack.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { RouterCommonMock } from "../../contracts/test/RouterCommonMock.sol";

contract RouterCommonTest is BaseVaultTest {
    ReentrancyAttack internal reentrancyAttack;
    RouterCommonMock internal routerCommonMock;

    function setUp() public virtual override {
        super.setUp();

        routerCommonMock = new RouterCommonMock(IVault(address(vault)), weth, permit2);
        reentrancyAttack = new ReentrancyAttack();
    }

    function testSaveSenderAndCall() external {
        vm.expectEmit();
        emit RouterCommonMock.CurrentSenderMock(address(this));
        routerCommonMock.call(address(routerCommonMock), abi.encodeWithSelector(RouterCommonMock.emitSender.selector));
    }

    function testSenderSlot() external view {
        assertEq(
            StorageSlotExtension.AddressSlotType.unwrap(routerCommonMock.manualGetSenderSlot()),
            keccak256(abi.encode(uint256(keccak256("balancer-labs.v3.storage.RouterCommon.sender")) - 1)) &
                ~bytes32(uint256(0xff))
        );
    }

    // This test verifies that the sender does not change when another sender reenter.
    function testSaveSenderAndCallWithReentrancyAttack() external {
        vm.expectEmit();
        emit RouterCommonMock.CurrentSenderMock(address(this));

        routerCommonMock.call(
            address(reentrancyAttack),
            abi.encodeWithSelector(
                ReentrancyAttack.callSender.selector,
                abi.encodeWithSelector(
                    RouterCommonMock.call.selector,
                    routerCommonMock,
                    abi.encodeWithSelector(RouterCommonMock.emitSender.selector)
                )
            )
        );
    }

    function testTakeTokenInInsufficientEth() public {
        uint256 routerEthBalance = address(routerCommonMock).balance;

        vm.expectRevert(RouterCommon.InsufficientEth.selector);
        routerCommonMock.mockTakeTokenIn(bob, IERC20(weth), routerEthBalance + 1, true);
    }

    function testTakeTokenInWEthIsNotEth() public {
        vault.manualSetIsUnlocked(true);
        uint256 amountToDeposit = weth.balanceOf(bob) / 100;

        uint256 wethBobBefore = IERC20(address(weth)).balanceOf(bob);
        uint256 wethVaultBefore = IERC20(address(weth)).balanceOf(address(vault));

        vm.startPrank(bob);
        IERC20(weth).approve(address(permit2), type(uint256).max);
        permit2.approve(address(weth), address(routerCommonMock), type(uint160).max, type(uint48).max);

        routerCommonMock.mockTakeTokenIn(bob, IERC20(weth), amountToDeposit, false);
        vm.stopPrank();

        uint256 wethBobAfter = IERC20(address(weth)).balanceOf(bob);
        uint256 wethVaultAfter = IERC20(address(weth)).balanceOf(address(vault));

        assertEq(wethBobAfter, wethBobBefore - amountToDeposit, "Bob weth balance is wrong");
        assertEq(wethVaultAfter, wethVaultBefore + amountToDeposit, "Vault weth balance is wrong");
    }

    function testSendTokenOutWethIsEth() public {
        vault.manualSetIsUnlocked(true);

        uint256 bobEthBalanceBefore = bob.balance;
        uint256 vaultEthBalanceBefore = address(vault).balance;

        uint256 amountToWithdraw = vaultEthBalanceBefore / 100;

        routerCommonMock.mockSendTokenOut(bob, IERC20(weth), amountToWithdraw, true);

        uint256 bobEthBalanceAfter = bob.balance;
        uint256 vaultEthBalanceAfter = address(vault).balance;

        assertEq(bobEthBalanceAfter, bobEthBalanceBefore + amountToWithdraw, "Bob ETH balance is wrong");
        assertEq(vaultEthBalanceAfter, vaultEthBalanceBefore - amountToWithdraw, "Vault ETH balance is wrong");
    }

    function testSendTokenOutWethIsNotEth() public {
        vault.manualSetIsUnlocked(true);

        uint256 wethBobBefore = IERC20(address(weth)).balanceOf(bob);
        uint256 wethVaultBefore = IERC20(address(weth)).balanceOf(address(vault));

        uint256 amountToWithdraw = wethVaultBefore / 100;

        routerCommonMock.mockSendTokenOut(bob, IERC20(weth), amountToWithdraw, false);

        uint256 wethBobAfter = IERC20(address(weth)).balanceOf(bob);
        uint256 wethVaultAfter = IERC20(address(weth)).balanceOf(address(vault));

        assertEq(wethBobAfter, wethBobBefore + amountToWithdraw, "Bob WETH balance is wrong");
        assertEq(wethVaultAfter, wethVaultBefore - amountToWithdraw, "Vault WETH balance is wrong");
    }
}
