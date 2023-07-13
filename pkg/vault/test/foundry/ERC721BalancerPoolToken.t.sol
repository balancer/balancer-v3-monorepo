// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IERC721Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC721Errors.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { ERC721BalancerPoolToken } from "../../contracts/ERC721BalancerPoolToken.sol";
import { ERC721PoolMock } from "../../contracts/test/ERC721PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

// Adopted form https://github.com/transmissions11/solmate/blob/main/src/test/ERC721.t.sol
contract ERC721Recipient is IERC721Receiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _id,
        bytes calldata _data
    ) public virtual override returns (bytes4) {
        operator = _operator;
        from = _from;
        id = _id;
        data = _data;

        return IERC721Receiver.onERC721Received.selector;
    }
}

contract RevertingERC721Recipient is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) public virtual override returns (bytes4) {
        revert(string(abi.encodePacked(IERC721Receiver.onERC721Received.selector)));
    }
}

contract WrongReturnDataERC721Recipient is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) public virtual override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract NonERC721Recipient {}

contract ERC721BalancerPoolTokenTest is Test {
    using AssetHelpers for address[];
    using ArrayHelpers for address[2];

    VaultMock vault;
    ERC721PoolMock token;

    function setUp() public {
        vault = new VaultMock(IWETH(address(0)), 30 days, 90 days);
        token = new ERC721PoolMock(
            vault,
            address(0),
            [address(0x1), address(0x2)].toMemoryArray().asIERC20(),
            "Pool",
            "POOL",
            true
        );
    }

    function testSupportsInterface() external {
        // ERC165
        assertEq(token.supportsInterface(0x01ffc9a7), true);
        // ERC721
        assertEq(token.supportsInterface(0x80ac58cd), true);
        // ERC721Metadata
        assertEq(token.supportsInterface(0x5b5e139f), true);
    }

    function testMetadata() public {
        assertEq(token.name(), "Pool");
        assertEq(token.symbol(), "POOL");
    }

    function testTokenURI() public {
        vault.mintERC721(address(token), address(0xBEEF), 1337);
        assertEq(token.tokenURI(1337), "");
    }

    function testMint() public {
        vault.mintERC721(address(token), address(0xBEEF), 1337);

        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.ownerOf(1337), address(0xBEEF));
    }

    function testBurn() public {
        vault.mintERC721(address(token), address(0xBEEF), 1337);
        vault.burnERC721(address(token), 1337);

        assertEq(token.balanceOf(address(0xBEEF)), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        token.ownerOf(1337);
    }

    function testApprove() public {
        vault.mintERC721(address(token), address(this), 1337);

        token.approve(address(0xBEEF), 1337);

        assertEq(token.getApproved(1337), address(0xBEEF));
    }

    function testApproveBurn() public {
        vault.mintERC721(address(token), address(this), 1337);

        token.approve(address(0xBEEF), 1337);

        vault.burnERC721(address(token), 1337);

        assertEq(token.balanceOf(address(this)), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        assertEq(token.getApproved(1337), address(0));

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        token.ownerOf(1337);
    }

    function testApproveAllInvalidOperator() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(this)));
        token.setApprovalForAll(address(this), true);
    }

    function testApproveAll() public {
        token.setApprovalForAll(address(0xBEEF), true);

        assertTrue(token.isApprovedForAll(address(this), address(0xBEEF)));
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        vault.mintERC721(address(token), address(from), 1337);

        vm.prank(from);
        token.approve(address(this), 1337);

        token.transferFrom(from, address(0xBEEF), 1337);

        assertEq(token.getApproved(1337), address(0));
        assertEq(token.ownerOf(1337), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testTransferFromSelf() public {
        vault.mintERC721(address(token), address(this), 1337);

        token.transferFrom(address(this), address(0xBEEF), 1337);

        assertEq(token.getApproved(1337), address(0));
        assertEq(token.ownerOf(1337), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function testTransferFromApproveAll() public {
        address from = address(0xABCD);

        vault.mintERC721(address(token), address(from), 1337);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.transferFrom(from, address(0xBEEF), 1337);

        assertEq(token.getApproved(1337), address(0));
        assertEq(token.ownerOf(1337), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testSafeTransferFromToEOA() public {
        address from = address(0xABCD);

        vault.mintERC721(address(token), address(from), 1337);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(0xBEEF), 1337);

        assertEq(token.getApproved(1337), address(0));
        assertEq(token.ownerOf(1337), address(0xBEEF));
        assertEq(token.balanceOf(address(0xBEEF)), 1);
        assertEq(token.balanceOf(from), 0);
    }

    function testSafeTransferFromToERC721Recipient() public {
        address from = address(0xABCD);
        ERC721Recipient recipient = new ERC721Recipient();

        vault.mintERC721(address(token), address(from), 1337);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(recipient), 1337);

        assertEq(token.getApproved(1337), address(0));
        assertEq(token.ownerOf(1337), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(from), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1337);
        assertEq(recipient.data(), "");
    }

    function testSafeTransferFromToERC721RecipientWithData() public {
        address from = address(0xABCD);
        ERC721Recipient recipient = new ERC721Recipient();

        vault.mintERC721(address(token), address(from), 1337);

        vm.prank(from);
        token.setApprovalForAll(address(this), true);

        token.safeTransferFrom(from, address(recipient), 1337, "testing 123");

        assertEq(token.getApproved(1337), address(0));
        assertEq(token.ownerOf(1337), address(recipient));
        assertEq(token.balanceOf(address(recipient)), 1);
        assertEq(token.balanceOf(from), 0);

        assertEq(recipient.operator(), address(this));
        assertEq(recipient.from(), from);
        assertEq(recipient.id(), 1337);
        assertEq(recipient.data(), "testing 123");
    }

    function testSafeMintToEOA() public {
        vault.safeMintERC721(address(token), address(0xBEEF), 1337);

        assertEq(token.ownerOf(1337), address(address(0xBEEF)));
        assertEq(token.balanceOf(address(address(0xBEEF))), 1);
    }

    function testSafeMintToERC721Recipient() public {
        ERC721Recipient to = new ERC721Recipient();

        vault.safeMintERC721(address(token), address(to), 1337);

        assertEq(token.ownerOf(1337), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1337);
        assertEq(to.data(), "");
    }

    function testSafeMintToERC721RecipientWithData() public {
        ERC721Recipient to = new ERC721Recipient();

        vault.safeMintERC721(address(token), address(to), 1337, "testing 123");

        assertEq(token.ownerOf(1337), address(to));
        assertEq(token.balanceOf(address(to)), 1);

        assertEq(to.operator(), address(this));
        assertEq(to.from(), address(0));
        assertEq(to.id(), 1337);
        assertEq(to.data(), "testing 123");
    }

    function testMintToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, 0));
        vault.mintERC721(address(token), address(0), 1337);
    }

    function testDoubleMint() public {
        vault.mintERC721(address(token), address(0xBEEF), 1337);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidSender.selector, 0));
        vault.mintERC721(address(token), address(0xBEEF), 1337);
    }

    function testBurnUnMinted() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        vault.burnERC721(address(token), 1337);
    }

    function testDoubleBurn() public {
        vault.mintERC721(address(token), address(0xBEEF), 1337);

        vault.burnERC721(address(token), 1337);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        vault.burnERC721(address(token), 1337);
    }

    function testApproveToOwner() public {
        vault.mintERC721(address(token), address(0xBEEF), 1337);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOperator.selector, address(0xBEEF)));
        token.approve(address(0xBEEF), 1337);
    }

    function testApproveUnMinted() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        token.approve(address(0xBEEF), 1337);
    }

    function testApproveUnAuthorized() public {
        vault.mintERC721(address(token), address(0xCAFE), 1337);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidApprover.selector, address(this)));
        token.approve(address(0xBEEF), 1337);
    }

    function testTransferFromToIncorrectOwner() public {
        vault.mintERC721(address(token), address(this), 1337);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, address(0xCAFE), 1337, address(this))
        );
        token.transferFrom(address(0xCAFE), address(0xBEEF), 1337);
    }

    function testTransferFromUnOwned() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        token.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function testTransferFromWrongFrom() public {
        vault.mintERC721(address(token), address(0xCAFE), 1337);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), 1337));
        token.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function testTransferFromToZero() public {
        vault.mintERC721(address(token), address(this), 1337);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, 0));
        token.transferFrom(address(this), address(0), 1337);
    }

    function testTransferFromNotOwner() public {
        vault.mintERC721(address(token), address(0xFEED), 1337);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), 1337));
        token.transferFrom(address(0xFEED), address(0xBEEF), 1337);
    }

    function testSafeTransferFromNoApproval() public {
        vault.mintERC721(address(token), address(0xBEEF), 1337);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), 1337));
        token.safeTransferFrom(address(this), address(0xCAFE), 1337);
    }

    function testSafeTransferFromToNonERC721Recipient() public {
        vault.mintERC721(address(token), address(this), 1337);

        address recipient = address(new NonERC721Recipient());
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        token.safeTransferFrom(address(this), recipient, 1337);
    }

    function testSafeTransferFromToNonERC721RecipientWithData() public {
        vault.mintERC721(address(token), address(this), 1337);

        address recipient = address(new NonERC721Recipient());
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        token.safeTransferFrom(address(this), recipient, 1337, "testing 123");
    }

    function testSafeTransferFromToRevertingERC721Recipient() public {
        vault.mintERC721(address(token), address(this), 1337);

        RevertingERC721Recipient recipient = new RevertingERC721Recipient();
        vm.expectRevert(abi.encodePacked(IERC721Receiver.onERC721Received.selector));
        token.safeTransferFrom(address(this), address(recipient), 1337);
    }

    function testSafeTransferFromToRevertingERC721RecipientWithData() public {
        vault.mintERC721(address(token), address(this), 1337);

        RevertingERC721Recipient recipient = new RevertingERC721Recipient();
        vm.expectRevert(abi.encodePacked(IERC721Receiver.onERC721Received.selector));
        token.safeTransferFrom(address(this), address(recipient), 1337, "testing 123");
    }

    function testSafeTransferFromToERC721RecipientWithWrongReturnData() public {
        vault.mintERC721(address(token), address(this), 1337);

        address recipient = address(new WrongReturnDataERC721Recipient());
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        token.safeTransferFrom(address(this), recipient, 1337);
    }

    function testSafeTransferFromToERC721RecipientWithWrongReturnDataWithData() public {
        vault.mintERC721(address(token), address(this), 1337);

        address recipient = address(new WrongReturnDataERC721Recipient());
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        token.safeTransferFrom(address(this), recipient, 1337, "testing 123");
    }

    function testSafeMintToNonERC721Recipient() public {
        address recipient = address(new NonERC721Recipient());
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        vault.safeMintERC721(address(token), address(recipient), 1337);
    }

    function testSafeMintToNonERC721RecipientWithData() public {
        address recipient = address(new NonERC721Recipient());
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        vault.safeMintERC721(address(token), address(recipient), 1337, "testing 123");
    }

    function testSafeMintToRevertingERC721Recipient() public {
        RevertingERC721Recipient recipient = new RevertingERC721Recipient();
        vm.expectRevert(abi.encodePacked(IERC721Receiver.onERC721Received.selector));
        vault.safeMintERC721(address(token), address(recipient), 1337);
    }

    function testSafeMintToRevertingERC721RecipientWithData() public {
        RevertingERC721Recipient recipient = new RevertingERC721Recipient();
        vm.expectRevert(abi.encodePacked(IERC721Receiver.onERC721Received.selector));
        vault.safeMintERC721(address(token), address(recipient), 1337, "testing 123");
    }

    function testSafeMintToERC721RecipientWithWrongReturnData() public {
        WrongReturnDataERC721Recipient recipient = new WrongReturnDataERC721Recipient();
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        vault.safeMintERC721(address(token), address(recipient), 1337);
    }

    function testSafeMintToERC721RecipientWithWrongReturnDataWithData() public {
        WrongReturnDataERC721Recipient recipient = new WrongReturnDataERC721Recipient();
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, recipient));
        vault.safeMintERC721(address(token), address(recipient), 1337, "testing 123");
    }

    function testBalanceOfZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidOwner.selector, 0));
        token.balanceOf(address(0));
    }

    function testOwnerOfUnminted() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1337));
        token.ownerOf(1337);
    }
}
