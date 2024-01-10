// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BalancerPoolTokenTest is BaseVaultTest {
    using ArrayHelpers for *;
    PoolMock internal poolMock;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        poolMock = PoolMock(pool);
    }

    function initPool() internal override {
        // no init
    }

    function testMetadata() public {
        assertEq(poolMock.name(), "ERC20 Pool");
        assertEq(poolMock.symbol(), "ERC20POOL");
        assertEq(poolMock.decimals(), 18);
    }

    function testMint() public {
        vault.mintERC20(address(poolMock), address(0xBEEF), defaultAmount);

        assertEq(poolMock.balanceOf(address(0xBEEF)), defaultAmount);
    }

    function testMintMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 1, 1e6));
        vault.mintERC20(address(pool), address(0xBEEF), 1);
    }

    function testBurn() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount - 1e6);

        assertEq(poolMock.balanceOf(address(0xBEEF)), 1e6);
    }

    function testBurnMinimum() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 0, 1e6));
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount);
    }

    function testApprove() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        poolMock.approve(address(0xBEEF), defaultAmount);

        assertEq(poolMock.allowance(address(this), address(0xBEEF)), defaultAmount);
    }

    function testTransfer() public {
        vault.mintERC20(address(pool), address(this), 1e18);

        assertTrue(poolMock.transfer(address(0xBEEF), 1e18));
        assertEq(poolMock.totalSupply(), 1e18);

        assertEq(poolMock.balanceOf(address(this)), 0);
        assertEq(poolMock.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(address(pool), address(from), defaultAmount);

        vm.prank(from);
        poolMock.approve(address(this), defaultAmount);

        poolMock.transferFrom(from, address(0xBEEF), defaultAmount);

        assertEq(poolMock.allowance(from, address(0xBEEF)), 0);
        assertEq(poolMock.balanceOf(address(0xBEEF)), defaultAmount);
        assertEq(poolMock.balanceOf(from), 0);
    }

    function testMintToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, 0));
        vault.mintERC20(address(pool), address(0), defaultAmount);
    }

    function testTransferFromToZero() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, defaultAmount)
        );
        poolMock.transferFrom(address(this), address(0), defaultAmount);
    }
}
