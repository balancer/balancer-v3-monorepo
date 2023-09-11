// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// solhint-disable

library ArrayHelpers {
    using SafeCast for *;

    // solhint-disable
    function toMemoryArray(address[2] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    function toMemoryArray(uint256[2] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    /**
     * @dev Casts an array of uint256 to int256, setting the sign of the result according to the `positive` flag,
     * will revert on overflow.
     */
    function safeCastToInt256(
        uint256[] memory values,
        bool positive
    ) internal pure returns (int256[] memory signedValues) {
        signedValues = new int256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            signedValues[i] = positive ? values[i].toInt256() : -(values[i].toInt256());
        }
    }

    /**
     * @dev Casts an array of uint256 to int256, setting the sign of the result according to the `positive` flag,
     * without checking whether the values fit in the signed 256 bit range.
     */
    function unsafeCastToInt256(
        uint256[] memory values,
        bool positive
    ) internal pure returns (int256[] memory signedValues) {
        signedValues = new int256[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            signedValues[i] = positive ? int256(values[i]) : -int256(values[i]);
        }
    }
}
