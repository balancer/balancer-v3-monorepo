// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

library MinTokenBalanceLib {
    // Matches the corresponding Vault constant in `ERC20MultiToken`.
    uint256 public constant POOL_MINIMUM_TOTAL_SUPPLY = 1e6;

    /**
     * @notice A pool was created with an invalid minimum token balance.
     * @param token Address of the token with the invalid minimum balance
     * @param givenMinimum The minimum token balance that was supplied
     * @param absoluteMinimum The minimum token balance allowed by the system
     */
    error InvalidMinTokenBalance(address token, uint256 givenMinimum, uint256 absoluteMinimum);

    /**
     * @notice Calculate the minimum balance for a token, given its decimals and the pool size.
     * @dev The intuition here is that the minimum total supply represents the minimum value of all the pool tokens, so
     * if all tokens were 18 decimals, the minimum balance for each token would simply be the max / n. However, token
     * decimals are also relevant, since it doesn't make sense to have a limit below what the native token decimals
     * can represent.
     *
     * @param tokens The pool tokens (as a TokenConfig array, for convenience)
     * @param minTokenBalances The minimum balances supplied by the caller (if any - this can be empty)
     * @return finalMinTokenBalances The validated minimum balances
     */
    function validateMinimumTokenBalances(
        TokenConfig[] memory tokens,
        uint256[] memory minTokenBalances
    ) internal view returns (uint256[] memory finalMinTokenBalances) {
        bool hasUserMinimums = minTokenBalances.length > 0;
        uint256 numTokens = tokens.length;

        if (hasUserMinimums) {
            InputHelpers.ensureInputLengthMatch(minTokenBalances.length, numTokens);
        }

        finalMinTokenBalances = new uint256[](numTokens);

        // Compute the default minimum balance: an equal share of the minimum pool value, as a scaled18 value.
        uint256 defaultMinTokenBalance = POOL_MINIMUM_TOTAL_SUPPLY / numTokens;

        // Adjust minimums for token decimals.
        for (uint256 i = 0; i < numTokens; ++i) {
            address token = address(tokens[i].token);
            uint256 tokenDecimals = IERC20Metadata(token).decimals();

            // Number of wei corresponding to 1 unit at the given decimal value (e.g., 18-decimals = 1 wei).
            // It doesn't make sense to have a minimum lower than this, as it would be truncated during downscaling.
            uint256 atomicUnitFloor = 10 ** (18 - tokenDecimals);

            // Note that the atomic unit floor only matters for tokens with 12 decimals or fewer:
            // - For the largest-allowed 8-token pools, the default minimum is given by: 1e6 / 8 = 1.25e5
            // - Atomic unit > 1.25e5 when: 10^(18-d) > 1.25e5; or d < ~12.9
            // - Therefore, for d > 12, the default minimum is always sufficient
            //
            // Could optimize this (i.e., only compute for <= 12 decimals), but this only happens on deployment.

            // Compute the decimal-adjusted minimum token balance.
            uint256 absoluteMinTokenBalance = Math.max(defaultMinTokenBalance, atomicUnitFloor);

            if (hasUserMinimums && minTokenBalances[i] < absoluteMinTokenBalance) {
                revert InvalidMinTokenBalance(token, minTokenBalances[i], absoluteMinTokenBalance);
            }

            // At this point the minimum has been validated, so use it if given.
            finalMinTokenBalances[i] = hasUserMinimums ? minTokenBalances[i] : absoluteMinTokenBalance;
        }
    }
}
