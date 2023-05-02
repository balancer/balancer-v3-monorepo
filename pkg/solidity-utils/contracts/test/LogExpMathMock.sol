// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "../math/LogExpMath.sol";

contract LogExpMathMock {
    function pow(uint256 x, uint256 y) public pure returns (uint256) {
        return LogExpMath.pow(x, y);
    }
}
