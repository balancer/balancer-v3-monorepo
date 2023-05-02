// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../math/Math.sol";

contract MathMock {
    function abs(int256 a) public pure returns (uint256) {
        return Math.abs(a);
    }
}
