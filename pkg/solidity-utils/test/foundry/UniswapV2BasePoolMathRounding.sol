// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "../../contracts/test/BasePoolMathMock.sol";
import "../../contracts/test/UniswapV2BasePoolMathMock.sol";
import "./utils/BasePoolMathRoundingTest.sol";

contract UniswapV2BasePoolMathRoundingTest is BasePoolMathRoundingTest {
    function setUp() public override {
        // The delta is dependent on the implementations of computeInvariant and computeBalances.
        // For UniswapV2, the delta is slightly higher due to the sqrt operation.
        delta = 1e9;
        BasePoolMathRoundingTest.setUp();
    }

    function createMathMock() internal override returns (BasePoolMathMock) {
        return BasePoolMathMock(address(new UniswapV2BasePoolMathMock()));
    }
}
