// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

// solhint-disable

library ArrayHelpers {
    // solhint-disable
    function toMemoryArray(address[2] memory array) internal pure returns (address[] memory) {
        address[] memory ret = new address[](2);
        ret[0] = array[0];
        ret[1] = array[1];
        return ret;
    }
}
