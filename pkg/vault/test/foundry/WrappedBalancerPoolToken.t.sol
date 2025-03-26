// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWrappedBalancerPoolToken } from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolToken.sol";

import { WrappedBalancerPoolToken } from "../../contracts/WrappedBalancerPoolToken.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract WrappedBalancerPoolTokenTest is BaseVaultTest {
    WrappedBalancerPoolToken public wBPT;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        wBPT = new WrappedBalancerPoolToken(vault, IERC20(pool), "Wrapped BPT", "wBPT");
    }

    function testConstructor() public view {
        assertEq(address(wBPT.vault()), address(vault), "Invalid vault address");
        assertEq(address(wBPT.bpt()), pool, "Invalid pool address");
    }

    function testMint() public {
        IERC20 bpt = IERC20(pool);

        uint256 balanceBefore = bpt.balanceOf(lp);

        vm.startPrank(lp);
        bpt.approve(address(wBPT), DEFAULT_AMOUNT);
        wBPT.mint(DEFAULT_AMOUNT);
        vm.stopPrank();

        assertEq(bpt.balanceOf(lp), balanceBefore - DEFAULT_AMOUNT, "Invalid BPT balance");
        assertEq(wBPT.balanceOf(lp), DEFAULT_AMOUNT, "Invalid wBPT balance");
    }

    function testMintIfVaultUnlocked() public {
        vault.forceUnlock();

        vm.expectRevert(IWrappedBalancerPoolToken.VaultIsUnlocked.selector);
        wBPT.mint(DEFAULT_AMOUNT);
    }

    function testBurn() public {
        IERC20 bpt = IERC20(pool);

        vm.startPrank(lp);
        bpt.approve(address(wBPT), DEFAULT_AMOUNT);
        wBPT.mint(DEFAULT_AMOUNT);

        uint256 balanceBefore = bpt.balanceOf(lp);
        wBPT.burn(DEFAULT_AMOUNT);
        vm.stopPrank();

        assertEq(bpt.balanceOf(lp), balanceBefore + DEFAULT_AMOUNT, "Invalid BPT balance");
        assertEq(wBPT.balanceOf(lp), 0, "Invalid wBPT balance");
    }

    function testBurnIfVaultUnlocked() public {
        vault.forceUnlock();

        vm.expectRevert(IWrappedBalancerPoolToken.VaultIsUnlocked.selector);
        wBPT.burn(DEFAULT_AMOUNT);
    }

    function testBurnFrom() public {
        IERC20 bpt = IERC20(pool);

        vm.startPrank(lp);
        bpt.approve(address(wBPT), DEFAULT_AMOUNT);
        wBPT.mint(DEFAULT_AMOUNT);
        vm.stopPrank();

        uint256 balanceBefore = bpt.balanceOf(lp);

        vm.prank(lp);
        wBPT.approve(alice, DEFAULT_AMOUNT);

        vm.prank(alice);
        wBPT.burnFrom(lp, DEFAULT_AMOUNT);

        assertEq(bpt.balanceOf(lp), balanceBefore + DEFAULT_AMOUNT, "Invalid BPT balance");
        assertEq(wBPT.balanceOf(lp), 0, "Invalid wBPT balance");
    }

    function testBurnFromIfVaultUnlocked() public {
        vault.forceUnlock();

        vm.expectRevert(IWrappedBalancerPoolToken.VaultIsUnlocked.selector);
        wBPT.burnFrom(lp, DEFAULT_AMOUNT);
    }
}
