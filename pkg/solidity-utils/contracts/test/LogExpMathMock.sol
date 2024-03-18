// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../math/LogExpMath.sol";

contract LogExpMathMock {
    function pow(uint256 x, uint256 y) public pure returns (uint256) {
        return LogExpMath.pow(x, y);
    }

    function exp(int256 x) public pure returns (int256) {
        return LogExpMath.exp(x);
    }

    function log(int256 arg, int256 base) public pure returns (int256) {
        return LogExpMath.log(arg, base);
    }

    function ln(int256 a) public pure returns (int256) {
        return LogExpMath.ln(a);
    }
}
