// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../helpers/ScalingHelpers.sol";

contract MockScalingHelpers {
    function upscale(uint256 amount, uint256 scalingFactor) external pure returns (uint256) {
        return _upscale(amount, scalingFactor);
    }

    function upscaleArray(uint256[] memory amounts, uint256[] memory scalingFactors)
        external
        pure
        returns (uint256[] memory)
    {
        _upscaleArray(amounts, scalingFactors);
        return amounts;
    }

    function downscaleDown(uint256 amount, uint256 scalingFactor) external pure returns (uint256) {
        return _downscaleDown(amount, scalingFactor);
    }

    function downscaleDownArray(uint256[] memory amounts, uint256[] memory scalingFactors)
        external
        pure
        returns (uint256[] memory)
    {
        _downscaleDownArray(amounts, scalingFactors);
        return amounts;
    }

    function downscaleUp(uint256 amount, uint256 scalingFactor) external pure returns (uint256) {
        return _downscaleUp(amount, scalingFactor);
    }

    function downscaleUpArray(uint256[] memory amounts, uint256[] memory scalingFactors)
        external
        pure
        returns (uint256[] memory)
    {
        _downscaleUpArray(amounts, scalingFactors);
        return amounts;
    }
}
