// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

import { GyroEclpPoolDeployer } from "./utils/GyroEclpPoolDeployer.sol";

contract LiquidityApproximationECLPTest is LiquidityApproximationTest, GyroEclpPoolDeployer {
    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();

        minSwapFeePercentage = IBasePool(swapPool).getMinimumSwapFeePercentage();

        // The invariant of E-CLP pools are smaller.
        maxAmount = 1e5 * 1e18;
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address, bytes memory) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyroEclpPool(tokens, rateProviders, label, vault, lp);
    }
}
