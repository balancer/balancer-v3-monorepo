// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Library of helper functions to convert fixed-sized array types to dynamic arrays in tests.
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
}
