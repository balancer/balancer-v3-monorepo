// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { GyroEclpPoolDeployer } from "./utils/GyroEclpPoolDeployer.sol";

contract ComputeBalanceECLPTest is BaseVaultTest, GyroEclpPoolDeployer {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address, bytes memory) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyroEclpPool(tokens, rateProviders, label, vault, lp);
    }

    function testComputeBalanceSmoke() public view {
        uint256[] memory balancesScaled18 = vault.getCurrentLiveBalances(pool);
        uint256 invariantRatio = 1e18;

        uint256 new0 = IBasePool(pool).computeBalance(balancesScaled18, 0, invariantRatio);
        uint256 new1 = IBasePool(pool).computeBalance(balancesScaled18, 1, invariantRatio);
        assertGt(new0, 0);
        assertGt(new1, 0);
    }
}
