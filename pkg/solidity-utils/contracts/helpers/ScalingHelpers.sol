// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { FixedPoint } from "../math/FixedPoint.sol";
import { InputHelpers } from "./InputHelpers.sol";

/**
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
     * @dev Applies `scalingFactor` to `amount`, resulting in a larger or equal value depending on whether it needed
     * scaling or not. The result is rounded down.
     */
    function toScaled18RoundDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulDown(amount, scalingFactor);
    }

    /**
     * @dev Applies `scalingFactor` and `tokenRate` to `amount`, resulting in a larger or equal value depending on
     * whether it needed scaling/rate adjustment or not. The result is rounded down.
     */
    function toScaled18ApplyRateRoundDown(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulDown(scalingFactor).mulDown(tokenRate);
    }

    /**
     * @dev Applies `scalingFactor` to `amount`, resulting in a larger or equal value depending on whether it needed
     * scaling or not. The result is rounded up.
     */
    function toScaled18RoundUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulUp(amount, scalingFactor);
    }

    /**
     * @dev Applies `scalingFactor` and `tokenRate` to `amount`, resulting in a larger or equal value depending on
     * whether it needed scaling/rate adjustment or not. The result is rounded up.
     */
    function toScaled18ApplyRateRoundUp(
        uint256 amount,
        uint256 scalingFactor,
        uint256 tokenRate
    ) internal pure returns (uint256) {
        return amount.mulUp(scalingFactor).mulUp(tokenRate);
    }

    /**
     * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
     * whether it needed scaling or not. The result is rounded down.
     */
    function toRawRoundDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divDown(amount, scalingFactor);
    }

    /**
     * @dev Reverses the `scalingFactor` and `tokenRate` applied to `amount`, resulting in a smaller or equal value
     * depending on whether it needed scaling/rate adjustment or not. The result is rounded down.
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
     * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
     * whether it needed scaling or not. The result is rounded up.
     */
    function toRawRoundUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divUp(amount, scalingFactor);
    }

    /**
     * @dev Reverses the `scalingFactor` and `tokenRate` applied to `amount`, resulting in a smaller or equal value
     * depending on whether it needed scaling/rate adjustment or not. The result is rounded up.
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
     * @dev Same as `toScaled18RoundDown`, but for an entire array. This function does not return anything,
     * but instead *mutates* the `amounts` array.
     */
    function toScaled18RoundDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toScaled18RoundDown(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @dev Same as `toScaled18ApplyRateRoundDown`, but for an entire array. This function does not return anything,
     * but instead *mutates* the `amounts` array.
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
     * @dev Same as `toScaled18ApplyRateRoundDown`, but returns a new array, leaving the original intact.
     */
    function copyToScaled18ApplyRateRoundDownArray(
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure returns (uint256[] memory) {
        uint256[] memory amountsScaled18 = new uint256[](amounts.length);
        updateToScaled18ApplyRateRoundDownArray(amountsScaled18, amounts, scalingFactors, tokenRates);

        return amountsScaled18;
    }

    function updateToScaled18ApplyRateRoundDownArray(
        uint256[] memory amountsScaled18,
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure {
        uint256 length = amountsScaled18.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length, tokenRates.length);

        for (uint256 i = 0; i < length; ++i) {
            amountsScaled18[i] = amounts[i].toScaled18ApplyRateRoundDown(scalingFactors[i], tokenRates[i]);
        }
    }

    /**
     * @dev Same as `toScaled18RoundUp`, but for an entire array. This function does not return anything,
     * but instead *mutates* the `amounts` array.
     */
    function toScaled18RoundUpArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toScaled18RoundUp(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @dev Same as `toScaled18ApplyRateRoundUp`, but for an entire array. This function does not return anything,
     * but instead *mutates* the `amounts` array.
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
     * @dev Same as `toScaled18ApplyRateRoundUp`, but returns a new array, leaving the original intact.
     */
    function copyToScaled18ApplyRateRoundUpArray(
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure returns (uint256[] memory) {
        uint256[] memory amountsScaled18 = new uint256[](amounts.length);
        updateToScaled18ApplyRateRoundUpArray(amountsScaled18, amounts, scalingFactors, tokenRates);

        return amountsScaled18;
    }

    function updateToScaled18ApplyRateRoundUpArray(
        uint256[] memory amountsScaled18,
        uint256[] memory amounts,
        uint256[] memory scalingFactors,
        uint256[] memory tokenRates
    ) internal pure {
        uint256 length = amountsScaled18.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length, tokenRates.length);

        for (uint256 i = 0; i < length; ++i) {
            amountsScaled18[i] = amounts[i].toScaled18ApplyRateRoundUp(scalingFactors[i], tokenRates[i]);
        }
    }

    /**
     * @dev Same as `toRawRoundDown`, but for an entire array. This function does not return anything, but instead
     * *mutates* the `amounts` array.
     */
    function toRawRoundDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toRawRoundDown(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @dev Same as `toRawRoundUp`, but for an entire array. This function does not return anything, but instead
     * *mutates* the `amounts` array.
     */
    function toRawRoundUpArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = ScalingHelpers.toRawRoundUp(amounts[i], scalingFactors[i]);
        }
    }

    function computeScalingFactor(IERC20 token) internal view returns (uint256) {
        // Tokens that don't implement the `decimals` method are not supported.
        uint256 tokenDecimals = IERC20Metadata(address(token)).decimals();

        // Tokens with more than 18 decimals are not supported.
        uint256 decimalsDifference = 18 - tokenDecimals;
        return FixedPoint.ONE * 10 ** decimalsDifference;
    }
}
