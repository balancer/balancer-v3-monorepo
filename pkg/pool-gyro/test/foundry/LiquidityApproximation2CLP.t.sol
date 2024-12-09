// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

import { Gyro2CLPPoolMock } from "../../contracts/test/Gyro2CLPPoolMock.sol";
import { Gyro2ClpPoolDeployer } from "./utils/Gyro2ClpPoolDeployer.sol";

contract LiquidityApproximation2CLPTest is LiquidityApproximationTest, Gyro2ClpPoolDeployer {
    // A difference smaller than the constant below causes issues during calculation of the 2-CLP pool invariant.
    uint256 private constant _MINIMUM_DIFF_ALPHA_BETA = 0.01e16;

    uint256 private constant _MINIMUM_SQRT_ALPHA = 90e16;
    uint256 private constant _MAXIMUM_SQRT_BETA = 110e16;

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address, bytes memory) {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        return createGyro2ClpPoolMock(tokens, rateProviders, label, vault, lp);
    }

    function fuzzPoolParams(uint256[POOL_SPECIFIC_PARAMS_SIZE] memory params) internal override {
        uint256 sqrtAlpha = params[0];
        sqrtAlpha = bound(sqrtAlpha, _MINIMUM_SQRT_ALPHA, _MAXIMUM_SQRT_BETA - _MINIMUM_DIFF_ALPHA_BETA);

        uint256 sqrtBeta = params[1];
        sqrtBeta = bound(sqrtBeta, sqrtAlpha + _MINIMUM_DIFF_ALPHA_BETA, _MAXIMUM_SQRT_BETA);

        _setSqrtParams(sqrtAlpha, sqrtBeta);

        // SqrtParams can introduce some differences in the swap fees calculated by the pool during unbalanced
        // add/remove liquidity, so the error tolerance needs to be a bit higher than the default tolerance. The
        // farther sqrtAlpha and sqrtBeta are from 1e18, the bigger the error.
        excessRoundingDelta = 2e16; // 2%

        // AddLiquidityUnbalanced without swap fees may have rounding issues when calculating Alice and Bob balances.
        absoluteRoundingDelta = 1e9;
        defectRoundingDelta = 3;

        // 2CLP requires a minimum fee so swaps are cheaper than unbalanced adds/removes in all situations.
        minSwapFeePercentage = 1e12;
    }

    function _setSqrtParams(uint256 sqrtAlpha, uint256 sqrtBeta) private {
        Gyro2CLPPoolMock(liquidityPool).setSqrtParams(sqrtAlpha, sqrtBeta);
        Gyro2CLPPoolMock(swapPool).setSqrtParams(sqrtAlpha, sqrtBeta);
    }
}
