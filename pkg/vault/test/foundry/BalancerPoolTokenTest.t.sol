// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BalancerPoolTokenTest is BaseVaultTest {
    using ArrayHelpers for *;
    PoolMock internal poolToken;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 amount,uint256 nonce,uint256 deadline)");

    uint256 private constant CURRENT_NONCE = 0;
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
        assertEq(poolToken.name(), "ERC20 Pool");
        assertEq(poolToken.symbol(), "ERC20POOL");
        assertEq(poolToken.decimals(), 18);
    }

    function testMint() public {
        vault.mintERC20(address(poolToken), address(0xBEEF), defaultAmount);

        assertEq(poolToken.balanceOf(address(0xBEEF)), defaultAmount);
    }

    function testMintMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 1, 1e6));
        vault.mintERC20(address(pool), address(0xBEEF), 1);
    }

    function testBurn() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount - 1e6);

        assertEq(poolToken.balanceOf(address(0xBEEF)), 1e6);
    }

    function testBurnMinimum() public {
        vault.mintERC20(address(pool), address(0xBEEF), defaultAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20MultiToken.TotalSupplyTooLow.selector, 0, 1e6));
        vault.burnERC20(address(pool), address(0xBEEF), defaultAmount);
    }

    function testApprove() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        poolToken.approve(address(0xBEEF), defaultAmount);

        assertEq(poolToken.allowance(address(this), address(0xBEEF)), defaultAmount);
    }

    function testTransfer() public {
        vault.mintERC20(address(pool), address(this), defaultAmount);

        assertTrue(poolToken.transfer(address(0xBEEF), defaultAmount));
        assertEq(poolToken.totalSupply(), defaultAmount);

        assertEq(poolToken.balanceOf(address(this)), 0);
        assertEq(poolToken.balanceOf(address(0xBEEF)), defaultAmount);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(address(pool), address(from), defaultAmount);

        vm.prank(from);
        poolToken.approve(address(this), defaultAmount);

        poolToken.transferFrom(from, address(0xBEEF), defaultAmount);

        assertEq(poolToken.allowance(from, address(0xBEEF)), 0);
        assertEq(poolToken.balanceOf(address(0xBEEF)), defaultAmount);
        assertEq(poolToken.balanceOf(from), 0);
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
        poolToken.transferFrom(address(this), address(0), defaultAmount);
    }

    function testPermit() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            user,
                            address(0xCAFE),
                            defaultAmount,
                            CURRENT_NONCE,
                            block.timestamp
                        )
                    )
                )
            )
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);

        assertEq(poolToken.allowance(user, address(0xCAFE)), defaultAmount);
        assertEq(poolToken.nonces(user), CURRENT_NONCE + 1);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadNonce() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            user,
                            address(0xCAFE),
                            defaultAmount,
                            CURRENT_NONCE + 1,
                            block.timestamp
                        )
                    )
                )
            )
        );

        vm.expectRevert(bytes(""));
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadDeadline() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            user,
                            address(0xCAFE),
                            defaultAmount,
                            CURRENT_NONCE,
                            block.timestamp
                        )
                    )
                )
            )
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp + 1, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitPastDeadline() public {
        uint256 oldTimestamp = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(PERMIT_TYPEHASH, user, address(0xCAFE), defaultAmount, CURRENT_NONCE, oldTimestamp)
                    )
                )
            )
        );

        vm.warp(block.timestamp + 1);
        poolToken.permit(user, address(0xCAFE), defaultAmount, oldTimestamp, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitReplay() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            user,
                            address(0xCAFE),
                            defaultAmount,
                            CURRENT_NONCE,
                            block.timestamp
                        )
                    )
                )
            )
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
    }

    function testPermit__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.assume(privKey != 0);
        vm.assume(to != address(0));

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, CURRENT_NONCE, deadline))
                )
            )
        );

        poolToken.permit(usr, to, amount, deadline, v, r, s);

        assertEq(poolToken.allowance(usr, to), amount);
        assertEq(poolToken.nonces(usr), CURRENT_NONCE + 1);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadNonce__Fuzz(
        uint256 privKey,
        address to,
        uint256 amount,
        uint256 deadline,
        uint256 nonce
    ) public {
        deadline = bound(deadline, block.timestamp, type(uint256).max);
        vm.assume(privKey != 0);
        vm.assume(to != address(0));
        vm.assume(nonce != 0);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, nonce, deadline))
                )
            )
        );

        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitBadDeadline__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        deadline = bound(deadline, 0, block.timestamp - 1);
        vm.assume(privKey != 0);
        vm.assume(to != address(0));

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, CURRENT_NONCE, deadline))
                )
            )
        );

        poolToken.permit(usr, to, amount, deadline + 1, v, r, s);
    }

    function testPermitPastDeadline__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        vm.assume(privKey != 0);
        vm.assume(to != address(0));
        deadline = bound(deadline, 0, block.timestamp - 1);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, CURRENT_NONCE, deadline))
                )
            )
        );

        vm.expectRevert(abi.encodeWithSelector(BalancerPoolToken.ERC2612ExpiredSignature.selector, deadline));
        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }

    // @dev Just test for general fail as it is hard to compute error arguments
    function testFailPermitReplay__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        vm.assume(privKey != 0);
        vm.assume(to != address(0));
        deadline = bound(deadline, block.timestamp, type(uint256).max);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    poolToken.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, usr, to, amount, CURRENT_NONCE, deadline))
                )
            )
        );

        poolToken.permit(usr, to, amount, deadline, v, r, s);
        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }
}
