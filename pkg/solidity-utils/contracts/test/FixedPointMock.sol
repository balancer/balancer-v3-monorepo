// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "../math/FixedPoint.sol";

contract FixedPointMock {
    function powDown(uint256 x, uint256 y) public pure returns (uint256) {
        return FixedPoint.powDown(x, y);
    }

    function powUp(uint256 x, uint256 y) public pure returns (uint256) {
        return FixedPoint.powUp(x, y);
    }
}
