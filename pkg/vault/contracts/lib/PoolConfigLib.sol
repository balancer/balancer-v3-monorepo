// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library PoolConfigLib {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    error InvalidSize(uint256 expected);

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
    uint256 public constant AGGREGATE_SWAP_FEE_OFFSET = STATIC_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant AGGREGATE_YIELD_FEE_OFFSET = AGGREGATE_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant DECIMAL_SCALING_FACTORS_OFFSET = AGGREGATE_YIELD_FEE_OFFSET + FEE_BITLENGTH;
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
        value /= FEE_SCALING_FACTOR;

        if (value > MAX_FEE_VALUE) {
            revert InvalidSize(FEE_BITLENGTH);
        }

        config.bits = config.bits.insertUint(value, STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH);
    }

    function getAggregateSwapFeePercentage(PoolConfigBits memory config) internal pure returns (uint256) {
        return config.bits.decodeUint(AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateSwapFeePercentage(PoolConfigBits memory config, uint256 value) internal pure {
        value /= FEE_SCALING_FACTOR;

        if (value > MAX_FEE_VALUE) {
            revert InvalidSize(FEE_BITLENGTH);
        }

        config.bits = config.bits.insertUint(value, AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH);
    }

    function getAggregateYieldFeePercentage(PoolConfigBits memory config) internal pure returns (uint256) {
        return config.bits.decodeUint(AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateYieldFeePercentage(PoolConfigBits memory config, uint256 value) internal pure {
        value /= FEE_SCALING_FACTOR;

        if (value > MAX_FEE_VALUE) {
            revert InvalidSize(FEE_BITLENGTH);
        }

        config.bits = config.bits.insertUint(value, AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH);
    }

    function getTokenDecimalDiffs(PoolConfigBits memory config) internal pure returns (uint24) {
        return uint24(config.bits.decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH));
    }

    function setTokenDecimalDiffs(PoolConfigBits memory config, uint24 value) internal pure {
        config.bits = config.bits.insertUint(value, DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH);
    }

    function getPauseWindowEndTime(PoolConfigBits memory config) internal pure returns (uint32) {
        return uint32(config.bits.decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH));
    }

    function setPauseWindowEndTime(PoolConfigBits memory config, uint32 value) internal pure {
        config.bits = config.bits.insertUint(value, PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
    }

    function supportsUnbalancedLiquidity(PoolConfigBits memory config) internal pure returns (bool) {
        // NOTE: The unbalanced liquidity flag is default-on (false means it is supported).
        // This function returns the inverted value.
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
    function toTokenDecimalDiffs(uint8[] memory tokenDecimalDiffs) internal pure returns (uint24) {
        bytes32 value;

        for (uint256 i = 0; i < tokenDecimalDiffs.length; ++i) {
            value = value.insertUint(tokenDecimalDiffs[i], i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);
        }

        return uint24(uint256(value));
    }

    function getDecimalScalingFactors(
        PoolConfigBits memory config,
        uint256 numTokens
    ) internal pure returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](numTokens);

        bytes32 tokenDecimalDiffs = bytes32(uint256(config.getTokenDecimalDiffs()));

        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 decimalDiff = tokenDecimalDiffs.decodeUint(i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);

            // This is equivalent to `10**(18+decimalsDifference)` but this form optimizes for 18 decimal tokens.
            scalingFactors[i] = FixedPoint.ONE * 10 ** decimalDiff;
        }

        return scalingFactors;
    }
}
