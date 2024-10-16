// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

import { GyroEclpPoolDeployer } from "./utils/GyroEclpPoolDeployer.sol";

contract LiquidityApproximationECLPTest is LiquidityApproximationTest, GyroEclpPoolDeployer {
    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();

        // The invariant of ECLP pools are smaller.
        maxAmount = 1e6 * 1e18;
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createEclpPool(tokens, rateProviders, label, vault, lp);
    }
}
