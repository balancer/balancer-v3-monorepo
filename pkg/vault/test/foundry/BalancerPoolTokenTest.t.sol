// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";

import { VaultUtils } from "./utils/VaultUtils.sol";

contract BalancerPoolTokenTest is VaultUtils {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        VaultUtils.setUp();
    }

    function initPool() internal override {}

    function testMetadata() public {
        assertEq(pool.name(), "ERC20 Pool");
        assertEq(pool.symbol(), "ERC20POOL");
        assertEq(pool.decimals(), 18);
    }

    function testMint() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);

        assertEq(pool.balanceOf(address(0xBEEF)), defaultAmount);
    }

    function testMintMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 1, 1e6));
        vault.mintERC20(address(pool), address(0xBEEF), 1);
    }

    function testBurn() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount - 1e6);

        assertEq(pool.balanceOf(address(0xBEEF)), 1e6);
    }

    function testBurnMinimum() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 0, 1e6));
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount);
    }

    function testApprove() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        pool.approve(address(0xBEEF), defaultAmount);

        assertEq(pool.allowance(address(this), address(0xBEEF)), defaultAmount);
    }

    function testTransfer() public {
        vault.mintERC20(address(pool), address(this), 1e18);

        assertTrue(pool.transfer(address(0xBEEF), 1e18));
        assertEq(pool.totalSupply(), 1e18);

        assertEq(pool.balanceOf(address(this)), 0);
        assertEq(pool.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(address(pool), address(from), defaultAmount);

        vm.prank(from);
        pool.approve(address(this), defaultAmount);

        pool.transferFrom(from, address(0xBEEF), defaultAmount);

        assertEq(pool.allowance(from, address(0xBEEF)), 0);
        assertEq(pool.balanceOf(address(0xBEEF)), defaultAmount);
        assertEq(pool.balanceOf(from), 0);
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
        pool.transferFrom(address(this), address(0), defaultAmount);
    }
}
