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

    function toMemoryArray(address[4] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](4);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        return ret;
    }

    function toMemoryArray(address[5] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](5);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        return ret;
    }

    function toMemoryArray(address[6] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](6);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        ret[5] = array[5];
        return ret;
    }

    function toMemoryArray(address[7] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](7);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        ret[5] = array[5];
        ret[6] = array[6];
        return ret;
    }

    function toMemoryArray(address[8] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](8);
        ret[0] = array[0];
        ret[1] = array[1];
        ret[2] = array[2];
        ret[3] = array[3];
        ret[4] = array[4];
        ret[5] = array[5];
        ret[6] = array[6];
        ret[7] = array[7];
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
