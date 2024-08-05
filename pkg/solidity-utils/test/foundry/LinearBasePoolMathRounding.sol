// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../../contracts/test/BasePoolMathMock.sol";
import "../../contracts/test/LinearBasePoolMathMock.sol";
import "./utils/BasePoolMathRoundingTest.sol";

contract LinearBasePoolMathRoundingTest is BasePoolMathRoundingTest {
    function setUp() public override {
        BasePoolMathRoundingTest.setUp();
    }

    function createMathMock() internal override returns (BasePoolMathMock) {
        return BasePoolMathMock(address(new LinearBasePoolMathMock()));
    }
}
