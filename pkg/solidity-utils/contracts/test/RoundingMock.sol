// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FixedPoint } from "../math/FixedPoint.sol";

library RoundingMock {
    function mockMul(uint256 a, uint256 b, bool roundUp) internal pure returns (uint256) {
        if (roundUp) {
            return FixedPoint.mulUp(a, b);
        } else {
            return FixedPoint.mulDown(a, b);
        }
    }

    function mockDiv(uint256 a, uint256 b, bool roundUp) internal pure returns (uint256) {
        if (roundUp) {
            return FixedPoint.divUp(a, b);
        } else {
            return FixedPoint.divDown(a, b);
        }
    }

    function mockDivRaw(uint256 a, uint256 b, bool roundUp) internal pure returns (uint256) {
        if (roundUp) {
            return FixedPoint.divUpRaw(a, b);
        } else {
            return divDownRaw(a, b);
        }
    }

    function mockPow(uint256 x, uint256 y, bool roundUp) internal pure returns (uint256) {
        if (roundUp) {
            return FixedPoint.powUp(x, y);
        } else {
            return FixedPoint.powDown(x, y);
        }
    }

    function divDownRaw(uint256 a, uint256 b) private pure returns (uint256) {
        return a / b;
    }
}
