// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

import { Gyro2ClpPoolDeployer } from "./utils/Gyro2ClpPoolDeployer.sol";

contract LiquidityApproximationGyroTest is LiquidityApproximationTest, Gyro2ClpPoolDeployer {
    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyro2ClpPool(tokens, rateProviders, label, vault, lp);
    }
}
