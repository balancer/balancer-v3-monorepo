// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IMinimumSwapFee } from "@balancer-labs/v3-interfaces/contracts/vault/IMinimumSwapFee.sol";

import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BalancerPoolToken } from "vault/contracts/BalancerPoolToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BalancerPoolTokenTest is BaseVaultTest {
    using ArrayHelpers for *;
    PoolMock internal poolToken;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 private constant CURRENT_NONCE = 0;

    uint256 internal constant MINIMUM_TOTAL_SUPPLY = 1e6;

    uint256 internal privateKey = 0xBEEF;
    address user = vm.addr(privateKey);

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        poolToken = PoolMock(pool);
    }

    function initPool() internal override {
        // no init
    }

    function testMetadata() public {
        assertEq(poolToken.name(), "ERC20 Pool", "name mismatch");
        assertEq(poolToken.symbol(), "ERC20POOL", "symbol mismatch");
        assertEq(poolToken.decimals(), 18, "decimals mismatch");
    }

    function testMint() public {
        vm.expectEmit();
        emit IERC20.Transfer(address(0), user, defaultAmount);

        vault.mintERC20(address(poolToken), user, defaultAmount);

        assertEq(poolToken.balanceOf(user), defaultAmount, "balance mismatch");
    }

    function testBurn() public {
        uint256 burnAmount = defaultAmount - MINIMUM_TOTAL_SUPPLY;

        vault.mintERC20(address(pool), user, defaultAmount);

        vm.expectEmit();
        emit IERC20.Transfer(user, address(0), burnAmount);
        vault.burnERC20(address(pool), user, burnAmount);

        assertEq(poolToken.balanceOf(user), MINIMUM_TOTAL_SUPPLY, "balance mismatch");
    }

    function testApprove() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        vm.expectEmit();
        emit IERC20.Approval(address(this), user, defaultAmount);
        poolToken.approve(user, defaultAmount);

        assertEq(poolToken.allowance(address(this), user), defaultAmount, "allowance mismatch");
    }

    function testTransfer() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        vm.expectEmit();
        emit IERC20.Transfer(address(this), user, defaultAmount);
        assertTrue(poolToken.transfer(user, defaultAmount), "transfer failed");
        assertEq(poolToken.totalSupply(), defaultAmount, "total supply mismatch");

        assertEq(poolToken.balanceOf(address(this)), 0, "address(this) balance mismatch");
        assertEq(poolToken.balanceOf(user), defaultAmount, "user balance mismatch");
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(address(pool), address(from), defaultAmount);

        vm.prank(from);
        poolToken.approve(address(this), defaultAmount);

        vm.expectEmit();
        emit IERC20.Approval(from, address(this), 0);

        vm.expectEmit();
        emit IERC20.Transfer(from, user, defaultAmount);

        poolToken.transferFrom(from, user, defaultAmount);

        assertEq(poolToken.allowance(from, user), 0, "allowance(from, user) isn't 0");
        assertEq(poolToken.balanceOf(user), defaultAmount, "user balance mismatch");
        assertEq(poolToken.balanceOf(from), 0, "sender balance mismatch");
    }

    function testPermit() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);

        assertEq(poolToken.allowance(user, address(0xCAFE)), defaultAmount, "allowance mismatch");
        assertEq(poolToken.nonces(user), CURRENT_NONCE + 1, "nonce mismatch");
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadNonce() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE + 1,
            block.timestamp,
            privateKey
        );

        vm.expectRevert(bytes(""));
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadDeadline() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp + 1, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitPastDeadline() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp - 1, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitReplay() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
    }

    function testPermit__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, MAX_UINT256);
        vm.assume(privKey != 0);

        address usr = vm.addr(privKey);

        vm.assume(to != address(0));
        vm.assume(to != address(usr));
        vm.assume(to != address(vault));

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            usr,
            to,
            amount,
            CURRENT_NONCE,
            deadline,
            privKey
        );

        poolToken.permit(usr, to, amount, deadline, v, r, s);

        assertEq(poolToken.allowance(usr, to), amount, "allowance mismatch");
        assertEq(poolToken.nonces(usr), CURRENT_NONCE + 1, "nonce mismatch");
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadNonce__Fuzz(
        uint256 privKey,
        address to,
        uint256 amount,
        uint256 deadline,
        uint256 nonce
    ) public {
        deadline = bound(deadline, block.timestamp, MAX_UINT256);
        vm.assume(privKey != 0);
        vm.assume(to != address(0));
        vm.assume(nonce != 0);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            usr,
            to,
            amount,
            nonce,
            deadline,
            privKey
        );

        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadDeadline__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        deadline = bound(deadline, 0, block.timestamp - 1);
        vm.assume(privKey != 0);
        vm.assume(to != address(0));

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            usr,
            to,
            amount,
            CURRENT_NONCE,
            deadline,
            privKey
        );

        poolToken.permit(usr, to, amount, deadline + 1, v, r, s);
    }

    function testPermitPastDeadline__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        vm.assume(privKey != 0);
        vm.assume(to != address(0));
        deadline = bound(deadline, 0, block.timestamp - 1);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            usr,
            to,
            amount,
            CURRENT_NONCE,
            deadline,
            privKey
        );

        vm.expectRevert(abi.encodeWithSelector(BalancerPoolToken.ERC2612ExpiredSignature.selector, deadline));
        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitReplay__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        vm.assume(privKey != 0);
        vm.assume(to != address(0));
        deadline = bound(deadline, block.timestamp, MAX_UINT256);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(poolToken)),
            usr,
            to,
            amount,
            CURRENT_NONCE,
            deadline,
            privKey
        );

        poolToken.permit(usr, to, amount, deadline, v, r, s);
        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }

    function testSupportsIERC165() public {
        assertTrue(poolToken.supportsInterface(type(IERC165).interfaceId), "IERC165 not supported");
        assertFalse(poolToken.supportsInterface(type(IMinimumSwapFee).interfaceId), "IMinimumSwapFee supported");
    }
}
