// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../../contracts/test/BasePoolMathMock.sol";
import "../../contracts/test/Weighted5050BasePoolMathMock.sol";
import "./utils/BasePoolMathRoundingTest.sol";

contract Weighted5050BasePoolMathRounding is BasePoolMathRoundingTest {
    function setUp() public override {
        // The delta is dependent on the implementations of computeInvariant and computeBalances. For Weighted5050, the delta is slightly higher
        delta = 1e4;

        BasePoolMathRoundingTest.setUp();
    }

    function createMathMock() internal override returns (BasePoolMathMock) {
        return BasePoolMathMock(address(new Weighted5050BasePoolMathMock()));
    }
}
