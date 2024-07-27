// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolData, TokenInfo, TokenType, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { PoolConfigBits, PoolConfigLib } from "./PoolConfigLib.sol";

/**
 * @notice Helper functions to read/write a `PoolData` struct.
 * @dev Note that the entire configuration of each pool is stored in the `_poolConfigBits` mapping (one slot per pool).
 * This includes the data in the `PoolConfig` struct, plus the data in the `HookFlags` struct. The layout (i.e.,
 * offsets for each data field) is specified in `PoolConfigConst`.
 *
 * The `PoolData` struct contains the raw bitmap with the entire pool state (`PoolConfigBits`), plus the token
 * configuration, scaling factors, and dynamic information such as current balances and rates.
 */
library PoolDataLib {
    using PackedTokenBalance for bytes32;
    using FixedPoint for *;
    using ScalingHelpers for *;
    using PoolConfigLib for PoolConfigBits;

    function load(
        PoolData memory poolData,
        mapping(uint => bytes32) storage poolTokenBalances,
        PoolConfigBits poolConfigBits,
        mapping(IERC20 => TokenInfo) storage poolTokenInfo,
        IERC20[] storage tokens,
        Rounding roundingDirection
    ) internal view {
        uint256 numTokens = tokens.length;

        poolData.poolConfigBits = poolConfigBits;
        poolData.tokens = tokens;
        poolData.tokenInfo = new TokenInfo[](numTokens);
        poolData.balancesRaw = new uint256[](numTokens);
        poolData.balancesLiveScaled18 = new uint256[](numTokens);
        poolData.decimalScalingFactors = PoolConfigLib.getDecimalScalingFactors(poolData.poolConfigBits, numTokens);
        poolData.tokenRates = new uint256[](numTokens);

        bool poolSubjectToYieldFees = poolData.poolConfigBits.isPoolInitialized() &&
            poolData.poolConfigBits.getAggregateYieldFeePercentage() > 0 &&
            poolData.poolConfigBits.isPoolInRecoveryMode() == false;

        for (uint256 i = 0; i < numTokens; ++i) {
            TokenInfo memory tokenInfo = poolTokenInfo[poolData.tokens[i]];
            bytes32 packedBalance = poolTokenBalances[i];

            poolData.tokenInfo[i] = tokenInfo;
            poolData.tokenRates[i] = getTokenRate(tokenInfo);
            updateRawAndLiveBalance(poolData, i, packedBalance.getBalanceRaw(), roundingDirection);

            // If there are no yield fees, we can save gas by skipping to the next token now.
            if (poolSubjectToYieldFees == false) {
                continue;
            }

            // `poolData` already has live balances computed from raw balances according to the token rates and the
            // given rounding direction. Charging a yield fee changes the raw balance, in which case the safest and
            // most numerically precise way to adjust the live balance is to simply repeat the scaling (hence the
            // second call below).

            // The Vault actually guarantees that a token with paysYieldFees set is a WITH_RATE token, so technically
            // we could just check the flag, but we don't want to introduce that dependency for a slight gas savings.
            bool tokenSubjectToYieldFees = tokenInfo.paysYieldFees && tokenInfo.tokenType == TokenType.WITH_RATE;

            // Do not charge yield fees before the pool is initialized, or in recovery mode.
            if (tokenSubjectToYieldFees) {
                uint256 aggregateYieldFeePercentage = poolData.poolConfigBits.getAggregateYieldFeePercentage();
                uint256 balanceRaw = poolData.balancesRaw[i];

                uint256 aggregateYieldFeeAmountRaw = _computeYieldFeesDue(
                    poolData,
                    packedBalance.getBalanceDerived(),
                    i,
                    aggregateYieldFeePercentage
                );

                if (aggregateYieldFeeAmountRaw > 0) {
                    updateRawAndLiveBalance(poolData, i, balanceRaw - aggregateYieldFeeAmountRaw, roundingDirection);
                }
            }
        }
    }

    function syncPoolBalancesAndFees(
        PoolData memory poolData,
        mapping(uint256 => bytes32) storage poolTokenBalances,
        mapping(IERC20 => bytes32) storage poolAggregateProtocolFeeAmounts
    ) internal {
        uint256 numTokens = poolData.balancesRaw.length;

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolData.tokens[i];
            bytes32 packedBalances = poolTokenBalances[i];
            uint256 storedBalanceRaw = packedBalances.getBalanceRaw();

            // `poolData` now has balances updated with yield fees.
            // If yield fees are not 0, then the stored balance is greater than the one in memory.
            if (storedBalanceRaw > poolData.balancesRaw[i]) {
                // Both Swap and Yield fees are stored together in a `PackedTokenBalance`.
                // We have designated "Derived" the derived half for Yield fee storage.
                bytes32 packedProtocolFeeAmounts = poolAggregateProtocolFeeAmounts[token];
                poolAggregateProtocolFeeAmounts[token] = packedProtocolFeeAmounts.setBalanceDerived(
                    packedProtocolFeeAmounts.getBalanceDerived() + (storedBalanceRaw - poolData.balancesRaw[i])
                );
            }

            poolTokenBalances[i] = PackedTokenBalance.toPackedBalance(
                poolData.balancesRaw[i],
                poolData.balancesLiveScaled18[i]
            );
        }
    }

    /**
     * @dev This is typically called after a reentrant callback (e.g., a "before" liquidity operation callback),
     * to refresh the poolData struct with any balances (or rates) that might have changed.
     *
     * Preconditions: tokenConfig, balancesRaw, and decimalScalingFactors must be current in `poolData`.
     * Side effects: mutates tokenRates, balancesLiveScaled18 in `poolData`.
     */
    function reloadBalancesAndRates(
        PoolData memory poolData,
        mapping(uint256 => bytes32) storage poolTokenBalances,
        Rounding roundingDirection
    ) internal view {
        uint256 numTokens = poolData.tokens.length;

        // It's possible a reentrant hook changed the raw balances in Vault storage.
        // Update them before computing the live balances.
        bytes32 packedBalance;

        for (uint256 i = 0; i < numTokens; ++i) {
            poolData.tokenRates[i] = getTokenRate(poolData.tokenInfo[i]);

            packedBalance = poolTokenBalances[i];

            // Note the order dependency. This requires up-to-date tokenRate for the token at index `i` in `poolData`
            updateRawAndLiveBalance(poolData, i, packedBalance.getBalanceRaw(), roundingDirection);
        }
    }

    function getTokenRate(TokenInfo memory tokenInfo) internal view returns (uint256 rate) {
        TokenType tokenType = tokenInfo.tokenType;

        if (tokenType == TokenType.STANDARD) {
            rate = FixedPoint.ONE;
        } else if (tokenType == TokenType.WITH_RATE) {
            rate = tokenInfo.rateProvider.getRate();
        } else {
            revert IVaultErrors.InvalidTokenConfiguration();
        }
    }

    function updateRawAndLiveBalance(
        PoolData memory poolData,
        uint256 tokenIndex,
        uint256 newRawBalance,
        Rounding roundingDirection
    ) internal pure {
        poolData.balancesRaw[tokenIndex] = newRawBalance;

        function(uint256, uint256, uint256) internal pure returns (uint256) _upOrDown = roundingDirection ==
            Rounding.ROUND_UP
            ? ScalingHelpers.toScaled18ApplyRateRoundUp
            : ScalingHelpers.toScaled18ApplyRateRoundDown;

        poolData.balancesLiveScaled18[tokenIndex] = _upOrDown(
            newRawBalance,
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );
    }

    // solhint-disable-next-line private-vars-leading-underscore
    function _computeYieldFeesDue(
        PoolData memory poolData,
        uint256 lastLiveBalance,
        uint256 tokenIndex,
        uint256 aggregateYieldFeePercentage
    ) internal pure returns (uint256 aggregateYieldFeeAmountRaw) {
        uint256 currentLiveBalance = poolData.balancesLiveScaled18[tokenIndex];

        // Do not charge fees if rates go down. If the rate were to go up, down, and back up again, protocol fees
        // would be charged multiple times on the "same" yield. For tokens subject to yield fees, this should not
        // happen, or at least be very rare. It can be addressed for known volatile rates by setting the yield fee
        // exempt flag on registration, or compensated off-chain if there is an incident with a normally
        // well-behaved rate provider.
        if (currentLiveBalance > lastLiveBalance) {
            unchecked {
                // Magnitudes are checked above, so it's safe to do unchecked math here.
                uint256 aggregateYieldFeeAmountScaled18 = (currentLiveBalance - lastLiveBalance).mulUp(
                    aggregateYieldFeePercentage
                );

                // A pool is subject to yield fees if poolSubjectToYieldFees is true, meaning that
                // `protocolYieldFeePercentage > 0`. So, we don't need to check this again in here, saving some gas.
                aggregateYieldFeeAmountRaw = aggregateYieldFeeAmountScaled18.toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[tokenIndex],
                    poolData.tokenRates[tokenIndex]
                );
            }
        }
    }
}
