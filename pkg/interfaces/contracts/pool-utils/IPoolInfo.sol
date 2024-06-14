// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../vault/VaultTypes.sol";

/**
 * @notice Convenience interface for pools, to get easy access to information stored in the Vault.
 * Intended mostly for offchain requests; pools do not need to implement this to work properly.
 */
interface IPoolInfo {
    /**
     * @notice Gets the tokens registered in the pool.
     * @return tokens List of tokens in the pool in registration order
     */
    function getTokens() external view returns (IERC20[] memory tokens);

    /**
     * @notice Gets the raw data for the pool: tokens, token info, raw balances, last live balances.
     * @return tokens The pool tokens, in registration order
     * @return tokenInfo Corresponding token info
     * @return balancesRaw Corresponding raw balances of the tokens
     * @return lastLiveBalances Corresponding last live balances from the previous operation of the tokens
     */
    function getTokenInfo()
        external
        view
        returns (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastLiveBalances
        );

    /**
     * @notice Gets current live balances of the pool (fixed-point, 18 decimals).
     * @dev Live balances
     * @return balancesLiveScaled18 Live token balances after applying decimal scaling factors, token rates and yield
     * fees due.
     */
    function getCurrentLiveBalances() external view returns (uint256[] memory balancesLiveScaled18);

    /// @notice Fetches the static swap fee percentage for the pool.
    function getStaticSwapFeePercentage() external view returns (uint256);
}
