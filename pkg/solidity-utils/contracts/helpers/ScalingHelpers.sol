// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { FixedPoint } from "../math/FixedPoint.sol";
import { InputHelpers } from "./InputHelpers.sol";

/**
 * @notice Helper functions to apply/undo token decimal and rate adjustments, rounding in the direction indicated.
 * @dev To simplify Pool logic, all token balances and amounts are normalized to behave as if the token had
 * 18 decimals. When comparing DAI (18 decimals) and USDC (6 decimals), 1 USDC and 1 DAI would both be
 * represented as 1e18. This allows us to not consider differences in token decimals in the internal Pool
 * math, simplifying it greatly.
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
     * @notice Applies `scalingFactor` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling or not. The result
     * is rounded down.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final 18-decimal precision result, rounded down
     */
    function toScaled18RoundDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulDown(amount, scalingFactor);
    }

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded down
     */
    function toScaled18ApplyRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulDown(scalingFactor).mulDown(tokenRate);
    }

    /**
     * @notice Applies `scalingFactor` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling or not. The result
     * is rounded up.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final 18-decimal precision result, rounded up
     */
    function toScaled18RoundUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulUp(amount, scalingFactor);
    }

    /**
     * @notice Applies `scalingFactor` and `tokenRate` to `amount`.
     * @dev This may result in a larger or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled up to 18 decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final 18-decimal precision result, rounded up
     */
    function toScaled18ApplyRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulUp(scalingFactor).mulUp(tokenRate);
    }

    /**
     * @notice Reverses the `scalingFactor` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling or not. The result
     * is rounded down.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final native decimal result, rounded down
     */
    function toRawRoundDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divDown(amount, scalingFactor);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded down.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded down
     */
    function toRawUndoRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last, and round scalingFactor * tokenRate up to divide by a larger number.
        return FixedPoint.divDown(amount, scalingFactor.mulUp(tokenRate));
    }

    /**
     * @notice Reverses the `scalingFactor` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling or not. The result
     * is rounded up.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @return result The final native decimal result, rounded up
     */
    function toRawRoundUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divUp(amount, scalingFactor);
    }

    /**
     * @notice Reverses the `scalingFactor` and `tokenRate` applied to `amount`.
     * @dev This may result in a smaller or equal value, depending on whether it needed scaling/rate adjustment or not.
     * The result is rounded up.
     *
     * @param amount Amount to be scaled down to native token decimals
     * @param scalingFactor The token decimal scaling factor
     * @param tokenRate The token rate scaling factor
     * @return result The final native decimal result, rounded up
     */
    function toRawUndoRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        // Do division last, and round scalingFactor * tokenRate down to divide by a smaller number.
        return FixedPoint.divUp(amount, scalingFactor.mulDown(tokenRate));
    }

    /***************************************************************************
                                    Array Functions
    ***************************************************************************/

    /**
     * @notice Same as `toScaled18RoundDown`, but for an entire array.
     * @dev This function does not return anything, but instead *mutates* the `amounts` array.
     * @param amounts Amounts to be scaled up to 18 decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     */
    function toScaled18RoundDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toScaled18RoundDown(amounts[i], scalingFactors[i]);
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
     * @notice Same as `toScaled18RoundUp`, but for an entire array.
     * @dev This function does not return anything, but instead *mutates* the `amounts` array.
     * @param amounts Amounts to be scaled up to 18 decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     */
    function toScaled18RoundUpArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toScaled18RoundUp(amounts[i], scalingFactors[i]);
        }
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
     * @notice Same as `toRawRoundDown`, but for an entire array.
     * @dev This function does not return anything, but instead *mutates* the `amounts` array.
     * @param amounts Amounts to be scaled down to native token decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     */
    function toRawRoundDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toRawRoundDown(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @notice Same as `toRawRoundUp`, but for an entire array.
     * @dev This function does not return anything, but instead *mutates* the `amounts` array.
     * @param amounts Amounts to be scaled down to native token decimals, sorted in token registration order
     * @param scalingFactors The token decimal scaling factors, sorted in token registration order
     */
    function toRawRoundUpArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toRawRoundUp(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @notice Convert the token `decimals` into a scaling factor.
     * @dev Called during registration, this reads the `decimals` from the token contract and constructs a conversion
     * factor to be used when scaling up to full precision and back down to native decimals.
     *
     * As noted below, the Vault does not support tokens with more than 18 decimals, or tokens that do not implement
     * `IERC20Metadata`.
     */
    function computeScalingFactor(IERC20 token) internal view returns (uint256) {
        // Tokens that don't implement the `decimals` method are not supported.
        uint256 tokenDecimals = IERC20Metadata(address(token)).decimals();

        // Tokens with more than 18 decimals are not supported.
        uint256 decimalsDifference = 18 - tokenDecimals;
        return FixedPoint.ONE * 10 ** decimalsDifference;
    }
}
