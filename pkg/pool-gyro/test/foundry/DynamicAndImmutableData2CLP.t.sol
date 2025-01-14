// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import {
    IGyro2CLPPool,
    Gyro2CLPPoolImmutableData,
    Gyro2CLPPoolDynamicData
} from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyro2CLPPool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { Gyro2ClpPoolDeployer } from "./utils/Gyro2ClpPoolDeployer.sol";

contract DynamicAndImmutableData2CLPTest is BaseVaultTest, Gyro2ClpPoolDeployer {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address, bytes memory) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyro2ClpPool(tokens, rateProviders, label, vault, lp);
    }

    function testGetGyro2CLPPoolDynamicData() public {
        Gyro2CLPPoolDynamicData memory data = IGyro2CLPPool(pool).getGyro2CLPPoolDynamicData();

        (, uint256[] memory tokenRates) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();
        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256 bptRate = vault.getBptRate(pool);

        assertTrue(data.isPoolInitialized, "Pool not initialized");
        assertFalse(data.isPoolPaused, "Pool paused");
        assertFalse(data.isPoolInRecoveryMode, "Pool in Recovery Mode");

        assertEq(data.bptRate, bptRate, "BPT rate mismatch");
        assertEq(data.totalSupply, totalSupply, "Total supply mismatch");

        assertEq(data.staticSwapFeePercentage, DEFAULT_SWAP_FEE, "Swap fee mismatch");

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(data.balancesLiveScaled18[i], DEFAULT_AMOUNT, "Live balance mismatch");
            assertEq(data.tokenRates[i], tokenRates[i], "Token rate mismatch");
        }

        // Data should reflect the change in the static swap fee percentage.
        vault.manualSetStaticSwapFeePercentage(pool, 1e16);
        data = IGyro2CLPPool(pool).getGyro2CLPPoolDynamicData();
        assertEq(data.staticSwapFeePercentage, 1e16, "Swap fee mismatch");
    }

    function testGetGyro2CLPPoolImmutableData() public view {
        Gyro2CLPPoolImmutableData memory data = IGyro2CLPPool(pool).getGyro2CLPPoolImmutableData();
        (uint256[] memory scalingFactors, ) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();

        assertEq(data.sqrtAlpha, _sqrtAlpha, "sqrtAlpha mismatch");
        assertEq(data.sqrtBeta, _sqrtBeta, "sqrtBeta mismatch");

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token mismatch");
            assertEq(data.decimalScalingFactors[i], scalingFactors[i], "Decimal scaling factors mismatch");
        }
    }
}
