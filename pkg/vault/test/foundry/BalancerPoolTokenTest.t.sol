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
    PoolMock internal token;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 internal privateKey = 0xBEEF;
    address user = vm.addr(privateKey);

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        token = PoolMock(pool);
    }

    function initPool() internal override {
        // no init
    }

    function testMetadata() public {
        assertEq(token.name(), "ERC20 Pool");
        assertEq(token.symbol(), "ERC20POOL");
        assertEq(token.decimals(), 18);
    }

    function testMint() public {
        vault.mintERC20(address(token), address(0xBEEF), defaultAmount);

        assertEq(token.balanceOf(address(0xBEEF)), defaultAmount);
    }

    function testMintMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 1, 1e6));
        vault.mintERC20(address(pool), address(0xBEEF), 1);
    }

    function testBurn() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount - 1e6);

        assertEq(token.balanceOf(address(0xBEEF)), 1e6);
    }

    function testBurnMinimum() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 0, 1e6));
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount);
    }

    function testApprove() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        token.approve(address(0xBEEF), defaultAmount);

        assertEq(token.allowance(address(this), address(0xBEEF)), defaultAmount);
    }

    function testTransfer() public {
        vault.mintERC20(address(pool), address(this), 1e18);

        assertTrue(token.transfer(address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(address(pool), address(from), defaultAmount);

        vm.prank(from);
        token.approve(address(this), defaultAmount);

        token.transferFrom(from, address(0xBEEF), defaultAmount);

        assertEq(token.allowance(from, address(0xBEEF)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), defaultAmount);
        assertEq(token.balanceOf(from), 0);
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
        token.transferFrom(address(this), address(0), defaultAmount);
    }

    function testPermit() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, user, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        token.permit(user, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(token.allowance(user, address(0xCAFE)), 1e18);
        assertEq(token.nonces(user), 1);
    }

    function testFailPermitBadNonce() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, user, address(0xCAFE), 1e18, 1, block.timestamp))
                )
            )
        );

        token.permit(user, address(0xCAFE), 1e18, block.timestamp, v, r, s);
    }

    function testFailPermitBadDeadline() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, user, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        token.permit(user, address(0xCAFE), 1e18, block.timestamp + 1, v, r, s);
    }

    function testFailPermitPastDeadline() public {
        uint256 oldTimestamp = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, user, address(0xCAFE), 1e18, 0, oldTimestamp))
                )
            )
        );

        vm.warp(block.timestamp + 1);
        token.permit(user, address(0xCAFE), 1e18, oldTimestamp, v, r, s);
    }

    function testFailPermitReplay() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, user, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        token.permit(user, address(0xCAFE), 1e18, block.timestamp, v, r, s);
        token.permit(user, address(0xCAFE), 1e18, block.timestamp, v, r, s);
    }

    function testPermit__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        if (deadline < block.timestamp) deadline = block.timestamp;
        if (privKey == 0) privKey = 1;
        if (to == address(0)) to = address(1);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, 0, deadline))
                )
            )
        );

        token.permit(usr, to, amount, deadline, v, r, s);

        assertEq(token.allowance(usr, to), amount);
        assertEq(token.nonces(usr), 1);
    }

    function testFailPermitBadNonce__Fuzz(
        uint256 privKey,
        address to,
        uint256 amount,
        uint256 deadline,
        uint256 nonce
    ) public {
        if (deadline < block.timestamp) deadline = block.timestamp;
        if (privKey == 0) privKey = 1;
        if (nonce == 0) nonce = 1;

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, nonce, deadline))
                )
            )
        );

        token.permit(usr, to, amount, deadline, v, r, s);
    }

    function testFailPermitBadDeadline__Fuzz(uint256 privKey, address to, uint256 amount, uint256 deadline) public {
        if (deadline < block.timestamp) deadline = block.timestamp;
        if (privKey == 0) privKey = 1;

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, 0, deadline))
                )
            )
        );

        token.permit(usr, to, amount, deadline + 1, v, r, s);
    }

    function testFailPermitPastDeadline__Fuzz(uint256 privKey, address to, uint256 amount, uint256 deadline) public {
        deadline = bound(deadline, 0, block.timestamp - 1);
        if (privKey == 0) privKey = 1;

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, 0, deadline))
                )
            )
        );

        token.permit(usr, to, amount, deadline, v, r, s);
    }

    function testFailPermitReplay__Fuzz(uint256 privKey, address to, uint256 amount, uint256 deadline) public {
        if (deadline < block.timestamp) deadline = block.timestamp;
        if (privKey == 0) privKey = 1;

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, 0, deadline))
                )
            )
        );

        token.permit(usr, to, amount, deadline, v, r, s);
        token.permit(usr, to, amount, deadline, v, r, s);
    }
}
