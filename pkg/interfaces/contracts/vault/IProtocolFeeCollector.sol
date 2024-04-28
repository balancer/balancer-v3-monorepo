// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";
import { IAuthorizer } from "./IAuthorizer.sol";

interface IProtocolFeeCollector {
    /// @dev Emmitted when a token is removed from the deny list.
    event TokenAllowlisted(IERC20 token);

    /// @dev Emitted when a token is added to the deny list.
    event TokenDenylisted(IERC20 token);

    /// @dev Cannot call allowlistToken on a token that is not on the deny list.
    error TokenNotOnDenyList(IERC20 token);

    /**
     * @notice Logs the collection of fees in a specific token and amount.
     * @param token The token in which the fee has been collected
     * @param amount The amount of the token collected as fees
     * @param recipient The address where funds were sent
     */
    event ProtocolFeeWithdrawn(IERC20 indexed token, uint256 indexed amount, address indexed recipient);

    /**
     * @dev Revert when trying to collect fees on a denylistToken, or trying to add a token to the deny list
     * when it is already there.
     */
    error TokenOnDenyList(IERC20 token);

    /**
     * @notice Get the associated Vault address.
     * @return vault The Vault address
     */
    function vault() external view returns (IVault);

    /**
     * @notice Get the authorizer used for authentication on permissioned calls.
     * @return authorizer The authorizer
     */
    function getAuthorizer() external view returns (IAuthorizer);

    /**
     * @notice Returns whether the provided token may be withdrawn from the Protocol Fee Collector
     * @param token The token to be withdrawn
     * @param success True if the token can be withdrawn (i.e., it's not on th deny list)
     */
    function isWithdrawableToken(IERC20 token) external view returns (bool success);

    /**
     * @notice Returns whether the provided array of tokens may be withdrawn from the Protocol Fee Collector
     * @param tokens Set of tokens to check withdrawal status
     * @param success True if all tokens can be withdrawn; false if any are on the deny list
     */
    function isWithdrawableTokens(IERC20[] calldata tokens) external view returns (bool success);

    /**
     * @notice Returns the denylisted token at the given `index`.
     * @dev In case there so many tokens on the deny list that iterating over the list would run out of gas,
     * allow fetching in an external loop, using the length and this getter.
     *
     * @param index The 0-based index of a token on the deny list
     * @param token The token on the deny list
     */
    function getDenylistedToken(uint256 index) external view returns (IERC20 token);

    /**
     * @notice Returns the number of denylisted tokens.
     * @return length Length of the deny list
     */
    function getDenylistedTokensLength() external view returns (uint256 length);

    /**
     * @notice Returns the collected fee amount of each token on the list (i.e., held by this contract).
     * @dev Note that this does not check the deny list, as we are not withdrawing anything, so it can be used to check
     * balances of tokens on the deny list.
     *
     * @param tokens The list of tokens fees have been collected on
     * @param feeAmounts The amount that can be withdrawn ()
     */
    function getCollectedFeeAmounts(IERC20[] memory tokens) external view returns (uint256[] memory feeAmounts);

    /**
     * @notice Withdraw collected protocol fees for a set of tokens, to the given recipient address.
     * @param tokens List of tokens to withdraw
     * @param recipient Recipient address for the withdrawn protocol fees
     */
    function withdrawCollectedFees(IERC20[] calldata tokens, address recipient) external;

    /**
     * @notice Marks the provided token as ineligible for withdrawal from the Protocol Fee Collector.
     * @dev Reverts if it is already on the list.
     * @param token The token to add to the deny list
     */
    function denylistToken(IERC20 token) external;

    /// 
    /**
     * @notice Marks the provided token as eligible for withdrawal from the Protocol Fee Collector
     * @dev Removes the token from the deny list (reverts if it was not on the list).
     */
    function allowlistToken(IERC20 token) external;
}
