// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Library of helper functions used to convert between fixed size and dynamic arrays of various types.
library ArrayHelpers {
    function toMemoryArray(address[1] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](1);
        ret[0] = array[0];
        return ret;
    }

    function toMemoryArray(address[2] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    function toMemoryArray(address[3] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](3);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        return ret;
    }

    function toMemoryArray(address payable[1] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](1);
        ret[0] = array[0];
        return ret;
    }

    function toMemoryArray(address payable[2] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    function toMemoryArray(address payable[3] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](3);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        return ret;
    }

    function toMemoryArray(uint256[1] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](1);
        ret[0] = array[0];
        return ret;
    }

    function toMemoryArray(uint256[2] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }

    function toMemoryArray(uint256[3] memory array) internal pure returns (uint256[] memory) {
        uint256[] memory ret = new uint256[](3);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        return ret;
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
        for (uint256 i = 0; i < values.length; ++i) {
            signedValues[i] = positive ? int256(values[i]) : -int256(values[i]);
        }
    }

    /// @dev Returns addresses as an array IERC20[] memory
    function asIERC20(address[] memory addresses) internal pure returns (IERC20[] memory tokens) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tokens := addresses
        }
    }
}
