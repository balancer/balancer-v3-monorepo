// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolConfigConst } from "./PoolConfigConst.sol";

/**
 * @notice Helper functions to read and write the packed hook configuration flags stored in `_poolConfigBits`.
 * @dev  Note that the entire configuration of each pool is stored in the `_poolConfigBits` mapping (one slot
 * per pool). This includes the data in the `PoolConfig` struct, plus the data in the `HookFlags` struct.
 * The layout (i.e., offsets for each data field) is specified in `PoolConfigConst`.
 *
 * There are two libraries for interpreting these data. `HooksConfigLib` parses fields related to hooks, while
 * this one contains helpers related to the non-hook-related flags, along with aggregate fee percentages and
 * other data associated with pools.
 *
 * The `PoolData` struct contains the raw bitmap with the entire pool state (`PoolConfigBits`), plus the token
 * configuration, scaling factors, and dynamic information such as current balances and rates.
 */
library PoolConfigLib {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    /// @dev Given percentage is above FixedPoint.ONE (1e18 wei).
    error InvalidPercentage(uint256 value);

    // #region Bit offsets for main pool config settings
    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.POOL_REGISTERED_OFFSET);
    }

    function setPoolRegistered(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.POOL_REGISTERED_OFFSET)
            );
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.POOL_INITIALIZED_OFFSET);
    }

    function setPoolInitialized(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.POOL_INITIALIZED_OFFSET)
            );
    }

    function isPoolPaused(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.POOL_PAUSED_OFFSET);
    }

    function setPoolPaused(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.POOL_PAUSED_OFFSET));
    }

    function isPoolInRecoveryMode(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.POOL_RECOVERY_MODE_OFFSET);
    }

    function setPoolInRecoveryMode(PoolConfigBits config, bool value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(value, PoolConfigConst.POOL_RECOVERY_MODE_OFFSET)
            );
    }

    // #endregion

    // #region Bit offsets for liquidity operations
    function supportsUnbalancedLiquidity(PoolConfigBits config) internal pure returns (bool) {
        // NOTE: The unbalanced liquidity flag is default-on (false means it is supported).
        // This function returns the inverted value.
        return !PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.UNBALANCED_LIQUIDITY_OFFSET);
    }

    function requireUnbalancedLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsUnbalancedLiquidity() == false) {
            revert IVaultErrors.DoesNotSupportUnbalancedLiquidity();
        }
    }

    function setDisableUnbalancedLiquidity(
        PoolConfigBits config,
        bool disableUnbalancedLiquidity
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(
                    disableUnbalancedLiquidity,
                    PoolConfigConst.UNBALANCED_LIQUIDITY_OFFSET
                )
            );
    }

    function supportsAddLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.ADD_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireAddCustomLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsAddLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportAddLiquidityCustom();
        }
    }

    function setAddLiquidityCustom(
        PoolConfigBits config,
        bool enableAddLiquidityCustom
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(
                    enableAddLiquidityCustom,
                    PoolConfigConst.ADD_LIQUIDITY_CUSTOM_OFFSET
                )
            );
    }

    function supportsRemoveLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.REMOVE_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireRemoveCustomLiquidityEnabled(PoolConfigBits config) internal pure {
        if (config.supportsRemoveLiquidityCustom() == false) {
            revert IVaultErrors.DoesNotSupportRemoveLiquidityCustom();
        }
    }

    function setRemoveLiquidityCustom(
        PoolConfigBits config,
        bool enableRemoveLiquidityCustom
    ) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(
                    enableRemoveLiquidityCustom,
                    PoolConfigConst.REMOVE_LIQUIDITY_CUSTOM_OFFSET
                )
            );
    }

    function supportsDonation(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(PoolConfigConst.DONATION_OFFSET);
    }

    function setDonation(PoolConfigBits config, bool enableDonation) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertBool(enableDonation, PoolConfigConst.DONATION_OFFSET)
            );
    }

    function requireDonationEnabled(PoolConfigBits config) internal pure {
        if (config.supportsDonation() == false) {
            revert IVaultErrors.DoesNotSupportDonation();
        }
    }

    // #endregion

    // #region Bit offsets for uint values
    function getStaticSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return
            PoolConfigBits.unwrap(config).decodeUint(PoolConfigConst.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) *
            FEE_SCALING_FACTOR;
    }

    function setStaticSwapFeePercentage(PoolConfigBits config, uint256 value) internal pure returns (PoolConfigBits) {
        if (value > MAX_FEE_PERCENTAGE) {
            revert InvalidPercentage(value);
        }
        value /= FEE_SCALING_FACTOR;

        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(value, PoolConfigConst.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH)
            );
    }

    function getAggregateSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return
            PoolConfigBits.unwrap(config).decodeUint(PoolConfigConst.AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH) *
            FEE_SCALING_FACTOR;
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
                PoolConfigBits.unwrap(config).insertUint(
                    value,
                    PoolConfigConst.AGGREGATE_SWAP_FEE_OFFSET,
                    FEE_BITLENGTH
                )
            );
    }

    function getAggregateYieldFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return
            PoolConfigBits.unwrap(config).decodeUint(PoolConfigConst.AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH) *
            FEE_SCALING_FACTOR;
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
                PoolConfigBits.unwrap(config).insertUint(
                    value,
                    PoolConfigConst.AGGREGATE_YIELD_FEE_OFFSET,
                    FEE_BITLENGTH
                )
            );
    }

    function getTokenDecimalDiffs(PoolConfigBits config) internal pure returns (uint40) {
        return
            uint40(
                PoolConfigBits.unwrap(config).decodeUint(
                    PoolConfigConst.DECIMAL_SCALING_FACTORS_OFFSET,
                    PoolConfigConst.TOKEN_DECIMAL_DIFFS_BITLENGTH
                )
            );
    }

    function getDecimalScalingFactors(
        PoolConfigBits config,
        uint256 numTokens
    ) internal pure returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](numTokens);

        bytes32 tokenDecimalDiffs = bytes32(uint256(config.getTokenDecimalDiffs()));

        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 decimalDiff = tokenDecimalDiffs.decodeUint(
                i * PoolConfigConst.DECIMAL_DIFF_BITLENGTH,
                PoolConfigConst.DECIMAL_DIFF_BITLENGTH
            );

            // This is equivalent to `10**(18+decimalsDifference)` but this form optimizes for 18 decimal tokens.
            scalingFactors[i] = FixedPoint.ONE * 10 ** decimalDiff;
        }

        return scalingFactors;
    }

    function setTokenDecimalDiffs(PoolConfigBits config, uint40 value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(
                    value,
                    PoolConfigConst.DECIMAL_SCALING_FACTORS_OFFSET,
                    PoolConfigConst.TOKEN_DECIMAL_DIFFS_BITLENGTH
                )
            );
    }

    function getPauseWindowEndTime(PoolConfigBits config) internal pure returns (uint32) {
        return
            uint32(
                PoolConfigBits.unwrap(config).decodeUint(
                    PoolConfigConst.PAUSE_WINDOW_END_TIME_OFFSET,
                    PoolConfigConst.TIMESTAMP_BITLENGTH
                )
            );
    }

    function setPauseWindowEndTime(PoolConfigBits config, uint32 value) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                PoolConfigBits.unwrap(config).insertUint(
                    value,
                    PoolConfigConst.PAUSE_WINDOW_END_TIME_OFFSET,
                    PoolConfigConst.TIMESTAMP_BITLENGTH
                )
            );
    }

    // #endregion

    // Convert from an array of decimal differences, to the encoded 40-bit value (8 tokens * 5 bits/token).
    function toTokenDecimalDiffs(uint8[] memory tokenDecimalDiffs) internal pure returns (uint40) {
        bytes32 value;

        for (uint256 i = 0; i < tokenDecimalDiffs.length; ++i) {
            value = value.insertUint(
                tokenDecimalDiffs[i],
                i * PoolConfigConst.DECIMAL_DIFF_BITLENGTH,
                PoolConfigConst.DECIMAL_DIFF_BITLENGTH
            );
        }

        return uint40(uint256(value));
    }
}
