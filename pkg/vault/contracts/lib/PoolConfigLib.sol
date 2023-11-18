// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// solhint-disable-next-line max-line-length
import { PoolConfig, PoolCallbacks, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store entire configuration of the pool
type PoolConfigBits is bytes32;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    /// @dev Pool does not support adding liquidity proportionally.
    error DoesNotSupportAddLiquidityProportional();

    /// @dev Pool does not support adding liquidity with unbalanced tokens in.
    error DoesNotSupportAddLiquidityUnbalanced();

    /// @dev Pool does not support adding liquidity with a single asset, specifying exact pool tokens out.
    error DoesNotSupportAddLiquiditySingleTokenExactOut();

    /// @dev Pool does not support adding liquidity with a customized input.
    error DoesNotSupportAddLiquidityCustom();

    /// @dev Pool does not support removing liquidity proportionally.
    error DoesNotSupportRemoveLiquidityProportional();

    /// @dev Pool does not support removing liquidity with unbalanced tokens out.
    error DoesNotSupportRemoveLiquidityUnbalanced();

    /// @dev Pool does not support removing liquidity with a single asset, specifying exact pool tokens in.
    error DoesNotSupportRemoveLiquiditySingleTokenExactIn();

    /// @dev
    error DoesNotSupportRemoveLiquiditySingleTokenExactOut();

    /// @dev Pool does not support removing liquidity with a customized input.
    error DoesNotSupportRemoveLiquidityCustom();

    using WordCodec for bytes32;
    using SafeCast for uint256;

    // Bit offsets for pool config
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = POOL_REGISTERED_OFFSET + 1;
    uint8 public constant POOL_PAUSED_OFFSET = POOL_INITIALIZED_OFFSET + 1;
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = POOL_PAUSED_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;

    // Supported liquidity API bit offsets
    uint8 public constant ADD_LIQUIDITY_PROPORTIONAL_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET = ADD_LIQUIDITY_PROPORTIONAL_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_UNBALANCED_OFFSET = ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = ADD_LIQUIDITY_UNBALANCED_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET = ADD_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET = REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET =
        REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET + 1;

    uint8 public constant STATIC_SWAP_FEE_OFFSET = REMOVE_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint8 public constant DECIMAL_SCALING_FACTORS_OFFSET = STATIC_SWAP_FEE_OFFSET + _STATIC_SWAP_FEE_BITLENGTH;
    uint8 public constant PAUSE_WINDOW_END_TIME_OFFSET =
        DECIMAL_SCALING_FACTORS_OFFSET + _TOKEN_DECIMAL_DIFFS_BITLENGTH;

    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint8 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;

    // A fee can never be larger than FixedPoint.ONE, which fits in 60 bits
    uint8 private constant _STATIC_SWAP_FEE_BITLENGTH = 64;
    uint8 private constant _TIMESTAMP_BITLENGTH = 32;

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function isPoolPaused(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_PAUSED_OFFSET);
    }

    function hasDynamicSwapFee(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(DYNAMIC_SWAP_FEE_OFFSET);
    }

    function getStaticSwapFeePercentage(PoolConfigBits config) internal pure returns (uint64) {
        return PoolConfigBits.unwrap(config).decodeUint(STATIC_SWAP_FEE_OFFSET, _STATIC_SWAP_FEE_BITLENGTH).toUint64();
    }

    function getTokenDecimalDiffs(PoolConfigBits config) internal pure returns (uint24) {
        return
            PoolConfigBits
                .unwrap(config)
                .decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH)
                .toUint24();
    }

    function getPauseWindowEndTime(PoolConfigBits config) internal pure returns (uint32) {
        return PoolConfigBits.unwrap(config).decodeUint(PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH).toUint32();
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

    function supportsAddLiquidityProportional(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_PROPORTIONAL_OFFSET);
    }

    function requireSupportsAddLiquidityProportional(PoolConfigBits config) internal pure {
        if (config.supportsAddLiquidityProportional() == false) {
            revert DoesNotSupportAddLiquidityProportional();
        }
    }

    function supportsAddLiquiditySingleTokenExactOut(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET);
    }

    function requireSupportsAddLiquiditySingleTokenExactOut(PoolConfigBits config) internal pure {
        if (config.supportsAddLiquiditySingleTokenExactOut() == false) {
            revert DoesNotSupportAddLiquiditySingleTokenExactOut();
        }
    }

    function supportsAddLiquidityUnbalanced(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_UNBALANCED_OFFSET);
    }

    function requireSupportsAddLiquidityUnbalanced(PoolConfigBits config) internal pure {
        if (config.supportsAddLiquidityUnbalanced() == false) {
            revert DoesNotSupportAddLiquidityUnbalanced();
        }
    }

    function supportsAddLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireSupportsAddLiquidityCustom(PoolConfigBits config) internal pure {
        if (config.supportsAddLiquidityCustom() == false) {
            revert DoesNotSupportAddLiquidityCustom();
        }
    }

    function supportsRemoveLiquidityProportional(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET);
    }

    function requireSupportsRemoveLiquidityProportional(PoolConfigBits config) internal pure {
        if (config.supportsRemoveLiquidityProportional() == false) {
            revert DoesNotSupportRemoveLiquidityProportional();
        }
    }

    function supportsRemoveLiquiditySingleTokenExactIn(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET);
    }

    function requireSupportsRemoveLiquiditySingleTokenExactIn(PoolConfigBits config) internal pure {
        if (config.supportsRemoveLiquiditySingleTokenExactIn() == false) {
            revert DoesNotSupportRemoveLiquiditySingleTokenExactIn();
        }
    }

    function supportsRemoveLiquiditySingleTokenExactOut(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET);
    }

    function requireSupportsRemoveLiquiditySingleTokenExactOut(PoolConfigBits config) internal pure {
        if (config.supportsRemoveLiquiditySingleTokenExactOut() == false) {
            revert DoesNotSupportRemoveLiquiditySingleTokenExactOut();
        }
    }

    function supportsRemoveLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_CUSTOM_OFFSET);
    }

    function requireSupportsRemoveLiquidityCustom(PoolConfigBits config) internal pure {
        if (config.supportsRemoveLiquidityCustom() == false) {
            revert DoesNotSupportRemoveLiquidityCustom();
        }
    }

    function fromPoolConfig(PoolConfig memory config) internal pure returns (PoolConfigBits) {
        bytes32 configBits = bytes32(0);

        // Stack too deep.
        {
            configBits = configBits
                .insertBool(config.isPoolRegistered, POOL_REGISTERED_OFFSET)
                .insertBool(config.isPoolInitialized, POOL_INITIALIZED_OFFSET)
                .insertBool(config.isPoolPaused, POOL_PAUSED_OFFSET)
                .insertBool(config.hasDynamicSwapFee, DYNAMIC_SWAP_FEE_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.callbacks.shouldCallAfterSwap, AFTER_SWAP_OFFSET)
                .insertBool(config.callbacks.shouldCallBeforeAddLiquidity, BEFORE_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.callbacks.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.callbacks.shouldCallBeforeRemoveLiquidity, BEFORE_REMOVE_LIQUIDITY_OFFSET)
                .insertBool(config.callbacks.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(
                    config.liquidityManagement.supportsAddLiquidityProportional,
                    ADD_LIQUIDITY_PROPORTIONAL_OFFSET
                )
                .insertBool(
                    config.liquidityManagement.supportsAddLiquiditySingleTokenExactOut,
                    ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET
                )
                .insertBool(config.liquidityManagement.supportsAddLiquidityUnbalanced, ADD_LIQUIDITY_UNBALANCED_OFFSET)
                .insertBool(config.liquidityManagement.supportsAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(
                    config.liquidityManagement.supportsRemoveLiquidityProportional,
                    REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET
                )
                .insertBool(
                    config.liquidityManagement.supportsRemoveLiquiditySingleTokenExactIn,
                    REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET
                )
                .insertBool(
                    config.liquidityManagement.supportsRemoveLiquiditySingleTokenExactOut,
                    REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET
                )
                .insertBool(config.liquidityManagement.supportsRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        }

        return
            PoolConfigBits.wrap(
                configBits
                    .insertUint(
                        config.tokenDecimalDiffs,
                        DECIMAL_SCALING_FACTORS_OFFSET,
                        _TOKEN_DECIMAL_DIFFS_BITLENGTH
                    )
                    .insertUint(config.staticSwapFeePercentage, STATIC_SWAP_FEE_OFFSET, _STATIC_SWAP_FEE_BITLENGTH)
                    .insertUint(config.pauseWindowEndTime, PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH)
            );
    }

    // Convert from an array of decimal differences, to the encoded 24 bit value (only uses bottom 20 bits).
    function toTokenDecimalDiffs(uint8[] memory tokenDecimalDiffs) internal pure returns (uint24) {
        bytes32 value;

        for (uint256 i = 0; i < tokenDecimalDiffs.length; i++) {
            value = value.insertUint(tokenDecimalDiffs[i], i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);
        }

        return uint256(value).toUint24();
    }

    function getScalingFactors(PoolConfig memory config, uint256 numTokens) internal pure returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](numTokens);

        bytes32 tokenDecimalDiffs = bytes32(uint256(config.tokenDecimalDiffs));

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 decimalDiff = tokenDecimalDiffs.decodeUint(i * _DECIMAL_DIFF_BITLENGTH, _DECIMAL_DIFF_BITLENGTH);

            // This is equivalent to `10**(18+decimalsDifference)` but this form optimizes for 18 decimal tokens.
            scalingFactors[i] = FixedPoint.ONE * 10 ** decimalDiff;
        }

        return scalingFactors;
    }

    function toPoolConfig(PoolConfigBits config) internal pure returns (PoolConfig memory) {
        return
            PoolConfig({
                isPoolRegistered: config.isPoolRegistered(),
                isPoolInitialized: config.isPoolInitialized(),
                isPoolPaused: config.isPoolPaused(),
                hasDynamicSwapFee: config.hasDynamicSwapFee(),
                staticSwapFeePercentage: config.getStaticSwapFeePercentage(),
                tokenDecimalDiffs: config.getTokenDecimalDiffs(),
                pauseWindowEndTime: config.getPauseWindowEndTime(),
                callbacks: PoolCallbacks({
                    shouldCallBeforeAddLiquidity: config.shouldCallBeforeAddLiquidity(),
                    shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                    shouldCallBeforeRemoveLiquidity: config.shouldCallBeforeRemoveLiquidity(),
                    shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity(),
                    shouldCallAfterSwap: config.shouldCallAfterSwap()
                }),
                liquidityManagement: LiquidityManagement({
                    supportsAddLiquidityProportional: config.supportsAddLiquidityProportional(),
                    supportsAddLiquiditySingleTokenExactOut: config.supportsAddLiquiditySingleTokenExactOut(),
                    supportsAddLiquidityUnbalanced: config.supportsAddLiquidityUnbalanced(),
                    supportsAddLiquidityCustom: config.supportsAddLiquidityCustom(),
                    supportsRemoveLiquidityProportional: config.supportsRemoveLiquidityProportional(),
                    supportsRemoveLiquiditySingleTokenExactIn: config.supportsRemoveLiquiditySingleTokenExactIn(),
                    supportsRemoveLiquiditySingleTokenExactOut: config.supportsRemoveLiquiditySingleTokenExactOut(),
                    supportsRemoveLiquidityCustom: config.supportsRemoveLiquidityCustom()
                })
            });
    }

    function getPoolPausedState(PoolConfigBits config) internal pure returns (bool, uint256) {
        return (config.isPoolPaused(), config.getPauseWindowEndTime());
    }
}
