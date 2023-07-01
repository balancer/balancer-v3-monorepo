// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
 * @notice Custom errors for ERC20 tokens.
 * @dev See [EIP-6093](https://eips.ethereum.org/EIPS/eip-6093).
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can’t be an owner. Used in balance queries.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a tokenId whose owner is the zero address.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token sender. Used in transfers.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token receiver. Used in transfers.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the operator’s approval. Used in transfers.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the owner of a token to be approved. Used in approvals.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the operator to be approved. Used in approvals.
     */
    error ERC721InvalidOperator(address operator);
}
