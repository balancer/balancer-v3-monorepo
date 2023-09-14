// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC20Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/token/IERC20Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20FacadeToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20FacadeToken.sol";

import { PoolMock } from "@balancer-labs/v3-pool-utils/contracts/test/PoolMock.sol";
import { ERC20FacadeToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20FacadeToken.sol";
import { Vault } from "../../contracts/Vault.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract ERC20FacadeTokenTest is Test {
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];

    VaultMock vault;
    PoolMock token;

    function setUp() public {
        vault = new VaultMock(30 days, 90 days);
        token = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            address(0),
            [address(0x1), address(0x2)].toMemoryArray().asIERC20(),
            true
        );
    }

    function testMetadata() public {
        assertEq(token.name(), "ERC20 Pool");
        assertEq(token.symbol(), "ERC20POOL");
        assertEq(token.decimals(), 18);
    }

    function testMint() public {
        vault.mintERC20(address(token), address(0xBEEF), 1337);

        assertEq(token.balanceOf(address(0xBEEF)), 1337);
    }

    function testBurn() public {
        vault.mintERC20(address(token), address(0xBEEF), 1337);
        vault.burnERC20(address(token), address(0xBEEF), 1337);

        assertEq(token.balanceOf(address(0xBEEF)), 0);
    }

    function testApprove() public {
        vault.mintERC20(address(token), address(this), 1337);

        token.approve(address(0xBEEF), 1337);

        assertEq(token.allowance(address(this), address(0xBEEF)), 1337);
    }

    function testApproveBurn() public {
        vault.mintERC20(address(token), address(this), 1337);

        token.approve(address(0xBEEF), 1337);

        vault.burnERC20(address(token), address(this), 1337);

        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransfer() public {
        vault.mintERC20(address(token), address(this), 1e18);

        assertTrue(token.transfer(address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(address(token), address(from), 1337);

        vm.prank(from);
        token.approve(address(this), 1337);

        token.transferFrom(from, address(0xBEEF), 1337);

        assertEq(token.allowance(from, address(0xBEEF)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1337);
        assertEq(token.balanceOf(from), 0);
    }

    function testMintToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, 0));
        vault.mintERC20(address(token), address(0), 1337);
    }

    function testTransferFromToZero() public {
        vault.mintERC20(address(token), address(this), 1337);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1337)
        );
        token.transferFrom(address(this), address(0), 1337);
    }
}
