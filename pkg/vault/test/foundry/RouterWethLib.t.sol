// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { RouterWethLib } from "../../contracts/lib/RouterWethLib.sol";

// @dev The test contract will act as the router.
contract RouterWethLibTest is BaseVaultTest {
    uint256 internal constant TRANSFER_AMOUNT = 1e18;

    function setUp() public override {
        BaseVaultTest.setUp();

        // Ensure the contract has no ETH balance.
        (bool success, ) = payable(0).call{ value: address(this).balance }("");
        require(success, "Failed to send ETH to address 0");
    }

    function testWrapEthAndSettleInsufficientBalance() public {
        // Ensure contract has no ETH balance
        require(address(this).balance < TRANSFER_AMOUNT, "Contract has ETH");

        vm.expectRevert(RouterWethLib.InsufficientEth.selector);
        RouterWethLib.wrapEthAndSettle(weth, vault, TRANSFER_AMOUNT);
    }

    function testWrapEthAndSettleSuccess() public {
        // Send ETH to contract
        vm.deal(address(this), TRANSFER_AMOUNT);
        require(address(this).balance >= TRANSFER_AMOUNT, "Contract does not have ETH");

        uint256 vaultWethBalanceBefore = weth.balanceOf(address(vault));
        uint256 vaultWethReserveBefore = vault.getReservesOf(weth);
        uint256 routerWethBalanceBefore = weth.balanceOf(address(this));
        uint256 routerEthBalanceBefore = address(this).balance;

        vault.forceUnlock();
        RouterWethLib.wrapEthAndSettle(weth, vault, TRANSFER_AMOUNT);

        // Vault balances and reserves.
        assertEq(
            weth.balanceOf(address(vault)),
            vaultWethBalanceBefore + TRANSFER_AMOUNT,
            "Vault WETH balance should increase"
        );
        assertEq(
            vault.getReservesOf(weth),
            vaultWethReserveBefore + TRANSFER_AMOUNT,
            "Vault WETH reserve should increase"
        );

        // Router balances.
        assertEq(address(this).balance, routerEthBalanceBefore - TRANSFER_AMOUNT, "Router ETH balance should decrease");
        assertEq(weth.balanceOf(address(this)), routerWethBalanceBefore, "Router WETH balance should not change");
    }

    function testUnwrapWethAndTransferToSenderInsufficientBalance() public {
        // Ensure Vault has no WETH balance.
        vm.startPrank(address(vault));
        weth.transfer(address(1), weth.balanceOf(address(vault)));
        vm.stopPrank();

        vault.forceUnlock();
        vm.expectRevert(); // Expect math underflow due to insufficient WETH balance
        RouterWethLibTest(payable(this)).externalUnwrapWethAndTransferToSender(
            weth,
            vault,
            address(this),
            TRANSFER_AMOUNT
        );
    }

    function testUnwrapWethAndTransferToSenderSuccess() public {
        // Send WETH to Vault.
        vm.deal(address(this), TRANSFER_AMOUNT);

        vault.forceUnlock();
        RouterWethLib.wrapEthAndSettle(weth, vault, TRANSFER_AMOUNT);

        require(weth.balanceOf(address(vault)) >= TRANSFER_AMOUNT, "Vault has insufficient WETH");

        uint256 vaultWethBalanceBefore = weth.balanceOf(address(vault));
        uint256 vaultWethReserveBefore = vault.getReservesOf(weth);
        uint256 routerWethBalanceBefore = weth.balanceOf(address(this));
        uint256 routerEthBalanceBefore = address(this).balance;

        RouterWethLib.unwrapWethAndTransferToSender(weth, vault, address(this), TRANSFER_AMOUNT);

        // Vault balances and reserves.
        assertEq(
            weth.balanceOf(address(vault)),
            vaultWethBalanceBefore - TRANSFER_AMOUNT,
            "Vault WETH balance should decrease"
        );
        assertEq(
            vault.getReservesOf(weth),
            vaultWethReserveBefore - TRANSFER_AMOUNT,
            "Vault WETH reserve should decrease"
        );

        // Router balances.
        assertEq(address(this).balance, routerEthBalanceBefore + TRANSFER_AMOUNT, "Router ETH balance should increase");
        assertEq(weth.balanceOf(address(this)), routerWethBalanceBefore, "Router WETH balance should not change");
    }

    // Required to receive ETH
    receive() external payable {}

    function externalUnwrapWethAndTransferToSender(IWETH weth, IVault vault, address sender, uint256 amount) external {
        RouterWethLib.unwrapWethAndTransferToSender(weth, vault, sender, amount);
    }
}
