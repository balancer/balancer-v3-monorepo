// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { FungibilityTest } from "@balancer-labs/v3-vault/test/foundry/Fungibility.t.sol";

import { Gyro2ClpPoolDeployer } from "./utils/Gyro2ClpPoolDeployer.sol";

contract FungibilityGyro2CLPTest is FungibilityTest, Gyro2ClpPoolDeployer {
    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by FungibilityTest.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyro2ClpPool(tokens, rateProviders, label, vault, lp);
    }
}
