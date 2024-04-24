// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FixedPoint } from "../math/FixedPoint.sol";

abstract contract RoundingMock {
    enum MockRounding {
        Disabled,
        RoundDown,
        RoundUp
    }

    MockRounding public mockRounding;

    function setMockRounding(MockRounding _mockRounding) external {
        mockRounding = _mockRounding;
    }

    function mulDown(uint256 a, uint256 b) internal view returns (uint256) {
        if (mockRounding == MockRounding.RoundUp) {
            return FixedPoint.mulUp(a, b);
        } else {
            return FixedPoint.mulDown(a, b);
        }
    }

    function mulUp(uint256 a, uint256 b) internal view returns (uint256) {
        if (mockRounding == MockRounding.RoundDown) {
            return FixedPoint.mulDown(a, b);
        } else {
            return FixedPoint.mulUp(a, b);
        }
    }

    function divDown(uint256 a, uint256 b) internal view returns (uint256) {
        if (mockRounding == MockRounding.RoundUp) {
            return FixedPoint.divUp(a, b);
        } else {
            return FixedPoint.divDown(a, b);
        }
    }

    function divUp(uint256 a, uint256 b) internal view returns (uint256) {
        if (mockRounding == MockRounding.RoundDown) {
            return FixedPoint.divDown(a, b);
        } else {
            return FixedPoint.divUp(a, b);
        }
    }

    function divUpRaw(uint256 a, uint256 b) internal view returns (uint256) {
        if (mockRounding == MockRounding.RoundDown) {
            return divDownRaw(a, b);
        } else {
            return FixedPoint.divUpRaw(a, b);
        }
    }

    function powDown(uint256 x, uint256 y) internal view returns (uint256) {
        if (mockRounding == MockRounding.RoundUp) {
            return FixedPoint.powUp(x, y);
        } else {
            return FixedPoint.powDown(x, y);
        }
    }

    function powUp(uint256 x, uint256 y) internal view returns (uint256) {
        if (mockRounding == MockRounding.RoundDown) {
            return FixedPoint.powDown(x, y);
        } else {
            return FixedPoint.powUp(x, y);
        }
    }

    function divDownRaw(uint256 a, uint256 b) private pure returns (uint256) {
        return a / b;
    }
}
