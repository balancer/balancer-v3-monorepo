// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store the PoolState portion of the pool configuration (the part that is packed).
type PoolConfigBits is bytes32;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    using WordCodec for bytes32;

    // Bit offsets for pool config
    uint8 public constant STATIC_SWAP_FEE_OFFSET = 0;
    uint256 public constant POOL_CREATOR_FEE_OFFSET = STATIC_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant DECIMAL_SCALING_FACTORS_OFFSET = POOL_CREATOR_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant PAUSE_WINDOW_END_TIME_OFFSET =
        DECIMAL_SCALING_FACTORS_OFFSET + _TOKEN_DECIMAL_DIFFS_BITLENGTH;
    uint256 public constant AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET = PAUSE_WINDOW_END_TIME_OFFSET + _TIMESTAMP_BITLENGTH;
    uint256 public constant AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET = AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant POOL_PAUSED_OFFSET = AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET + FEE_BITLENGTH;

    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint8 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;
    uint8 private constant _TIMESTAMP_BITLENGTH = 32;

    function getStaticSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function getAggregateProtocolSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return
            PoolConfigBits.unwrap(config).decodeUint(AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET, FEE_BITLENGTH) *
            FEE_SCALING_FACTOR;
    }

    function getAggregateProtocolYieldFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return
            PoolConfigBits.unwrap(config).decodeUint(AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET, FEE_BITLENGTH) *
            FEE_SCALING_FACTOR;
    }

    function getTokenDecimalDiffs(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH);
    }

    function getPauseWindowEndTime(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
    }

    function isPoolPaused(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_PAUSED_OFFSET);
    }

    function fromPoolState(PoolState memory config) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                bytes32(0)
                    .insertBool(config.isPoolPaused, POOL_PAUSED_OFFSET)
                    .insertUint(
                        config.staticSwapFeePercentage / FEE_SCALING_FACTOR,
                        STATIC_SWAP_FEE_OFFSET,
                        FEE_BITLENGTH
                    )
                    .insertUint(
                        config.aggregateProtocolSwapFeePercentage / FEE_SCALING_FACTOR,
                        AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
                        FEE_BITLENGTH
                    )
                    .insertUint(
                        config.aggregateProtocolYieldFeePercentage / FEE_SCALING_FACTOR,
                        AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
                        FEE_BITLENGTH
                    )
                    .insertUint(
                        config.tokenDecimalDiffs,
                        DECIMAL_SCALING_FACTORS_OFFSET,
                        _TOKEN_DECIMAL_DIFFS_BITLENGTH
                    )
                    .insertUint(config.pauseWindowEndTime, PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH)
            );
    }

    // Convert from an array of decimal differences, to the encoded 24 bit value (only uses bottom 20 bits).
    function toTokenDecimalDiffs(uint8[] memory tokenDecimalDiffs) internal pure returns (uint256) {
        bytes32 value;

        for (uint256 i = 0; i < tokenDecimalDiffs.length; ++i) {
            value = value.insertUint(tokenDecimalDiffs[i], i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);
        }

        return uint256(value);
    }

    function getDecimalScalingFactors(
        PoolState memory config,
        uint256 numTokens
    ) internal pure returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](numTokens);

        bytes32 tokenDecimalDiffs = bytes32(uint256(config.tokenDecimalDiffs));

        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 decimalDiff = tokenDecimalDiffs.decodeUint(i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);

            // This is equivalent to `10**(18+decimalsDifference)` but this form optimizes for 18 decimal tokens.
            scalingFactors[i] = FixedPoint.ONE * 10 ** decimalDiff;
        }

        return scalingFactors;
    }

    function toPoolState(PoolConfigBits config) internal pure returns (PoolState memory) {
        bytes32 rawConfig = PoolConfigBits.unwrap(config);

        // Calling the functions (in addition to costing more gas), causes an obscure form of stack error (Yul errors).
        return
            PoolState({
                staticSwapFeePercentage: rawConfig.decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) *
                    FEE_SCALING_FACTOR,
                aggregateProtocolSwapFeePercentage: rawConfig.decodeUint(
                    AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
                    FEE_BITLENGTH
                ) * FEE_SCALING_FACTOR,
                aggregateProtocolYieldFeePercentage: rawConfig.decodeUint(
                    AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
                    FEE_BITLENGTH
                ) * FEE_SCALING_FACTOR,
                tokenDecimalDiffs: rawConfig.decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH),
                pauseWindowEndTime: rawConfig.decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH),
                isPoolPaused: rawConfig.decodeBool(POOL_PAUSED_OFFSET)
            });
    }

    /**
     * @dev There is a lot of data packed into the PoolConfig, but most often we only need one or two pieces of it.
     * Since it is costly to pack and unpack the entire structure, convenience functions like `getPoolPausedState`
     * help streamline frequent operations. The pause state needs to be checked on every state-changing pool operation.
     *
     * @param config The encoded pool configuration
     * @return paused Whether the pool was paused (i.e., the bit was set)
     * @return pauseWindowEndTime The end of the pause period, used to determine whether the pool is actually paused
     */
    function getPoolPausedState(PoolConfigBits config) internal pure returns (bool, uint256) {
        return (config.isPoolPaused(), config.getPauseWindowEndTime());
    }
}
