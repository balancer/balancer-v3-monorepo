// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FixedPoint } from "../math/FixedPoint.sol";

contract FixedPointMock {
    function mulDown(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.mulDown(a, b);
    }

    function mulUp(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.mulUp(a, b);
    }

    function divDown(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.divDown(a, b);
    }

    function divUp(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.divUp(a, b);
    }

    function divUpRaw(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.divUpRaw(a, b);
    }

    function powDown(uint256 x, uint256 y) external pure returns (uint256) {
        return FixedPoint.powDown(x, y);
    }

    function powUp(uint256 x, uint256 y) external pure returns (uint256) {
        return FixedPoint.powUp(x, y);
    }

    function complement(uint256 x) external pure returns (uint256) {
        return FixedPoint.complement(x);
    }
}
