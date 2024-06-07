// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library PoolConfigLib {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    // Bit offsets for pool config
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = POOL_REGISTERED_OFFSET + 1;
    uint8 public constant POOL_PAUSED_OFFSET = POOL_INITIALIZED_OFFSET + 1;
    uint8 public constant POOL_RECOVERY_MODE_OFFSET = POOL_PAUSED_OFFSET + 1;

    // Supported liquidity API bit offsets
    uint8 public constant UNBALANCED_LIQUIDITY_OFFSET = POOL_RECOVERY_MODE_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = UNBALANCED_LIQUIDITY_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = ADD_LIQUIDITY_CUSTOM_OFFSET + 1;

    uint8 public constant STATIC_SWAP_FEE_OFFSET = REMOVE_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint256 public constant AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET = STATIC_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET = AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant DECIMAL_SCALING_FACTORS_OFFSET = AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant PAUSE_WINDOW_END_TIME_OFFSET =
        DECIMAL_SCALING_FACTORS_OFFSET + _TOKEN_DECIMAL_DIFFS_BITLENGTH;

    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint8 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;

    uint8 private constant _TIMESTAMP_BITLENGTH = 32;

    function isPoolRegistered(PoolConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(POOL_REGISTERED_OFFSET);
    }

    function setPoolRegistered(PoolConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, POOL_REGISTERED_OFFSET);
    }

    function isPoolInitialized(PoolConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function setPoolInitialized(PoolConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, POOL_INITIALIZED_OFFSET);
    }

    function isPoolInRecoveryMode(PoolConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(POOL_RECOVERY_MODE_OFFSET);
    }

    function setPoolInRecoveryMode(PoolConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, POOL_RECOVERY_MODE_OFFSET);
    }

    function isPoolPaused(PoolConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(POOL_PAUSED_OFFSET);
    }

    function setPoolPaused(PoolConfigBits memory config, bool value) internal pure {
        config.bits = config.bits.insertBool(value, POOL_PAUSED_OFFSET);
    }

    function getStaticSwapFeePercentage(PoolConfigBits memory config) internal pure returns (uint256) {
        return config.bits.decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setStaticSwapFeePercentage(PoolConfigBits memory config, uint256 value) internal pure {
        config.bits = config.bits.insertUint(value / FEE_SCALING_FACTOR, STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH);
    }

    function getAggregateProtocolSwapFeePercentage(PoolConfigBits memory config) internal pure returns (uint256) {
        return config.bits.decodeUint(AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateProtocolSwapFeePercentage(PoolConfigBits memory config, uint256 value) internal pure {
        config.bits = config.bits.insertUint(
            value / FEE_SCALING_FACTOR,
            AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
            FEE_BITLENGTH
        );
    }

    function getAggregateProtocolYieldFeePercentage(PoolConfigBits memory config) internal pure returns (uint256) {
        return config.bits.decodeUint(AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateProtocolYieldFeePercentage(PoolConfigBits memory config, uint256 value) internal pure {
        config.bits = config.bits.insertUint(
            value / FEE_SCALING_FACTOR,
            AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
            FEE_BITLENGTH
        );
    }

    function getTokenDecimalDiffs(PoolConfigBits memory config) internal pure returns (uint256) {
        return config.bits.decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH);
    }

    function setTokenDecimalDiffs(PoolConfigBits memory config, uint256 value) internal pure {
        config.bits = config.bits.insertUint(value, DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH);
    }

    function getPauseWindowEndTime(PoolConfigBits memory config) internal pure returns (uint256) {
        return config.bits.decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
    }

    function setPauseWindowEndTime(PoolConfigBits memory config, uint256 value) internal pure {
        config.bits = config.bits.insertUint(value, PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
    }

    function supportsUnbalancedLiquidity(PoolConfigBits memory config) internal pure returns (bool) {
        // NOTE: The unbalanced liquidity flag is default-on (false means it is supported)
        return !config.bits.decodeBool(UNBALANCED_LIQUIDITY_OFFSET);
    }

    function setDisableUnbalancedLiquidity(
        PoolConfigBits memory config,
        bool disableUnbalancedLiquidity
    ) internal pure {
        config.bits = config.bits.insertBool(disableUnbalancedLiquidity, UNBALANCED_LIQUIDITY_OFFSET);
    }

    function requireUnbalancedLiquidityEnabled(PoolConfigBits memory config) internal pure {
        if (config.supportsUnbalancedLiquidity() == false) {
            revert IVaultErrors.DoesNotSupportUnbalancedLiquidity();
        }
    }

    function supportsAddLiquidityCustom(PoolConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET);
    }

    function setAddLiquidityCustom(PoolConfigBits memory config, bool enableAddLiquidityCustom) internal pure {
        config.bits = config.bits.insertBool(enableAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireAddCustomLiquidityEnabled(PoolConfigBits memory config) internal pure {
        if (config.supportsAddLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportAddLiquidityCustom();
        }
    }

    function supportsRemoveLiquidityCustom(PoolConfigBits memory config) internal pure returns (bool) {
        return config.bits.decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET);
    }

    function setRemoveLiquidityCustom(PoolConfigBits memory config, bool enableRemoveLiquidityCustom) internal pure {
        config.bits = config.bits.insertBool(enableRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireRemoveCustomLiquidityEnabled(PoolConfigBits memory config) internal pure {
        if (config.supportsRemoveLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportRemoveLiquidityCustom();
        }
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
        PoolConfigBits memory config,
        uint256 numTokens
    ) internal pure returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](numTokens);

        bytes32 tokenDecimalDiffs = bytes32(config.getTokenDecimalDiffs());

        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 decimalDiff = tokenDecimalDiffs.decodeUint(i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);

            // This is equivalent to `10**(18+decimalsDifference)` but this form optimizes for 18 decimal tokens.
            scalingFactors[i] = FixedPoint.ONE * 10 ** decimalDiff;
        }

        return scalingFactors;
    }

    function fromPoolConfig(PoolConfig memory config) internal pure returns (PoolConfigBits memory configBits) {
        // Stack too deep.
        {
            configBits.bits = configBits
                .bits
                .insertBool(config.isPoolRegistered, POOL_REGISTERED_OFFSET)
                .insertBool(config.isPoolInitialized, POOL_INITIALIZED_OFFSET)
                .insertBool(config.isPoolPaused, POOL_PAUSED_OFFSET)
                .insertBool(config.isPoolInRecoveryMode, POOL_RECOVERY_MODE_OFFSET);
        }

        {
            configBits.bits = configBits
                .bits
                .insertBool(config.liquidityManagement.disableUnbalancedLiquidity, UNBALANCED_LIQUIDITY_OFFSET)
                .insertBool(config.liquidityManagement.enableAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET)
                .insertBool(config.liquidityManagement.enableRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        }
        {
            configBits.bits = configBits
                .bits
                .insertUint(config.staticSwapFeePercentage / FEE_SCALING_FACTOR, STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH)
                .insertUint(
                    config.aggregateProtocolSwapFeePercentage / FEE_SCALING_FACTOR,
                    AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
                    FEE_BITLENGTH
                )
                .insertUint(
                    config.aggregateProtocolYieldFeePercentage / FEE_SCALING_FACTOR,
                    AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
                    FEE_BITLENGTH
                );
        }

        configBits.bits = configBits
            .bits
            .insertUint(config.tokenDecimalDiffs, DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH)
            .insertUint(config.pauseWindowEndTime, PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
    }

    function toPoolConfig(PoolConfigBits memory config) internal pure returns (PoolConfig memory) {
        // Calling the functions (in addition to costing more gas), causes an obscure form of stack error (Yul errors).
        return
            PoolConfig({
                isPoolRegistered: config.bits.decodeBool(POOL_REGISTERED_OFFSET),
                isPoolInitialized: config.bits.decodeBool(POOL_INITIALIZED_OFFSET),
                isPoolPaused: config.bits.decodeBool(POOL_PAUSED_OFFSET),
                isPoolInRecoveryMode: config.bits.decodeBool(POOL_RECOVERY_MODE_OFFSET),
                staticSwapFeePercentage: config.bits.decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) *
                    FEE_SCALING_FACTOR,
                aggregateProtocolSwapFeePercentage: config.bits.decodeUint(
                    AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
                    FEE_BITLENGTH
                ) * FEE_SCALING_FACTOR,
                aggregateProtocolYieldFeePercentage: config.bits.decodeUint(
                    AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
                    FEE_BITLENGTH
                ) * FEE_SCALING_FACTOR,
                tokenDecimalDiffs: config.bits.decodeUint(
                    DECIMAL_SCALING_FACTORS_OFFSET,
                    _TOKEN_DECIMAL_DIFFS_BITLENGTH
                ),
                pauseWindowEndTime: config.bits.decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH),
                liquidityManagement: LiquidityManagement({
                    disableUnbalancedLiquidity: config.bits.decodeBool(UNBALANCED_LIQUIDITY_OFFSET),
                    enableAddLiquidityCustom: config.bits.decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET),
                    enableRemoveLiquidityCustom: config.bits.decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET)
                })
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
    function getPoolPausedState(PoolConfigBits memory config) internal pure returns (bool, uint256) {
        return (config.isPoolPaused(), config.getPauseWindowEndTime());
    }
}
