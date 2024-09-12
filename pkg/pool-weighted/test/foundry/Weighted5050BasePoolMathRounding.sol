// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { BasePoolMathRoundingTest } from "@balancer-labs/v3-vault/test/foundry/BasePoolMathRoundingTest.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BasePoolMathMock } from "@balancer-labs/v3-vault/contracts/test/BasePoolMathMock.sol";

import { WeightedBasePoolMathMock } from "../../contracts/test/WeightedBasePoolMathMock.sol";
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

contract Weighted5050BasePoolMathRounding is BasePoolMathRoundingTest, WeightedPoolContractsDeployer {
    using ArrayHelpers for *;

    function setUp() public override {
        // The delta is dependent on the implementations of computeInvariant and computeBalances.
        // For Weighted5050, the delta is slightly higher
        delta = 1e4;

        BasePoolMathRoundingTest.setUp();
    }

    function createMathMock() internal override returns (BasePoolMathMock) {
        return BasePoolMathMock(address(deployWeightedBasePoolMathMock([uint256(50e16), 50e16].toMemoryArray())));
    }
}
