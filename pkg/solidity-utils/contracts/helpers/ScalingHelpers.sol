// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FixedPoint } from "../math/FixedPoint.sol";
import { InputHelpers } from "./InputHelpers.sol";

/**
 * @notice Helper functions to apply/undo token decimal and rate adjustments, rounding in the direction indicated.
 * @dev To simplify Pool logic, all token balances and amounts are normalized to behave as if the token had
 * 18 decimals. When comparing DAI (18 decimals) and USDC (6 decimals), 1 USDC and 1 DAI would both be
 * represented as 1e18. This allows us to not consider differences in token decimals in the internal Pool
 * math, simplifying it greatly.
 *
 * The Vault does not support tokens with more than 18 decimals (see `_MAX_TOKEN_DECIMALS` in `VaultStorage`),
 * or tokens that do not implement `IERC20Metadata.decimals`.
 *
 * These helpers can also be used to scale amounts by other 18-decimal floating point values, such as rates.
 */
library ScalingHelpers {
    using FixedPoint for *;
    using ScalingHelpers for uint256;

    /***************************************************************************
                                Single Value Functions
    ***************************************************************************/

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded down
     */
    function toScaled18ApplyRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return (amount * scalingFactor).mulDown(tokenRate);
    }

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded up
     */
    function toScaled18ApplyRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return (amount * scalingFactor).mulUp(tokenRate);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded down
     */
    function toRawUndoRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last. Scaling factor is not a FP18, but a FP18 normalized by FP(1).
        // `scalingFactor * tokenRate` is a precise FP18, so there is no rounding direction here.
        return FixedPoint.divDown(amount, scalingFactor * tokenRate);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor, `10^(18-tokenDecimals)`
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded up
     */
    function toRawUndoRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last. Scaling factor is not a FP18, but a FP18 normalized by FP(1).
        // `scalingFactor * tokenRate` is a precise FP18, so there is no rounding direction here.
        return FixedPoint.divUp(amount, scalingFactor * tokenRate);
    }

    /***************************************************************************
                                    Array Functions
    ***************************************************************************/

    function copyToArray(uint256[] memory from, uint256[] memory to) internal pure {
        uint256 length = from.length;
        InputHelpers.ensureInputLengthMatch(length, to.length);

        assembly ("memory-safe") {
            mcopy(add(to, 0x20), add(from, 0x20), mul(length, 0x20))
        }
    }

    /**
     * @notice Same as `toScaled18ApplyRateRoundDown`, but for an entire array.
     * @dev This function does not return anything, but instead *mutates* the `amounts` array.
     * @param amounts Amounts to be scaled up to 18 decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     * @param tokenRates The token rate scaling factors, sorted in token registration order
     */
    function toScaled18ApplyRateRoundDownArray(
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length, tokenRates.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = amounts[i].toScaled18ApplyRateRoundDown(scalingFactors[i], tokenRates[i]);
        }
    }

    /**
     * @notice Same as `toScaled18ApplyRateRoundDown`, but returns a new array, leaving the original intact.
     * @param amounts Amounts to be scaled up to 18 decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     * @param tokenRates The token rate scaling factors, sorted in token registration order
     * @return results The final 18 decimal results, sorted in token registration order, rounded down
     */
    function copyToScaled18ApplyRateRoundDownArray(
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure returns (uint256[] memory) {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length, tokenRates.length);
        uint256[] memory amountsScaled18 = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            amountsScaled18[i] = amounts[i].toScaled18ApplyRateRoundDown(scalingFactors[i], tokenRates[i]);
        }

        return amountsScaled18;
    }

    /**
     * @notice Same as `toScaled18ApplyRateRoundUp`, but for an entire array.
     * @dev This function does not return anything, but instead *mutates* the `amounts` array.
     * @param amounts Amounts to be scaled up to 18 decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     * @param tokenRates The token rate scaling factors, sorted in token registration order
     */
    function toScaled18ApplyRateRoundUpArray(
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length, tokenRates.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = amounts[i].toScaled18ApplyRateRoundUp(scalingFactors[i], tokenRates[i]);
        }
    }

    /**
     * @notice Same as `toScaled18ApplyRateRoundUp`, but returns a new array, leaving the original intact.
     * @param amounts Amounts to be scaled up to 18 decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     * @param tokenRates The token rate scaling factors, sorted in token registration order
     * @return The final 18 decimal results, sorted in token registration order, rounded up
     */
    function copyToScaled18ApplyRateRoundUpArray(
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure returns (uint256[] memory) {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length, tokenRates.length);
        uint256[] memory amountsScaled18 = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            amountsScaled18[i] = amounts[i].toScaled18ApplyRateRoundUp(scalingFactors[i], tokenRates[i]);
        }

        return amountsScaled18;
    }

    /**
     * @notice Rounds up a rate informed by a rate provider.
     * @dev Rates calculated by an external rate provider have rounding errors. Intuitively, a rate provider
     * rounds the rate down so the pool math is executed with conservative amounts. However, when upscaling or
     * downscaling the amount out, the rate should be rounded up to make sure the amounts scaled are conservative.
     */
    function computeRateRoundUp(uint256 rate) internal pure returns (uint256) {
        uint256 roundedRate;
        // If rate is divisible by FixedPoint.ONE, roundedRate and rate will be equal. It means that rate has 18 zeros,
        // so there's no rounding issue and the rate should not be rounded up.
        unchecked {
            roundedRate = (rate / FixedPoint.ONE) * FixedPoint.ONE;
        }
        return roundedRate == rate ? rate : rate + 1;
    }
}
