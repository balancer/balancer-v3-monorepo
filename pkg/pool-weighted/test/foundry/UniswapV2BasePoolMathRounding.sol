// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { BasePoolMathRoundingTest } from "@balancer-labs/v3-vault/test/foundry/BasePoolMathRoundingTest.sol";
import { BasePoolMathMock } from "@balancer-labs/v3-vault/contracts/test/BasePoolMathMock.sol";

import { UniswapV2BasePoolMathMock } from "./UniswapV2BasePoolMathMock.sol";

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
