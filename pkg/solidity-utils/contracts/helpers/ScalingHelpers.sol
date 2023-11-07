// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { FixedPoint } from "../math/FixedPoint.sol";
import { InputHelpers } from "./InputHelpers.sol";

/**
 * @dev To simplify Pool logic, all token balances and amounts are normalized to behave as if the token had
 * 18 decimals. When comparing DAI (18 decimals) and USDC (6 decimals), 1 USDC and 1 DAI would both be
 * represented as 1e18. This allows us to not consider differences in token decimals in the internal Pool
 * math, simplifying it greatly.
 */
library ScalingHelpers {
    /***************************************************************************
                                Single Value Functions
    ***************************************************************************/

    /**
     * @dev Applies `scalingFactor` to `amount`, resulting in a larger or equal value depending on whether it needed
     * scaling or not. The result is rounded down.
     */
    function upscaleDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulDown(amount, scalingFactor);
    }

    /**
     * @dev Applies `scalingFactor` to `amount`, resulting in a larger or equal value depending on whether it needed
     * scaling or not. The result is rounded up.
     */
    function upscaleUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulUp(amount, scalingFactor);
    }

    /**
     * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
     * whether it needed scaling or not. The result is rounded down.
     */
    function downscaleDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divDown(amount, scalingFactor);
    }

    /**
     * @dev Reverses the `scalingFactor` applied to `amount`, resulting in a smaller or equal value depending on
     * whether it needed scaling or not. The result is rounded up.
     */
    function downscaleUp(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divUp(amount, scalingFactor);
    }

    /***************************************************************************
                                    Array Functions
    ***************************************************************************/

    /**
     * @dev Same as `upscaleDown`, but for an entire array. This function does not return anything,
     * but instead *mutates* the `amounts` array.
     */
    function upscaleDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.mulDown(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @dev Same as `upscaleUp`, but for an entire array. This function does not return anything,
     * but instead *mutates* the `amounts` array.
     */
    function upscaleUpArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.mulUp(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @dev Same as `downscaleDown`, but for an entire array. This function does not return anything, but instead
     * *mutates* the `amounts` array.
     */
    function downscaleDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.divDown(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @dev Same as `downscaleUp`, but for an entire array. This function does not return anything, but instead
     * *mutates* the `amounts` array.
     */
    function downscaleUpArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.divUp(amounts[i], scalingFactors[i]);
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
