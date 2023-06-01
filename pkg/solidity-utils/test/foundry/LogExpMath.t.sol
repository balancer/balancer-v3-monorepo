// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../contracts/math/LogExpMath.sol";

contract LogExpMathTest is Test {
    function testPow() external {
        assertApproxEqAbs(LogExpMath.pow(2e18, 2e18), 4e18, 100);
    }
}
