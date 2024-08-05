// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BasePoolMathMock } from "../../contracts/test/BasePoolMathMock.sol";
import { WeightedBasePoolMathMock } from "../../contracts/test/WeightedBasePoolMathMock.sol";
import { BasePoolMathRoundingTest } from "./utils/BasePoolMathRoundingTest.sol";

contract Weighted8020BasePoolMathRounding is BasePoolMathRoundingTest {
    using ArrayHelpers for *;

    function setUp() public override {
        // The delta is dependent on the implementations of computeInvariant and computeBalances.
        // For Weighted5050, the delta is slightly higher
        delta = 1e4;

        BasePoolMathRoundingTest.setUp();
    }

    function createMathMock() internal override returns (BasePoolMathMock) {
        return BasePoolMathMock(address(new WeightedBasePoolMathMock([uint256(80e16), 20e16].toMemoryArray())));
    }
}
