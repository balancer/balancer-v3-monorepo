// SPDX-License-Identifier: GPL-3.0-or-laterk

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IERC721Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC721Errors.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

/**
 * @notice Base contract for all ERC721 Balancer pools. Often abbreviated as "BPT" = Balancer Pool Token.
 * @dev The ERC721BalancerPoolToken is fully compliant with the ERC721 API. However, all the accounting
 * is delegated to the Vault, allowing the Vault to mint and burn ERC721 tokens.
 */
contract ERC721BalancerPoolToken is IERC721, IERC721Metadata, ERC165, IVaultErrors {
    using Strings for uint256;

    IVault private immutable _vault;
    string private _name;
    string private _symbol;

    modifier onlyVault() {
        if (msg.sender != address(_vault)) {
            revert SenderIsNotVault(msg.sender);
        }
        _;
    }

    constructor(IVault vault_, string memory name_, string memory symbol_) {
        _vault = vault_;
        _name = name_;
        _symbol = symbol_;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC721Metadata
    function name() public view returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC721Metadata
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC721Metadata
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        // checking that tokenId has an owner
        _vault.ownerOfERC721(address(this), tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toString()) : "";
    }

    /// @inheritdoc IERC721
    function balanceOf(address owner) public view virtual returns (uint256) {
        return _vault.balanceOfERC721(address(this), owner);
    }

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return _vault.ownerOfERC721(address(this), tokenId);
    }

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) public virtual {
        _vault.approveERC721(msg.sender, to, tokenId);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId) public view virtual returns (address) {
        return _vault.getApprovedERC721(address(this), tokenId);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) public virtual {
        _vault.setApprovalForAllERC721(msg.sender, operator, approved);
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _vault.isApprovedForAllERC721(address(this), owner, operator);
    }

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        _vault.transferFromERC721(msg.sender, from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        _vault.safeTransferFromERC721(msg.sender, from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        _vault.safeTransferFromERC721(msg.sender, from, to, tokenId, data);
    }

    /// Accounting is centralized in the Vault MultiToken contract, and the actual transfers and approvals
    /// are done there. Operations can be initiated from either the token contract or the Vault.
    ///
    /// To maintain compliance with the ERC-721 standard, and conform to the expections of off-chain processes,
    /// the Vault calls `emitTransfer` and `emitApprove` during those operations, so that the event is emitted
    /// only from the token contract. These events are NOT defined in the Vault contract.

    /**
     * @dev The Transfer event is emitted. This function can only be called by the Vault.
     * The Vault is invoking this function to ensure that the ERC721BalancerPoolToken is compliant with the ERC721 API.
     */
    function emitTransfer(address from, address to, uint256 amount) external onlyVault {
        emit Transfer(from, to, amount);
    }

    /**
     * @dev The ApprovalForAll event is emitted. This function can only be called by the Vault.
     * The Vault is invoking this function to ensure that the ERC721BalancerPoolToken is compliant with the ERC721 API.
     */
    function emitApprovalForAll(address owner, address operator, bool approved) external onlyVault {
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev The Approval event is emitted. This function can only be called by the Vault.
     * The Vault is invoking this function to ensure that the ERC721BalancerPoolToken is compliant with the ERC721 API.
     */
    function emitApproval(address owner, address spender, uint256 amount) external onlyVault {
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }
}
