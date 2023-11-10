// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PoolConfig, PoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store entire configuration of the pool
type PoolConfigBits is bytes32;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    using WordCodec for bytes32;
    using SafeCast for uint256;

    uint24 public constant SWAP_FEE_PRECISION = 1e6;

    // "reserved" bits are padding so that values fall on byte boundaries.
    // [ 200 bits |  24 bits   |  4 bits  | 4x5 bits |  2 bits  | 1 bit  | 1 bit | 1 bit  |  1 bit   | 1 bit | 1 bit ]
    // [ not used | static fee | reserved | decimals | reserved | remove |  add  |  swap  | dyn. fee | init. | reg.  ]
    // |MSB                                                                                                       LSB|

    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = 1;
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = 2;
    uint8 public constant AFTER_SWAP_OFFSET = 3;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = 4;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = 5;
    uint8 public constant DECIMAL_SCALING_FACTORS_OFFSET = 8;
    uint8 public constant STATIC_SWAP_FEE_OFFSET = DECIMAL_SCALING_FACTORS_OFFSET + _TOKEN_DECIMAL_DIFFS_BITLENGTH;

    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint8 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;

    // 24 bits represent values up to 2^24 - 1 = 16,777,216 − 1 which should be enough for the swap fee
    uint8 private constant _STATIC_SWAP_FEE_BITLENGTH = 24;

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function hasDynamicSwapFee(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(DYNAMIC_SWAP_FEE_OFFSET);
    }

    function getStaticSwapFeePercentage(PoolConfigBits config) internal pure returns (uint24) {
        return PoolConfigBits.unwrap(config).decodeUint(STATIC_SWAP_FEE_OFFSET, _STATIC_SWAP_FEE_BITLENGTH).toUint24();
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

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET);
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

    function fromPoolConfig(PoolConfig memory config) internal pure returns (PoolConfigBits) {
        // Needed to resolve "stack too deep"
        bytes32 val = bytes32(0)
            .insertBool(config.isRegisteredPool, POOL_REGISTERED_OFFSET)
            .insertBool(config.isInitializedPool, POOL_INITIALIZED_OFFSET)
            .insertBool(config.hasDynamicSwapFee, DYNAMIC_SWAP_FEE_OFFSET);

        val = val
            .insertUint(config.staticSwapFeePercentage, STATIC_SWAP_FEE_OFFSET, _STATIC_SWAP_FEE_BITLENGTH)
            .insertUint(config.tokenDecimalDiffs, DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH);

        return
            PoolConfigBits.wrap(
                val
                    .insertBool(config.callbacks.shouldCallAfterSwap, AFTER_SWAP_OFFSET)
                    .insertBool(config.callbacks.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET)
                    .insertBool(config.callbacks.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET)
            );
    }

    function toPoolConfig(PoolConfigBits config) internal pure returns (PoolConfig memory) {
        return
            PoolConfig({
                isRegisteredPool: config.isPoolRegistered(),
                isInitializedPool: config.isPoolInitialized(),
                hasDynamicSwapFee: config.hasDynamicSwapFee(),
                staticSwapFeePercentage: config.getStaticSwapFeePercentage(),
                tokenDecimalDiffs: config.getTokenDecimalDiffs(),
                callbacks: PoolCallbacks({
                    shouldCallAfterSwap: config.shouldCallAfterSwap(),
                    shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                    shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity()
                })
            });
    }
}
