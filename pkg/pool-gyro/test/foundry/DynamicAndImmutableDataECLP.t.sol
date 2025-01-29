// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import {
    IGyroECLPPool,
    GyroECLPPoolImmutableData,
    GyroECLPPoolDynamicData
} from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { GyroEclpPoolDeployer } from "./utils/GyroEclpPoolDeployer.sol";

contract DynamicAndImmutableDataECLPTest is BaseVaultTest, GyroEclpPoolDeployer {
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

    function testGetGyroECLPPoolDynamicData() public {
        GyroECLPPoolDynamicData memory data = IGyroECLPPool(pool).getGyroECLPPoolDynamicData();

        (, uint256[] memory tokenRates) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();
        uint256 totalSupply = IERC20(pool).totalSupply();
        uint256 bptRate = vault.getBptRate(pool);

        assertTrue(data.isPoolInitialized, "Pool not initialized");
        assertFalse(data.isPoolPaused, "Pool paused");
        assertFalse(data.isPoolInRecoveryMode, "Pool in Recovery Mode");

        assertEq(data.bptRate, bptRate, "BPT rate mismatch");
        assertEq(data.totalSupply, totalSupply, "Total supply mismatch");

        assertEq(data.staticSwapFeePercentage, MIN_SWAP_FEE_PERCENTAGE, "Swap fee mismatch");

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(data.balancesLiveScaled18[i], DEFAULT_AMOUNT, "Live balance mismatch");
            assertEq(data.tokenRates[i], tokenRates[i], "Token rate mismatch");
        }

        // Data should reflect the change in the static swap fee percentage.
        vault.manualSetStaticSwapFeePercentage(pool, 1e16);
        data = IGyroECLPPool(pool).getGyroECLPPoolDynamicData();
        assertEq(data.staticSwapFeePercentage, 1e16, "Swap fee mismatch");
    }

    function testGetGyroECLPPoolImmutableData() public view {
        GyroECLPPoolImmutableData memory data = IGyroECLPPool(pool).getGyroECLPPoolImmutableData();
        (uint256[] memory scalingFactors, ) = vault.getPoolTokenRates(pool);
        IERC20[] memory tokens = IPoolInfo(pool).getTokens();

        assertEq(data.paramsAlpha, _paramsAlpha, "paramsAlpha mismatch");
        assertEq(data.paramsBeta, _paramsBeta, "paramsBeta mismatch");
        assertEq(data.paramsC, _paramsC, "paramsC mismatch");
        assertEq(data.paramsS, _paramsS, "paramsS mismatch");
        assertEq(data.paramsLambda, _paramsLambda, "paramsLambda mismatch");
        assertEq(data.tauAlphaX, _tauAlphaX, "tauAlphaX mismatch");
        assertEq(data.tauAlphaY, _tauAlphaY, "tauAlphaY mismatch");
        assertEq(data.tauBetaX, _tauBetaX, "tauBetaX mismatch");
        assertEq(data.tauBetaY, _tauBetaY, "tauBetaY mismatch");
        assertEq(data.u, _u, "u mismatch");
        assertEq(data.v, _v, "v mismatch");
        assertEq(data.w, _w, "w mismatch");
        assertEq(data.z, _z, "z mismatch");
        assertEq(data.dSq, _dSq, "dSq mismatch");

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token mismatch");
            assertEq(data.decimalScalingFactors[i], scalingFactors[i], "Decimal scaling factors mismatch");
        }
    }
}
