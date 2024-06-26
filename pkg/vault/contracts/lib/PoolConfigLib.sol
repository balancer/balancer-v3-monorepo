// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library PoolConfigLib {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    error InvalidPercentage(uint256 value);
    error InvalidSize(uint256 currentValue, uint256 expectedSize);

    // Bit offsets for pool config
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = POOL_REGISTERED_OFFSET + 1;
    uint8 public constant POOL_PAUSED_OFFSET = POOL_INITIALIZED_OFFSET + 1;
    uint8 public constant POOL_RECOVERY_MODE_OFFSET = POOL_PAUSED_OFFSET + 1;

    // Supported liquidity API bit offsets
    uint8 public constant UNBALANCED_LIQUIDITY_OFFSET = POOL_RECOVERY_MODE_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = UNBALANCED_LIQUIDITY_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = ADD_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint8 public constant DONATION_OFFSET = REMOVE_LIQUIDITY_CUSTOM_OFFSET + 1;

    uint8 public constant STATIC_SWAP_FEE_OFFSET = DONATION_OFFSET + 1;
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

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function setPoolRegistered(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_REGISTERED_OFFSET));
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function setPoolInitialized(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_INITIALIZED_OFFSET));
    }

    function isPoolInRecoveryMode(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_RECOVERY_MODE_OFFSET);
    }

    function setPoolInRecoveryMode(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_RECOVERY_MODE_OFFSET));
    }

    function isPoolPaused(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_PAUSED_OFFSET);
    }

    function setPoolPaused(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, POOL_PAUSED_OFFSET));
    }

    function getStaticSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    // solhint-disable-next-line private-vars-leading-underscore
    function _setStaticSwapFeePercentage(PoolConfigBits config, uint256 value) internal pure returns (PoolConfigBits) {
        if (value > MAX_FEE_PERCENTAGE) {
            revert InvalidPercentage(value);
        }
        value /= FEE_SCALING_FACTOR;

        return
            PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertUint(value, STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH));
    }

    function getAggregateSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateSwapFeePercentage(
        PoolConfigBits config,
        uint256 value
    ) internal pure returns (PoolConfigBits) {
        if (value > MAX_FEE_PERCENTAGE) {
            revert InvalidPercentage(value);
        }
        value /= FEE_SCALING_FACTOR;

        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(value, AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH)
            );
    }

    function getAggregateYieldFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function setAggregateYieldFeePercentage(
        PoolConfigBits config,
        uint256 value
    ) internal pure returns (PoolConfigBits) {
        if (value > MAX_FEE_PERCENTAGE) {
            revert InvalidPercentage(value);
        }
        value /= FEE_SCALING_FACTOR;

        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(value, AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH)
            );
    }

    function getTokenDecimalDiffs(PoolConfigBits config) internal pure returns (uint24) {
        return
            uint24(
                PoolConfigBits.unwrap(config).decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH)
            );
    }

    function setTokenDecimalDiffs(PoolConfigBits config, uint24 value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(
                    value,
                    DECIMAL_SCALING_FACTORS_OFFSET,
                    _TOKEN_DECIMAL_DIFFS_BITLENGTH
                )
            );
    }

    function getPauseWindowEndTime(PoolConfigBits config) internal pure returns (uint32) {
        return uint32(PoolConfigBits.unwrap(config).decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH));
    }

    function setPauseWindowEndTime(PoolConfigBits config, uint32 value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(value, PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH)
            );
    }

    function supportsUnbalancedLiquidity(PoolConfigBits config) internal pure returns (bool) {
        // NOTE: The unbalanced liquidity flag is default-on (false means it is supported).
        // This function returns the inverted value.
        return !PoolConfigBits.unwrap(config).decodeBool(UNBALANCED_LIQUIDITY_OFFSET);
    }

    function setDisableUnbalancedLiquidity(
        PoolConfigBits config,
        bool disableUnbalancedLiquidity
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(disableUnbalancedLiquidity, UNBALANCED_LIQUIDITY_OFFSET)
            );
    }

    function requireUnbalancedLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsUnbalancedLiquidity() == false) {
            revert IVaultErrors.DoesNotSupportUnbalancedLiquidity();
        }
    }

    function supportsAddLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET);
    }

    function setAddLiquidityCustom(
        PoolConfigBits config,
        bool enableAddLiquidityCustom
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(enableAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET)
            );
    }

    function requireAddCustomLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsAddLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportAddLiquidityCustom();
        }
    }

    function supportsRemoveLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET);
    }

    function setRemoveLiquidityCustom(
        PoolConfigBits config,
        bool enableRemoveLiquidityCustom
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(enableRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET)
            );
    }

    function requireRemoveCustomLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsRemoveLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportRemoveLiquidityCustom();
        }
    }

    function supportsDonation(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(DONATION_OFFSET);
    }

    function setDonation(PoolConfigBits config, bool enableDonation) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(enableDonation, DONATION_OFFSET));
    }

    function requireDonationEnabled(PoolConfigBits config) internal pure {
        if (config.supportsDonation() == false) {
            revert IVaultErrors.DoesNotSupportDonation();
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
        PoolConfigBits config,
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

    function setStaticSwapFeePercentage(
        mapping(address => PoolConfigBits) storage poolConfigBits,
        address pool,
        uint256 swapFeePercentage
    ) internal {
        // These cannot be called during pool construction. Pools must be deployed first, then registered.
        if (swapFeePercentage < ISwapFeePercentageBounds(pool).getMinimumSwapFeePercentage()) {
            revert IVaultErrors.SwapFeePercentageTooLow();
        }

        // Still has to be a valid percentage, regardless of what the pool defines.
        if (
            swapFeePercentage > ISwapFeePercentageBounds(pool).getMaximumSwapFeePercentage() ||
            swapFeePercentage > FixedPoint.ONE
        ) {
            revert IVaultErrors.SwapFeePercentageTooHigh();
        }

        poolConfigBits[pool] = poolConfigBits[pool]._setStaticSwapFeePercentage(swapFeePercentage);

        emit IVaultEvents.SwapFeePercentageChanged(pool, swapFeePercentage);
    }
}
