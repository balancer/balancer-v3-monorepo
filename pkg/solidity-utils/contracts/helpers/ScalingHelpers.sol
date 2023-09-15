// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { FixedPoint } from "../math/FixedPoint.sol";
import { InputHelpers } from "./InputHelpers.sol";

library ScalingHelpers {
    /// To simplify Pool logic, all token balances and amounts are normalized to behave as if the token had 18 decimals.
    /// e.g. When comparing DAI (18 decimals) and USDC (6 decimals), 1 USDC and 1 DAI would both be represented as 1e18,
    /// whereas without scaling 1 USDC would be represented as 1e6.
    /// This allows us to not consider differences in token decimals in the internal Pool maths, simplifying it greatly.

    /// Single Value

    /**
     * @dev Applies `scalingFactor` to `amount`, resulting in a larger or equal value depending on whether it needed
     * scaling or not.
     */
    function upscale(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        // Upscale rounding wouldn't necessarily always go in the same direction: in a swap for example the balance of
        // token in should be rounded up, and that of token out rounded down. This is the only place where we round in
        // the same direction for all amounts, as the impact of this rounding is expected to be minimal.
        return FixedPoint.mulDown(amount, scalingFactor);
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

    /// Array

    /**
     * @dev Same as `_upscale`, but for an entire array. This function does not return anything, but instead *mutates*
     * the `amounts` array.
     */
    function upscaleArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        InputHelpers.ensureInputLengthMatch(length, scalingFactors.length);

        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.mulDown(amounts[i], scalingFactors[i]);
        }
    }

    /**
     * @dev Same as `_downscaleDown`, but for an entire array. This function does not return anything, but instead
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
     * @dev Same as `_downscaleUp`, but for an entire array. This function does not return anything, but instead
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
