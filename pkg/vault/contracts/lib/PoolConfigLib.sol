// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library PoolConfigLib {
    using WordCodec for bytes32;
    using SafeCast for *;

    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;

    function getStaticSwapFeePercentage(PoolConfig memory config) internal pure returns (uint256) {
        return config.staticSwapFeePercentageUnscaled * FEE_SCALING_FACTOR;
    }

    function setStaticSwapFeePercentage(PoolConfig memory config, uint256 value) internal pure {
        config.staticSwapFeePercentageUnscaled = (value / FEE_SCALING_FACTOR).toUint24();
    }

    function getAggregateSwapFeePercentage(PoolConfig memory config) internal pure returns (uint256) {
        return config.aggregateSwapFeePercentageUnscaled * FEE_SCALING_FACTOR;
    }

    function setAggregateSwapFeePercentage(PoolConfig memory config, uint256 value) internal pure {
        config.aggregateSwapFeePercentageUnscaled = (value / FEE_SCALING_FACTOR).toUint24();
    }

    function getAggregateYieldFeePercentage(PoolConfig memory config) internal pure returns (uint256) {
        return config.aggregateYieldFeePercentageUnscaled * FEE_SCALING_FACTOR;
    }

    function setAggregateYieldFeePercentage(PoolConfig memory config, uint256 value) internal pure {
        config.aggregateYieldFeePercentageUnscaled = (value / FEE_SCALING_FACTOR).toUint24();
    }

    function requireUnbalancedLiquidityEnabled(PoolConfig memory config) internal pure {
        if (config.disableUnbalancedLiquidity == true) {
            revert IVaultErrors.DoesNotSupportUnbalancedLiquidity();
        }
    }

    function requireAddCustomLiquidityEnabled(PoolConfig memory config) internal pure {
        if (config.enableAddLiquidityCustom == false) {
            revert IVaultErrors.DoesNotSupportAddLiquidityCustom();
        }
    }

    function requireRemoveCustomLiquidityEnabled(PoolConfig memory config) internal pure {
        if (config.enableRemoveLiquidityCustom == false) {
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
}
