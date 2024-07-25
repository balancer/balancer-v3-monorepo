// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenInfo } from "../vault/VaultTypes.sol";

/**
 * @notice Convenience interface for pools, to get easy access to information stored in the Vault.
 * Intended mostly for off-chain requests; pools do not need to implement this to work properly.
 */
interface IPoolInfo {
    /**
     * @notice Gets the tokens registered in the pool.
     * @return tokens List of tokens in the pool, sorted in registration order
     */
    function getTokens() external view returns (IERC20[] memory tokens);

    /**
     * @notice Gets the raw data for the pool: tokens, token info, raw balances, last live balances.
     * @return tokens The pool tokens, sorted in registration order
     * @return tokenInfo Corresponding token info (type, rate provider, yield flag)
     * @return balancesRaw Corresponding raw balances of the tokens
     * @return lastLiveBalances Corresponding last live balances from the previous operation
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
     * @notice Gets the current live balances of the pool, as fixed point, 18-decimal numbers.
     * @return balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
     */
    function getCurrentLiveBalances() external view returns (uint256[] memory balancesLiveScaled18);

    /**
     * @notice Gets the static swap fee percentage for the pool.
     * @return staticSwapFeePercentage The current static swap fee percentage for the pool
     */
    function getStaticSwapFeePercentage() external view returns (uint256 staticSwapFeePercentage);

    /**
     * @notice Gets the aggregate swap and yield fee percentages for a pool.
     * @dev These are determined by the current protocol and pool creator fees, set in the `ProtocolFeeController`.
     * @return aggregateSwapFeePercentage The aggregate percentage fee applied to swaps
     * @return aggregateYieldFeePercentage The aggregate percentage fee applied to yield
     */
    function getAggregateFeePercentages()
        external
        view
        returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage);
}
