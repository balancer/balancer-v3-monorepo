// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
 * @notice Interface for a ERC20MultiToken
 */
interface IERC20MultiToken {
    /**
     * @notice Gets total supply of a given ERC20 token
     * @param token                          Token's address
     * @return                               Total supply of the token
     */
    function totalSupply(address token) external view returns (uint256);

    /**
     * @notice Gets balance of an account for a given ERC20 token
     * @param token                          Token's address
     * @param account                        Account's address
     * @return                               Balance of the account for the token
     */
    function balanceOf(address token, address account) external view returns (uint256);

    /**
     * @notice Transfers ERC20 token from owner to a recipient
     * @param token                          Token's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transfer(
        address token,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Transfers ERC20 token from owner to a recipient
     * @param owner                          Owner's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transferWith(
        address owner,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Transfers from a sender to a recipient using an allowance
     * @param token                          Token's address
     * @param from                           Sender's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Transfers from a sender to a recipient using an allowance
     * @param spender                        Address allowed to perform the transfer
     * @param from                           Sender's address
     * @param to                             Recipient's address
     * @param amount                         Amount of tokens to transfer
     * @return                               True if successful, false otherwise
     */
    function transferFromWith(
        address spender,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Gets allowance of a spender for a given ERC20 token and owner
     * @param token                          Token's address
     * @param owner                          Owner's address
     * @param spender                        Spender's address
     * @return                               Amount of tokens the spender is allowed to spend
     */
    function allowance(
        address token,
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @notice Approves a spender to spend tokens on behalf of sender
     * @param owner                          Owner's address
     * @param spender                        Spender's address
     * @param amount                         Amount of tokens to approve
     * @return                               True if successful, false otherwise
     */
    function approveWith(
        address owner,
        address spender,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Approves a spender to spend tokens on behalf of sender
     * @param token                          Token's address
     * @param spender                        Spender's address
     * @param amount                         Amount of tokens to approve
     * @return                               True if successful, false otherwise
     */
    function approve(
        address token,
        address spender,
        uint256 amount
    ) external returns (bool);
}
