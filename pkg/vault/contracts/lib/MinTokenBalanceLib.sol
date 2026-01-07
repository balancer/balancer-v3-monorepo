// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

library MinTokenBalanceLib {
    // Matches the POOL_MINIMUM_TOTAL_SUPPLY Vault constant in `ERC20MultiToken`.
    uint256 public constant ABSOLUTE_MIN_TOKEN_BALANCE = 1e6;

    /**
     * @notice A minimum token balance is less than the absolute minimum defined above.
     * @dev This can only happen if a pool is deployed outside the factory.
     */
    error InvalidMinTokenBalance();

    /**
     * @notice An operation has caused a token balance to drop below the minimum allowed balance.
     * @param tokenIndex Index of the token; we don't always have easy access to the token address
     * @param actualBalance The balance the pool is rejecting
     * @param minBalance The minimum balance allowed for this token
     */
    error TokenBalanceBelowMin(uint256 tokenIndex, uint256 actualBalance, uint256 minBalance);

    /**
     * @notice Calculate the minimum balance for a token, given its decimals and the pool size.
     * @dev The intuition here is that the minimum total supply represents the minimum value of all the pool tokens, so
     * if all tokens were 18 decimals, the minimum balance for each token would simply be the absolute minimum.
     * However, token decimals are also relevant, since it doesn't make sense to have a limit below what the native
     * token decimals can represent.
     *
     * @param tokens The pool tokens (as a TokenConfig array, for convenience)
     * @return minTokenBalances The validated minimum balances
     */
    function computeMinTokenBalances(
        TokenConfig[] memory tokens
    ) internal view returns (uint256[] memory minTokenBalances) {
        uint256 numTokens = tokens.length;

        minTokenBalances = new uint256[](numTokens);

        // Compute the default minimum balance, as a scaled18 value.
        // If defined conceptually as an "equal share" of the value, we should technically divide the minimum supply
        // by the number of tokens. However, it is simpler to use a single minimum for all pool sizes, and provides an
        // extra safety margin.
        uint256 defaultMinTokenBalance = ABSOLUTE_MIN_TOKEN_BALANCE;

        // Adjust minimums for token decimals.
        for (uint256 i = 0; i < numTokens; ++i) {
            address token = address(tokens[i].token);
            uint256 tokenDecimals = IERC20Metadata(token).decimals();

            // Number of wei corresponding to 1 unit at the given decimal value (e.g., 18-decimals = 1 wei).
            // It doesn't make sense to have a minimum lower than this, as it would be truncated during downscaling.
            uint256 atomicUnitFloor = 10 ** (18 - tokenDecimals);

            // Note that the atomic unit floor only matters for tokens with 12 decimals or fewer:
            // - Atomic unit > 1e6 when: 10^(18-d) > 1e6; or d < 12
            // - Therefore, for d >= 12, the default minimum (1e6) is always sufficient
            //
            // Could optimize this (i.e., only compute for <= 12 decimals), but this only happens on deployment.

            // Compute the decimal-adjusted minimum token balance.
            minTokenBalances[i] = Math.max(defaultMinTokenBalance, atomicUnitFloor);
        }
    }
}
