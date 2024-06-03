// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";


import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract StableSurgeTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 private constant _MIN_UPDATE_TIME = 1 days;
    uint256 private constant _MAX_RANGEWIDTH_UPDATE_DAILY_RATE = 2;

    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    struct StableSurgeVars {
        uint256 amp;
        uint256 swapFeePercentage;
        uint256 threshold;
        uint256 surgeCoefficient;
    }

    function testStableSurge() public {
        console.log("testing stable surge");

        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = 50e18;
        balancesScaled18[1] = 50e18;

        IBasePool.PoolSwapParams memory params = IBasePool.PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: 40e18,
            balancesScaled18: balancesScaled18,
            indexIn: 0,
            indexOut: 1,
            router: address(0),
            userData: ""
        });

        StableSurgeVars memory vars = StableSurgeVars({
            amp: 1000 * StableMath.AMP_PRECISION,
            swapFeePercentage: 0.0004e18,
            threshold: 0.1e18,
            surgeCoefficient: 50e18
        });

        // 50 _000_000_000_000_000_000

        uint256 dynamicSwapFee;

        (, dynamicSwapFee) = _onComputeDynamicSwapFee(params, vars);

        console.log("dynamic swap fee", dynamicSwapFee);

        _computeAmountOutGivenSurgeFee(params, vars, dynamicSwapFee);
    }

    function _onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams memory params,
        StableSurgeVars memory vars
    ) internal view returns (bool success, uint256 dynamicSwapFee) {
        uint256 invariant = StableMath.computeInvariant(vars.amp, params.balancesScaled18);
        uint256 oneOverN = 1e18 / params.balancesScaled18.length;
        uint256 balancesTotal;

        for (uint256 i = 0; i < params.balancesScaled18.length; ++i) {
            balancesTotal += params.balancesScaled18[i];
        }

        uint256 amountCalculatedScaled18;

        // Bi - after swap = balance of token in after swap
        // W - after swap = Bi / Bn - after swap

        uint amountGivenMinusFeeScaled18 = params.amountGivenScaled18 - params.amountGivenScaled18.mulDown(vars.swapFeePercentage);

        if (params.kind == SwapKind.EXACT_IN) {
            //TODO: we need to account for the static swap fee percentage, which has not been removed from amountGivenScaled18 at this point 
            amountCalculatedScaled18 = StableMath.computeOutGivenExactIn(
                vars.amp,
                params.balancesScaled18,
                params.indexIn,
                params.indexOut,
                amountGivenMinusFeeScaled18,
                invariant
            );
        } else {
            amountCalculatedScaled18 = StableMath.computeInGivenExactOut(
                vars.amp,
                params.balancesScaled18,
                params.indexIn,
                params.indexOut,
                amountGivenMinusFeeScaled18,
                invariant
            );
        }

        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
                ? (params.amountGivenScaled18, amountCalculatedScaled18)
                : (amountCalculatedScaled18, params.amountGivenScaled18);

        uint256 balanceTokenInAfterSwap = params.balancesScaled18[params.indexIn] + amountInScaled18;
        uint256 balanceTokenOutAfterSwap = params.balancesScaled18[params.indexOut] - amountOutScaled18;
        uint256 balancesTotalAfterSwap = balancesTotal + amountInScaled18 - amountOutScaled18;


        console.log("balanceTokenInAfterSwap", balanceTokenInAfterSwap);
        console.log("balanceTokenOutAfterSwap", balanceTokenOutAfterSwap);
        console.log("balancesTotalAfterSwap", balancesTotalAfterSwap);
        console.log("amountOutScaled18", amountOutScaled18);

        uint256 weightAfterSwap = balanceTokenInAfterSwap.divDown(balancesTotalAfterSwap);
        console.log("weightAfterSwap", weightAfterSwap);

        //internal function to avoid stack too deep
        dynamicSwapFee = _computeSurgeFee(vars, oneOverN, weightAfterSwap);
        success = true;
    }

    function _computeSurgeFee(
        StableSurgeVars memory vars,
        uint256 oneOverN,
        uint256 weightAfterSwap
    ) internal view returns (uint256) {
        uint256 weightRatio = weightAfterSwap.divDown(oneOverN + vars.threshold);
        uint256 surgeFee = vars.swapFeePercentage
            .mulDown(vars.surgeCoefficient)
            .mulDown(weightRatio.mulDown(weightRatio));

        /* uint256 surgeFee = vars.swapFeePercentage
            .mulDown(vars.surgeCoefficient)
            .mulDown(weightAfterSwap.divDown(oneOverN + vars.threshold)); */

        if (weightAfterSwap > (oneOverN + vars.threshold)) {
            console.log("surge fee");
            return surgeFee;
        } else {
            console.log("static swap fee");
            return vars.swapFeePercentage;
        }
    }

    function _computeAmountOutGivenSurgeFee(
        IBasePool.PoolSwapParams memory params,
        StableSurgeVars memory vars,
        uint256 surgeFee
    ) internal {
        uint256 invariant = StableMath.computeInvariant(vars.amp, params.balancesScaled18);
        uint amountGivenMinusFeeScaled18 = params.amountGivenScaled18 - params.amountGivenScaled18.mulDown(surgeFee);

        uint256 amountCalculatedScaled18;

        if (params.kind == SwapKind.EXACT_IN) {
            //TODO: we need to account for the static swap fee percentage, which has not been removed from amountGivenScaled18 at this point 
            amountCalculatedScaled18 = StableMath.computeOutGivenExactIn(
                vars.amp,
                params.balancesScaled18,
                params.indexIn,
                params.indexOut,
                amountGivenMinusFeeScaled18,
                invariant
            );
        } else {
            amountCalculatedScaled18 = StableMath.computeInGivenExactOut(
                vars.amp,
                params.balancesScaled18,
                params.indexIn,
                params.indexOut,
                amountGivenMinusFeeScaled18,
                invariant
            );
        }

        console.log("amount out given surge fee", amountCalculatedScaled18);
    }
}






        // weightAfterSwap = 30e18 / 100e18 = 0.3e18
        // weightAfterSwap.divDown(oneOverN + threshold) = 3e17 / (5e17 + 1e17) = 3e17 / 6e17 = 0.5e17 = 0.05e18
        // surgeFee = 0.01e18 * 50e18 * 0.05e18 = 0.025e18

        // weightAfterSwap = 10e18 / 100e18 = 0.1e18
        // weightAfterSwap.divDown(oneOverN + threshold) = 1e17 / (5e17 + 1e17) = 1e17 / 6e17 = 0.16667e17 = 0.016667e18
        // surgeFee = 0.01e18 * 50e18 * 0.016667e18 = 0.0083335e18

        // weightAfterSwap = 70e18 / 100e18 = 0.7e18
        // weightAfterSwap.divDown(oneOverN + threshold) = 7e17 / (5e17 + 1e17) = 7e17 / 6e17 = 1.16667e17 = 0.116667e18
        // surgeFee = 0.01e18 * 50e18 * 0.116667e18 = 0.0583335e18

        // weightAfterSwap = 90e18 / 100e18 = 0.9e18
        // weightAfterSwap.divDown(oneOverN + threshold) = 9e17 / (5e17 + 1e17) = 9e17 / 6e17 = 1.5e17 = 0.15e18
        // surgeFee = 0.01e18 * 50e18 * 0.15e18 = 0.0.075e18





// 022_560_672_736_114_085

// 16267648242060391853