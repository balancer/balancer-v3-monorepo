// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/FixedPoint.sol";

contract FixedPointMock {
    function powDown(uint256 x, uint256 y) public pure returns (uint256) {
        return FixedPoint.powDown(x, y);
    }

    function powUp(uint256 x, uint256 y) public pure returns (uint256) {
        return FixedPoint.powUp(x, y);
    }

    function mulDown(uint256 a, uint256 b) public pure returns (uint256) {
        return FixedPoint.mulDown(a, b);
    }

    function mulUp(uint256 a, uint256 b) public pure returns (uint256) {
        return FixedPoint.mulUp(a, b);
    }

    function divDown(uint256 a, uint256 b) public pure returns (uint256) {
        return FixedPoint.divDown(a, b);
    }

    function divUp(uint256 a, uint256 b) public pure returns (uint256) {
        return FixedPoint.divUp(a, b);
    }

    function complement(uint256 x) public pure returns (uint256) {
        return FixedPoint.complement(x);
    }
}
