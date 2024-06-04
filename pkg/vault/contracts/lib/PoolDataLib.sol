// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PackedTokenBalance } from "./PackedTokenBalance.sol";
import { PoolConfigBits, PoolConfigLib } from "./PoolConfigLib.sol";

import {
    PoolData,
    Rounding,
    TokenType,
    PoolConfig,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library PoolDataLib {
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using PackedTokenBalance for bytes32;
    using FixedPoint for *;
    using ScalingHelpers for *;

    function load(
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances,
        PoolConfigBits poolConfig,
        mapping(IERC20 => TokenConfig) storage poolTokenConfig,
        Rounding roundingDirection
    ) internal view returns (PoolData memory poolData) {
        uint256 numTokens = poolTokenBalances.length();
        poolData.poolConfig = PoolConfigLib.toPoolConfig(poolConfig);

        poolData.tokenConfig = new TokenConfig[](numTokens);
        poolData.balancesRaw = new uint256[](numTokens);
        poolData.balancesLiveScaled18 = new uint256[](numTokens);
        poolData.decimalScalingFactors = PoolConfigLib.getDecimalScalingFactors(poolData.poolConfig, numTokens);
        poolData.tokenRates = new uint256[](numTokens);

        bool poolSubjectToYieldFees = poolData.poolConfig.isPoolInitialized &&
            poolData.poolConfig.aggregateProtocolYieldFeePercentage > 0 &&
            poolData.poolConfig.isPoolInRecoveryMode == false;

        for (uint256 i = 0; i < numTokens; ++i) {
            (IERC20 token, bytes32 packedBalance) = poolTokenBalances.unchecked_at(i);
            poolData.tokenConfig[i] = poolTokenConfig[token];
            updateTokenRate(poolData, i);
            updateRawAndLiveBalance(poolData, i, packedBalance.getBalanceRaw(), roundingDirection);

            uint256 aggregateYieldFeeAmountRaw = 0;
            TokenConfig memory tokenConfig = poolData.tokenConfig[i];

            // poolData already has live balances computed from raw balances according to the token rates and the
            // given rounding direction. Charging a yield fee changes the raw
            // balance, in which case the safest and most numerically precise way to adjust
            // the live balance is to simply repeat the scaling (hence the second call below).

            // The Vault actually guarantees a token with paysYieldFees set is a WITH_RATE token, so technically we
            // could just check the flag, but we don't want to introduce that dependency for a slight gas savings.
            bool tokenSubjectToYieldFees = tokenConfig.paysYieldFees && tokenConfig.tokenType == TokenType.WITH_RATE;

            // Do not charge yield fees until the pool is initialized, and is not in recovery mode.
            if (poolSubjectToYieldFees && tokenSubjectToYieldFees) {
                aggregateYieldFeeAmountRaw = _computeYieldFeesDue(
                    poolData,
                    packedBalance.getBalanceDerived(),
                    i,
                    poolData.poolConfig.aggregateProtocolYieldFeePercentage
                );
            }

            if (aggregateYieldFeeAmountRaw > 0) {
                updateRawAndLiveBalance(
                    poolData,
                    i,
                    poolData.balancesRaw[i] - aggregateYieldFeeAmountRaw,
                    roundingDirection
                );
            }
        }
    }

    function syncPoolBalancesAndFees(
        PoolData memory poolData,
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances,
        mapping(IERC20 => bytes32) storage poolAggregateProtocolFeeAmounts
    ) internal {
        uint256 numTokens = poolData.balancesRaw.length;

        for (uint256 i = 0; i < numTokens; ++i) {
            IERC20 token = poolData.tokenConfig[i].token;
            bytes32 packedBalances = poolTokenBalances.unchecked_valueAt(i);
            uint256 storedBalanceRaw = packedBalances.getBalanceRaw();

            // poolData has balances updated with yield fees now.
            // If yield fees are not 0, then the stored balance is greater than the one in memory.
            if (storedBalanceRaw > poolData.balancesRaw[i]) {
                // Both Swap and Yield fees are stored together in a PackedTokenBalance.
                // We have designated "Derived" the derived half for Yield fee storage.
                bytes32 packedProtocolFeeAmounts = poolAggregateProtocolFeeAmounts[token];
                poolAggregateProtocolFeeAmounts[token] = packedProtocolFeeAmounts.setBalanceDerived(
                    packedProtocolFeeAmounts.getBalanceDerived() + (storedBalanceRaw - poolData.balancesRaw[i])
                );
            }

            poolTokenBalances.unchecked_setAt(
                i,
                PackedTokenBalance.toPackedBalance(poolData.balancesRaw[i], poolData.balancesLiveScaled18[i])
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
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances,
        Rounding roundingDirection
    ) internal view {
        uint256 numTokens = poolData.tokenConfig.length;

        // It's possible a reentrant hook changed the raw balances in Vault storage.
        // Update them before computing the live balances.
        bytes32 packedBalance;

        for (uint256 i = 0; i < numTokens; ++i) {
            updateTokenRate(poolData, i);

            (, packedBalance) = poolTokenBalances.unchecked_at(i);

            // Note the order dependency. This requires up-to-date tokenRate for the token at index `i` in `poolData`
            updateRawAndLiveBalance(poolData, i, packedBalance.getBalanceRaw(), roundingDirection);
        }
    }

    function updateTokenRate(PoolData memory poolData, uint256 tokenIndex) internal view {
        TokenType tokenType = poolData.tokenConfig[tokenIndex].tokenType;

        if (tokenType == TokenType.STANDARD) {
            poolData.tokenRates[tokenIndex] = FixedPoint.ONE;
        } else if (tokenType == TokenType.WITH_RATE) {
            poolData.tokenRates[tokenIndex] = poolData.tokenConfig[tokenIndex].rateProvider.getRate();
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

    function increaseTokenBalance(
        PoolData memory poolData,
        uint256 tokenIndex,
        uint256 amountToIncreaseRaw
    ) internal pure {
        updateRawAndLiveBalance(
            poolData,
            tokenIndex,
            poolData.balancesRaw[tokenIndex] + amountToIncreaseRaw,
            Rounding.ROUND_UP
        );
    }

    function decreaseTokenBalance(
        PoolData memory poolData,
        uint256 tokenIndex,
        uint256 amountToDecreaseRaw
    ) internal pure {
        updateRawAndLiveBalance(
            poolData,
            tokenIndex,
            poolData.balancesRaw[tokenIndex] - amountToDecreaseRaw,
            Rounding.ROUND_DOWN
        );
    }

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
                // Magnitudes checked above, so it's safe to do unchecked math here.
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
