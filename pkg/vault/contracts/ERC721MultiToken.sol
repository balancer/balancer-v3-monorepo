// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { IERC721Errors } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/tokens/IERC721Errors.sol";

import { ERC721BalancerPoolToken } from "./ERC721BalancerPoolToken.sol";

/**
 * @notice Store Balancer Pool Token (BPT) ERC721 data and handle accounting for all Pools in the Vault.
 * @dev The Vault manages all BPT (Balancer Pool Tokens), which can be either ERC20 or ERC721, in a manner similar to
 * ERC-1155, but without fully supporting the standard. Parts of it conflict with the Vault's security model and
 * design philosophy; the purpose is to encapsulate all accounting (of both pool constituent tokens and the pool
 * contracts themselves) in the Vault, rather than dividing responsibilities between the Vault and pool contracts.
 */
abstract contract ERC721MultiToken is IERC721Errors {
    // Mapping from token ID to owner address
    mapping(address => mapping(uint256 => address)) private _owners;

    // Mapping from owner address to token count
    mapping(address => mapping(address => uint256)) private _bptBalances;

    // Mapping from token ID to approved address
    mapping(address => mapping(uint256 => address)) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => mapping(address => bool))) private _operatorApprovals;

    /// @dev See {IERC721-balanceOf}.
    function _balanceOfERC721(address token, address owner) internal view returns (uint256) {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(address(0));
        }
        return _balances[token][owner];
    }

    /// @dev See {IERC721-ownerOf}.
    function _safeOwnerOfERC721(address token, uint256 tokenId) internal view returns (address) {
        address owner = _ownerOfERC721(token, tokenId);
        if (owner == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        return owner;
    }

    /// @dev See {IERC721-getApproved}.
    function _getApprovedERC721(address token, uint256 tokenId) internal view returns (address) {
        _requireMinted(token, tokenId);

        return _tokenApprovals[token][tokenId];
    }

    /// @dev See {IERC721-isApprovedForAll}.
    function _isApprovedForAllERC721(address token, address owner, address operator) internal view returns (bool) {
        return _operatorApprovals[token][owner][operator];
    }

    /// @dev See {IERC721-approve}.
    function _approveERC721(address token, address sender, address to, uint256 tokenId) internal {
        address owner = _safeOwnerOfERC721(token, tokenId);
        if (to == owner) {
            revert ERC721InvalidOperator(owner);
        }

        if (sender != owner && !_isApprovedForAllERC721(token, owner, sender)) {
            revert ERC721InvalidApprover(sender);
        }

        _approve(token, to, tokenId);
    }

    /// @dev See {IERC721-setApprovalForAll}.
    function _setApprovalForAllERC721(address token, address sender, address operator, bool approved) internal {
        _setApprovalForAll(token, sender, operator, approved);
    }

    /// @dev See {IERC721-transferFrom}.
    function _transferFromERC721(address token, address sender, address from, address to, uint256 tokenId) internal {
        if (!_isApprovedOrOwnerERC721(token, sender, tokenId)) {
            revert ERC721InsufficientApproval(sender, tokenId);
        }

        _transferERC721(token, from, to, tokenId);
    }

    /// @dev See {IERC721-safeTransferFrom}.
    function _safeTransferFromERC721(
        address token,
        address sender,
        address from,
        address to,
        uint256 tokenId
    ) internal {
        _safeTransferFromERC721(token, sender, from, to, tokenId, "");
    }

    /// @dev See {IERC721-safeTransferFrom}.
    function _safeTransferFromERC721(
        address token,
        address sender,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal {
        if (!_isApprovedOrOwnerERC721(token, sender, tokenId)) {
            revert ERC721InsufficientApproval(sender, tokenId);
        }
        _safeTransferERC721(token, sender, from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received},
     * which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransferERC721(
        address token,
        address sender,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private {
        _transferERC721(token, from, to, tokenId);
        if (!_checkOnERC721Received(sender, from, to, tokenId, data)) {
            revert ERC721InvalidReceiver(to);
        }
    }

    /// @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
    function _ownerOfERC721(address token, uint256 tokenId) private view returns (address) {
        return _owners[token][tokenId];
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _existsERC721(address token, uint256 tokenId) private view returns (bool) {
        return _ownerOfERC721(token, tokenId) != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwnerERC721(address token, address spender, uint256 tokenId) private view returns (bool) {
        address owner = _ownerOfERC721(token, tokenId);
        return (spender == owner ||
            _isApprovedForAllERC721(token, owner, spender) ||
            _getApprovedERC721(token, tokenId) == spender);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received},
     * which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMintERC721(address token, address sender, address to, uint256 tokenId) internal {
        _safeMintERC721(token, sender, to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMintERC721(address token, address sender, address to, uint256 tokenId, bytes memory data) internal {
        _mintERC721(token, to, tokenId);
        if (!_checkOnERC721Received(sender, address(0), to, tokenId, data)) {
            revert ERC721InvalidReceiver(to);
        }
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mintERC721(address token, address to, uint256 tokenId) internal {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        if (_existsERC721(token, tokenId)) {
            revert ERC721InvalidSender(address(0));
        }

        unchecked {
            // Will not overflow unless all 2**256 token ids are minted to the same owner.
            // Given that tokens are minted one by one, it is impossible in practice that
            // this ever happens. Might change if we allow batch minting.
            // The ERC fails to describe this case.
            _balances[token][to] += 1;
        }

        _owners[token][tokenId] = to;

        // Emit Transfer event on the token
        ERC721BalancerPoolToken(token).emitTransfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     * This is an internal function that does not check if the sender is authorized to operate on the token.
     *
     * Requirements:
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burnERC721(address token, uint256 tokenId) internal {
        address owner = _safeOwnerOfERC721(token, tokenId);

        // Clear approvals
        delete _tokenApprovals[token][tokenId];

        // Decrease balance with checked arithmetic, because an `ownerOf` override may
        // invalidate the assumption that `_balances[from] >= 1`.
        _balances[token][owner] -= 1;

        delete _owners[token][tokenId];

        // Emit Transfer event on the token
        ERC721BalancerPoolToken(token).emitTransfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transferERC721(address token, address from, address to, uint256 tokenId) private {
        address owner = _safeOwnerOfERC721(token, tokenId);
        if (owner != from) {
            revert ERC721IncorrectOwner(from, tokenId, owner);
        }
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }

        // Clear approvals from the previous owner
        delete _tokenApprovals[token][tokenId];

        // Decrease balance with checked arithmetic, because an `ownerOf` override may
        // invalidate the assumption that `_balances[from] >= 1`.
        _balances[token][from] -= 1;

        unchecked {
            // `_balances[to]` could overflow in the conditions described in `_mint`. That would require
            // all 2**256 token ids to be minted, which in practice is impossible.
            _balances[token][to] += 1;
        }

        _owners[token][tokenId] = to;

        // Emit Transfer event on the token
        ERC721BalancerPoolToken(token).emitTransfer(address(0), to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address token, address to, uint256 tokenId) private {
        _tokenApprovals[token][tokenId] = to;
        // Emit Approval event on the token
        ERC721BalancerPoolToken(token).emitApproval(_ownerOfERC721(token, tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     */
    function _setApprovalForAll(address token, address owner, address operator, bool approved) private {
        if (owner == operator) {
            revert ERC721InvalidOperator(owner);
        }
        _operatorApprovals[token][owner][operator] = approved;
        // Emit ApprovalForAll event on the token
        ERC721BalancerPoolToken(token).emitApprovalForAll(owner, operator, approved);
    }

    /// @dev Reverts if the `tokenId` has not been minted yet.
    function _requireMinted(address token, uint256 tokenId) private view {
        if (!_existsERC721(token, tokenId)) {
            revert ERC721NonexistentToken(tokenId);
        }
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address sender,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(sender, from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert ERC721InvalidReceiver(to);
                } else {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}
