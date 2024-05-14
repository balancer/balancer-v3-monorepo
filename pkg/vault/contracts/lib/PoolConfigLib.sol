// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store entire configuration of the pool
type PoolConfigBits is bytes32;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    using WordCodec for bytes32;

    // Bit offsets for pool config
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = POOL_REGISTERED_OFFSET + 1;
    uint8 public constant POOL_PAUSED_OFFSET = POOL_INITIALIZED_OFFSET + 1;
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = POOL_PAUSED_OFFSET + 1;
    uint8 public constant BEFORE_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = BEFORE_SWAP_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_INITIALIZE_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_INITIALIZE_OFFSET = BEFORE_INITIALIZE_OFFSET + 1;
    uint8 public constant POOL_RECOVERY_MODE_OFFSET = AFTER_INITIALIZE_OFFSET + 1;

    // Supported liquidity API bit offsets
    uint8 public constant UNBALANCED_LIQUIDITY_OFFSET = POOL_RECOVERY_MODE_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = UNBALANCED_LIQUIDITY_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = ADD_LIQUIDITY_CUSTOM_OFFSET + 1;

    uint8 public constant STATIC_SWAP_FEE_OFFSET = REMOVE_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint256 public constant POOL_CREATOR_FEE_OFFSET = STATIC_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant DECIMAL_SCALING_FACTORS_OFFSET = POOL_CREATOR_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant PAUSE_WINDOW_END_TIME_OFFSET =
        DECIMAL_SCALING_FACTORS_OFFSET + _TOKEN_DECIMAL_DIFFS_BITLENGTH;

    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint8 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;

    uint8 private constant _TIMESTAMP_BITLENGTH = 32;

    // Flags used to read/write fields selectively.
    uint16 public constant REGISTERED_FLAG = 1;
    uint16 public constant INITIALIZED_FLAG = 1 << 1;
    uint16 public constant PAUSED_FLAG = 1 << 2;
    uint16 public constant RECOVERY_MODE_FLAG = 1 << 3;
    uint16 public constant STATIC_SWAP_FEE_FLAG = 1 << 4;
    uint16 public constant POOL_CREATOR_FEE_FLAG = 1 << 5;
    uint16 public constant TOKEN_DECIMALS_FLAG = 1 << 6;
    uint16 public constant PAUSE_WINDOW_FLAG = 1 << 7;
    uint16 public constant HOOKS_FLAG = 1 << 8;
    uint16 public constant LIQUIDITY_FLAG = 1 << 9;

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function isPoolInRecoveryMode(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_RECOVERY_MODE_OFFSET);
    }

    function isPoolPaused(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_PAUSED_OFFSET);
    }

    function getStaticSwapFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function getPoolCreatorFeePercentage(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(POOL_CREATOR_FEE_OFFSET, FEE_BITLENGTH) * FEE_SCALING_FACTOR;
    }

    function getTokenDecimalDiffs(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH);
    }

    function getPauseWindowEndTime(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
    }

    function shouldCallComputeDynamicSwapFee(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(DYNAMIC_SWAP_FEE_OFFSET);
    }

    function shouldCallBeforeSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_SWAP_OFFSET);
    }

    function shouldCallAfterSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_SWAP_OFFSET);
    }

    function shouldCallBeforeAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallBeforeRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function shouldCallBeforeInitialize(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_INITIALIZE_OFFSET);
    }

    function shouldCallAfterInitialize(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_INITIALIZE_OFFSET);
    }

    function supportsUnbalancedLiquidity(PoolConfigBits config) internal pure returns (bool) {
        // NOTE: The unbalanced liquidity flag is default-on (false means it is supported)
        return !PoolConfigBits.unwrap(config).decodeBool(UNBALANCED_LIQUIDITY_OFFSET);
    }

    function requireUnbalancedLiquidityEnabled(PoolConfig memory config) internal pure {
        if (config.liquidityManagement.disableUnbalancedLiquidity == true) {
            revert IVaultErrors.DoesNotSupportUnbalancedLiquidity();
        }
    }

    function supportsAddLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireAddCustomLiquidityEnabled(PoolConfig memory config) internal pure {
        if (config.liquidityManagement.enableAddLiquidityCustom == false) {
            revert IVaultErrors.DoesNotSupportAddLiquidityCustom();
        }
    }

    function supportsRemoveLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireRemoveCustomLiquidityEnabled(PoolConfig memory config) internal pure {
        if (config.liquidityManagement.enableRemoveLiquidityCustom == false) {
            revert IVaultErrors.DoesNotSupportRemoveLiquidityCustom();
        }
    }

    function fromPoolConfig(
        PoolConfigBits configBits,
        PoolConfig memory config,
        uint16 cherryPicks
    ) internal pure returns (PoolConfigBits) {
        bytes32 poolConfig = PoolConfigBits.unwrap(configBits);
        // Subtract if we want to short-circuit and not do other checks.
        // Just tried for most common first (paused check).
        uint16 picked = cherryPicks;

        if (cherryPicks & PAUSED_FLAG != 0) {
            poolConfig = poolConfig.insertBool(config.isPoolPaused, POOL_PAUSED_OFFSET);
            picked -= PAUSED_FLAG;
            if (picked == 0) {
                return PoolConfigBits.wrap(poolConfig);
            }
        }
        if (cherryPicks & PAUSE_WINDOW_FLAG != 0) {
            poolConfig = poolConfig.insertUint(
                config.pauseWindowEndTime,
                PAUSE_WINDOW_END_TIME_OFFSET,
                _TIMESTAMP_BITLENGTH
            );
            picked -= PAUSE_WINDOW_FLAG;
            if (picked == 0) {
                return PoolConfigBits.wrap(poolConfig);
            }
        }
        if (cherryPicks & REGISTERED_FLAG != 0) {
            poolConfig = poolConfig.insertBool(config.isPoolRegistered, POOL_REGISTERED_OFFSET);
        }
        if (cherryPicks & INITIALIZED_FLAG != 0) {
            poolConfig = poolConfig.insertBool(config.isPoolInitialized, POOL_INITIALIZED_OFFSET);
        }
        if (cherryPicks & RECOVERY_MODE_FLAG != 0) {
            poolConfig = poolConfig.insertBool(config.isPoolInRecoveryMode, POOL_RECOVERY_MODE_OFFSET);
        }
        if (cherryPicks & STATIC_SWAP_FEE_FLAG != 0) {
            poolConfig = poolConfig.insertUint(
                config.staticSwapFeePercentage / FEE_SCALING_FACTOR,
                STATIC_SWAP_FEE_OFFSET,
                FEE_BITLENGTH
            );
        }
        if (cherryPicks & POOL_CREATOR_FEE_FLAG != 0) {
            poolConfig = poolConfig.insertUint(
                config.poolCreatorFeePercentage / FEE_SCALING_FACTOR,
                POOL_CREATOR_FEE_OFFSET,
                FEE_BITLENGTH
            );
        }
        if (cherryPicks & TOKEN_DECIMALS_FLAG != 0) {
            poolConfig = poolConfig.insertUint(
                config.tokenDecimalDiffs,
                DECIMAL_SCALING_FACTORS_OFFSET,
                _TOKEN_DECIMAL_DIFFS_BITLENGTH
            );
        }
        if (cherryPicks & HOOKS_FLAG != 0) {
            {
                poolConfig = poolConfig
                    .insertBool(config.hooks.shouldCallBeforeSwap, BEFORE_SWAP_OFFSET)
                    .insertBool(config.hooks.shouldCallAfterSwap, AFTER_SWAP_OFFSET)
                    .insertBool(config.hooks.shouldCallBeforeAddLiquidity, BEFORE_ADD_LIQUIDITY_OFFSET)
                    .insertBool(config.hooks.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET);
            }

            {
                poolConfig = poolConfig
                    .insertBool(config.hooks.shouldCallBeforeRemoveLiquidity, BEFORE_REMOVE_LIQUIDITY_OFFSET)
                    .insertBool(config.hooks.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET)
                    .insertBool(config.hooks.shouldCallBeforeInitialize, BEFORE_INITIALIZE_OFFSET);
            }
            {
                poolConfig = poolConfig
                    .insertBool(config.hooks.shouldCallAfterInitialize, AFTER_INITIALIZE_OFFSET)
                    .insertBool(config.hooks.shouldCallComputeDynamicSwapFee, DYNAMIC_SWAP_FEE_OFFSET);
            }
        }

        if (cherryPicks & LIQUIDITY_FLAG != 0) {
            poolConfig = poolConfig
                .insertBool(config.liquidityManagement.disableUnbalancedLiquidity, UNBALANCED_LIQUIDITY_OFFSET)
                .insertBool(config.liquidityManagement.enableAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET)
                .insertBool(config.liquidityManagement.enableRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        }

        return PoolConfigBits.wrap(poolConfig);
    }

    function fromPoolConfig(PoolConfig memory config) internal pure returns (PoolConfigBits) {
        bytes32 configBits = bytes32(0);

        // Stack too deep.
        {
            configBits = configBits
                .insertBool(config.isPoolRegistered, POOL_REGISTERED_OFFSET)
                .insertBool(config.isPoolInitialized, POOL_INITIALIZED_OFFSET)
                .insertBool(config.isPoolPaused, POOL_PAUSED_OFFSET)
                .insertBool(config.isPoolInRecoveryMode, POOL_RECOVERY_MODE_OFFSET);
        }

        {
            configBits = configBits.insertBool(config.hooks.shouldCallBeforeSwap, BEFORE_SWAP_OFFSET).insertBool(
                config.hooks.shouldCallAfterSwap,
                AFTER_SWAP_OFFSET
            );
        }

        {
            configBits = configBits
                .insertBool(config.hooks.shouldCallBeforeAddLiquidity, BEFORE_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.hooks.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.hooks.shouldCallBeforeRemoveLiquidity, BEFORE_REMOVE_LIQUIDITY_OFFSET)
                .insertBool(config.hooks.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.hooks.shouldCallBeforeInitialize, BEFORE_INITIALIZE_OFFSET)
                .insertBool(config.hooks.shouldCallAfterInitialize, AFTER_INITIALIZE_OFFSET)
                .insertBool(config.hooks.shouldCallComputeDynamicSwapFee, DYNAMIC_SWAP_FEE_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.liquidityManagement.disableUnbalancedLiquidity, UNBALANCED_LIQUIDITY_OFFSET)
                .insertBool(config.liquidityManagement.enableAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET)
                .insertBool(config.liquidityManagement.enableRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        }
        {
            configBits = configBits
                .insertUint(config.staticSwapFeePercentage / FEE_SCALING_FACTOR, STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH)
                .insertUint(
                    config.poolCreatorFeePercentage / FEE_SCALING_FACTOR,
                    POOL_CREATOR_FEE_OFFSET,
                    FEE_BITLENGTH
                );
        }

        return
            PoolConfigBits.wrap(
                configBits
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
        PoolConfig memory config,
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

    function toPoolConfig(
        PoolConfigBits config,
        uint16 cherryPicks
    ) internal pure returns (PoolConfig memory poolConfig) {
        bytes32 rawConfig = PoolConfigBits.unwrap(config);
        uint16 picked = cherryPicks;

        if (cherryPicks & PAUSED_FLAG != 0) {
            poolConfig.isPoolPaused = rawConfig.decodeBool(POOL_PAUSED_OFFSET);
            picked -= PAUSED_FLAG;
            if (picked == 0) {
                return poolConfig;
            }
        }
        if (cherryPicks & PAUSE_WINDOW_FLAG != 0) {
            poolConfig.pauseWindowEndTime = rawConfig.decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
            picked -= PAUSE_WINDOW_FLAG;
            if (picked == 0) {
                return poolConfig;
            }
        }

        if (cherryPicks & REGISTERED_FLAG != 0) {
            poolConfig.isPoolRegistered = rawConfig.decodeBool(POOL_REGISTERED_OFFSET);
        }
        if (cherryPicks & INITIALIZED_FLAG != 0) {
            poolConfig.isPoolInitialized = rawConfig.decodeBool(POOL_INITIALIZED_OFFSET);
        }
        if (cherryPicks & RECOVERY_MODE_FLAG != 0) {
            poolConfig.isPoolInRecoveryMode = rawConfig.decodeBool(POOL_RECOVERY_MODE_OFFSET);
        }
        if (cherryPicks & STATIC_SWAP_FEE_FLAG != 0) {
            poolConfig.staticSwapFeePercentage =
                rawConfig.decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) *
                FEE_SCALING_FACTOR;
        }
        if (cherryPicks & POOL_CREATOR_FEE_FLAG != 0) {
            poolConfig.poolCreatorFeePercentage =
                rawConfig.decodeUint(POOL_CREATOR_FEE_OFFSET, FEE_BITLENGTH) *
                FEE_SCALING_FACTOR;
        }
        if (cherryPicks & TOKEN_DECIMALS_FLAG != 0) {
            poolConfig.tokenDecimalDiffs = rawConfig.decodeUint(
                DECIMAL_SCALING_FACTORS_OFFSET,
                _TOKEN_DECIMAL_DIFFS_BITLENGTH
            );
        }
        if (cherryPicks & HOOKS_FLAG != 0) {
            poolConfig.hooks = PoolHooks({
                shouldCallBeforeInitialize: rawConfig.decodeBool(BEFORE_INITIALIZE_OFFSET),
                shouldCallAfterInitialize: rawConfig.decodeBool(AFTER_INITIALIZE_OFFSET),
                shouldCallBeforeAddLiquidity: rawConfig.decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET),
                shouldCallAfterAddLiquidity: rawConfig.decodeBool(AFTER_ADD_LIQUIDITY_OFFSET),
                shouldCallBeforeRemoveLiquidity: rawConfig.decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET),
                shouldCallAfterRemoveLiquidity: rawConfig.decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET),
                shouldCallComputeDynamicSwapFee: rawConfig.decodeBool(DYNAMIC_SWAP_FEE_OFFSET),
                shouldCallBeforeSwap: rawConfig.decodeBool(BEFORE_SWAP_OFFSET),
                shouldCallAfterSwap: rawConfig.decodeBool(AFTER_SWAP_OFFSET)
            });
        }
        if (cherryPicks & LIQUIDITY_FLAG != 0) {
            poolConfig.liquidityManagement = LiquidityManagement({
                disableUnbalancedLiquidity: rawConfig.decodeBool(UNBALANCED_LIQUIDITY_OFFSET),
                enableAddLiquidityCustom: rawConfig.decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET),
                enableRemoveLiquidityCustom: rawConfig.decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET)
            });
        }
    }

    function toPoolConfig(PoolConfigBits config) internal pure returns (PoolConfig memory) {
        bytes32 rawConfig = PoolConfigBits.unwrap(config);

        // Calling the functions (in addition to costing more gas), causes an obscure form of stack error (Yul errors).
        return
            PoolConfig({
                isPoolRegistered: rawConfig.decodeBool(POOL_REGISTERED_OFFSET),
                isPoolInitialized: rawConfig.decodeBool(POOL_INITIALIZED_OFFSET),
                isPoolPaused: rawConfig.decodeBool(POOL_PAUSED_OFFSET),
                isPoolInRecoveryMode: rawConfig.decodeBool(POOL_RECOVERY_MODE_OFFSET),
                staticSwapFeePercentage: rawConfig.decodeUint(STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH) *
                    FEE_SCALING_FACTOR,
                poolCreatorFeePercentage: rawConfig.decodeUint(POOL_CREATOR_FEE_OFFSET, FEE_BITLENGTH) *
                    FEE_SCALING_FACTOR,
                tokenDecimalDiffs: rawConfig.decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH),
                pauseWindowEndTime: rawConfig.decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH),
                hooks: PoolHooks({
                    shouldCallBeforeInitialize: rawConfig.decodeBool(BEFORE_INITIALIZE_OFFSET),
                    shouldCallAfterInitialize: rawConfig.decodeBool(AFTER_INITIALIZE_OFFSET),
                    shouldCallBeforeAddLiquidity: rawConfig.decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET),
                    shouldCallAfterAddLiquidity: rawConfig.decodeBool(AFTER_ADD_LIQUIDITY_OFFSET),
                    shouldCallBeforeRemoveLiquidity: rawConfig.decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET),
                    shouldCallAfterRemoveLiquidity: rawConfig.decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET),
                    shouldCallComputeDynamicSwapFee: rawConfig.decodeBool(DYNAMIC_SWAP_FEE_OFFSET),
                    shouldCallBeforeSwap: rawConfig.decodeBool(BEFORE_SWAP_OFFSET),
                    shouldCallAfterSwap: rawConfig.decodeBool(AFTER_SWAP_OFFSET)
                }),
                liquidityManagement: LiquidityManagement({
                    disableUnbalancedLiquidity: rawConfig.decodeBool(UNBALANCED_LIQUIDITY_OFFSET),
                    enableAddLiquidityCustom: rawConfig.decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET),
                    enableRemoveLiquidityCustom: rawConfig.decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET)
                })
            });
    }
}
