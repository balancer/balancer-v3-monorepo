// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IEIP712 } from "permit2/src/interfaces/IEIP712.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../../contracts/BalancerPoolToken.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BalancerPoolTokenTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    PoolMock internal poolToken;

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

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

    function testMetadata() public view {
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
        uint256 burnAmount = defaultAmount - POOL_MINIMUM_TOTAL_SUPPLY;

        vault.mintERC20(pool, user, defaultAmount);

        vm.expectEmit();
        emit IERC20.Transfer(user, address(0), burnAmount);
        vault.burnERC20(pool, user, burnAmount);

        assertEq(poolToken.balanceOf(user), POOL_MINIMUM_TOTAL_SUPPLY, "balance mismatch");
    }

    function testApprove() public {
        vault.mintERC20(pool, address(this), defaultAmount);

        vm.expectEmit();
        emit IERC20.Approval(address(this), user, defaultAmount);
        assertTrue(poolToken.approve(user, defaultAmount), "approve failed");

        assertEq(poolToken.allowance(address(this), user), defaultAmount, "allowance mismatch");
    }

    function testTransfer() public {
        vault.mintERC20(pool, address(this), defaultAmount);

        vm.expectEmit();
        emit IERC20.Transfer(address(this), user, defaultAmount);
        assertTrue(poolToken.transfer(user, defaultAmount), "transfer failed");
        assertEq(poolToken.totalSupply(), defaultAmount, "total supply mismatch");

        assertEq(poolToken.balanceOf(address(this)), 0, "address(this) balance mismatch");
        assertEq(poolToken.balanceOf(user), defaultAmount, "user balance mismatch");
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC20(pool, address(from), defaultAmount);

        vm.prank(from);
        poolToken.approve(address(this), defaultAmount);

        vm.expectEmit();
        emit IERC20.Approval(from, address(this), 0);

        vm.expectEmit();
        emit IERC20.Transfer(from, user, defaultAmount);

        assertTrue(poolToken.transferFrom(from, user, defaultAmount), "transferFrom failed");

        assertEq(poolToken.allowance(from, user), 0, "allowance(from, user) isn't 0");
        assertEq(poolToken.balanceOf(user), defaultAmount, "user balance mismatch");
        assertEq(poolToken.balanceOf(from), 0, "sender balance mismatch");
    }

    function testEmitTransfer() public {
        vm.expectEmit();
        emit IERC20.Transfer(user, address(this), defaultAmount);

        vm.prank(address(vault));
        poolToken.emitTransfer(user, address(this), defaultAmount);
    }

    function testEmitApproval() public {
        vm.expectEmit();
        emit IERC20.Approval(user, address(this), defaultAmount);

        vm.prank(address(vault));
        poolToken.emitApproval(user, address(this), defaultAmount);
    }

    function testEmitTransferRevertIfCallerIsNotVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));

        poolToken.emitTransfer(user, address(this), defaultAmount);
    }

    function testEmitApprovalRevertIfCallerIsNotVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));

        poolToken.emitApproval(user, address(this), defaultAmount);
    }

    function testPermit() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
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

    function testRevokePermit() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);

        vm.prank(user);
        poolToken.incrementNonce();

        // Note that `incrementNonce` doesn't affect allowances already granted by executed permits.
        // It just invalidates signatures for permits that have not yet been executed.
        assertEq(poolToken.allowance(user, address(0xCAFE)), defaultAmount, "allowance mismatch");

        // Nonce should be incremented by 2 now.
        assertEq(poolToken.nonces(user), CURRENT_NONCE + 2, "nonce mismatch");
    }

    function testRevokePermitOperation() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);

        vm.prank(user);
        poolToken.incrementNonce();

        // Would have to pull in the OZ libraries to compute this, so just did it externally. This is the signer
        // recovered from the incremented nonce, which of course will not match the original signer.
        address externallyComputedSigner = 0xFBa42FB0E78277dE55327c8571D8c38B6bFDCD1a;

        vm.expectRevert(
            abi.encodeWithSelector(BalancerPoolToken.ERC2612InvalidSigner.selector, externallyComputedSigner, user)
        );
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
    }

    /// @dev Just test for general fail as it is hard to compute error arguments.
    function testFailPermitBadNonce() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
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

    function testPermitRevokedNonce() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);

        vm.prank(user);
        poolToken.incrementNonce();

        (uint8 v2, bytes32 r2, bytes32 s2) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE + 2,
            block.timestamp,
            privateKey
        );
        // Works with nonce + 2.
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v2, r2, s2);
    }

    function testFailPermitRevokedNonceV1() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        vm.prank(user);
        poolToken.incrementNonce();

        vm.expectRevert(bytes(""));
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
    }

    function testFailPermitRevokedNonceV2() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        vm.prank(user);
        poolToken.incrementNonce();

        (uint8 v2, bytes32 r2, bytes32 s2) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE + 2,
            block.timestamp,
            privateKey
        );
        // Works with nonce + 2.
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v2, r2, s2);

        vm.expectRevert(bytes(""));
        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp, v, r, s);
    }

    /// @dev Just test for general fail as it is hard to compute error arguments.
    function testFailPermitBadDeadline() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp + 1, v, r, s);
    }

    /// @dev Just test for general fail as it is hard to compute error arguments.
    function testFailPermitPastDeadline() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
            user,
            address(0xCAFE),
            defaultAmount,
            CURRENT_NONCE,
            block.timestamp,
            privateKey
        );

        poolToken.permit(user, address(0xCAFE), defaultAmount, block.timestamp - 1, v, r, s);
    }

    /// @dev Just test for general fail as it is hard to compute error arguments.
    function testFailPermitReplay() public {
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
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
            IEIP712(address(poolToken)),
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

    /// @dev Just test for general fail as it is hard to compute error arguments.
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
            IEIP712(address(poolToken)),
            usr,
            to,
            amount,
            nonce,
            deadline,
            privKey
        );

        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }

    /// @dev Just test for general fail as it is hard to compute error arguments.
    function testFailPermitBadDeadline__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        deadline = bound(deadline, 0, block.timestamp - 1);
        vm.assume(privKey != 0);
        vm.assume(to != address(0));

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
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
            IEIP712(address(poolToken)),
            usr,
            to,
            amount,
            CURRENT_NONCE,
            deadline,
            privKey
        );

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        poolToken.permit(usr, to, amount, deadline, v, r, s);
    }

    /// @dev Just test for general fail as it is hard to compute error arguments.
    function testFailPermitReplay__Fuzz(uint248 privKey, address to, uint256 amount, uint256 deadline) public {
        vm.assume(privKey != 0);
        vm.assume(to != address(0));
        deadline = bound(deadline, block.timestamp, MAX_UINT256);

        address usr = vm.addr(privKey);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            IEIP712(address(poolToken)),
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

    function testSupportsIERC165() public view {
        assertTrue(poolToken.supportsInterface(type(IERC165).interfaceId), "IERC165 not supported");
    }

    function testGetVault() public view {
        assertEq(address(poolToken.getVault()), address(vault), "Vault is wrong");
    }

    function testGetRatePoolNotInitialized() public {
        // Since poolToken is not initialized, getRate should revert.
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, poolToken));
        poolToken.getRate();
    }

    function testGetRate() public {
        // Init pool, so it has a BPT supply and rate can be calculated.
        vm.startPrank(lp);
        IERC20[] memory tokens = vault.getPoolTokens(address(poolToken));
        router.initialize(
            address(poolToken),
            tokens,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );
        vm.stopPrank();

        uint256[] memory liveBalancesScaled18 = vault.getCurrentLiveBalances(address(poolToken));
        uint256 invariant = IBasePool(address(poolToken)).computeInvariant(liveBalancesScaled18, Rounding.ROUND_DOWN);
        uint256 bptRate = invariant.divDown(poolToken.totalSupply());

        assertEq(poolToken.getRate(), bptRate, "BPT rate is wrong");
        assertEq(bptRate, FixedPoint.ONE, "BPT rate is not 1");
    }

    function testOverrideRate() public {
        uint256 mockRate = 51.567e16;

        poolToken.setMockRate(mockRate);

        assertEq(poolToken.getRate(), mockRate, "Wrong overridden mock rate");
    }
}
