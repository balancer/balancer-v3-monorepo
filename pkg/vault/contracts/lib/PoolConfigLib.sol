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
    uint8 public constant POOL_INITIALIZED_OFFSET = 1;
    uint8 public constant AFTER_SWAP_OFFSET = 2;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = 3;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = 4;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = 5;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = 6;

    // Supported API bit offsets
    uint8 public constant ADD_LIQUIDITY_PROPORTIONAL_OFFSET = 7;
    uint8 public constant ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET = 8;
    uint8 public constant ADD_LIQUIDITY_UNBALANCED_OFFSET = 9;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = 10;
    uint8 public constant REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET = 11;
    uint8 public constant REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET = 12;
    uint8 public constant REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET = 13;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = 14;
    uint8 public constant POOL_RECOVERY_MODE_OFFSET = 15;

    uint8 public constant DECIMAL_SCALING_FACTORS_OFFSET = 16;

    uint256 private constant _DECIMAL_DIFF_BITLENGTH = 5;
    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint256 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function isPoolInRecoveryMode(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_RECOVERY_MODE_OFFSET);
    }

    function getTokenDecimalDiffs(PoolConfigBits config) internal pure returns (uint24) {
        return
            PoolConfigBits
                .unwrap(config)
                .decodeUint(DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH)
                .toUint24();
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
            configBits = configBits.insertBool(config.isRegisteredPool, POOL_REGISTERED_OFFSET);
            configBits = configBits.insertBool(config.isInitializedPool, POOL_INITIALIZED_OFFSET);
            configBits = configBits.insertBool(config.isPoolInRecoveryMode, POOL_RECOVERY_MODE_OFFSET);
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
                configBits.insertUint(
                    config.tokenDecimalDiffs,
                    DECIMAL_SCALING_FACTORS_OFFSET,
                    _TOKEN_DECIMAL_DIFFS_BITLENGTH
                )
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
                isRegisteredPool: config.isPoolRegistered(),
                isInitializedPool: config.isPoolInitialized(),
                isPoolInRecoveryMode: config.isPoolInRecoveryMode(),
                tokenDecimalDiffs: config.getTokenDecimalDiffs(),
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
}
