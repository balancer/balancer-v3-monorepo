// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolRoleAccounts, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { PoolConfigBits } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { WeightedPoolMock } from "../../contracts/test/WeightedPoolMock.sol";
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

contract LiquidityApproximationWeightedTest is LiquidityApproximationTest, WeightedPoolContractsDeployer {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 internal poolCreationNonce;

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();

        minSwapFeePercentage = IBasePool(swapPool).getMinimumSwapFeePercentage();
        maxSwapFeePercentage = IBasePool(swapPool).getMaximumSwapFeePercentage();

        excessRoundingDelta = 0.5e16; // 0.5%
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        WeightedPoolMock weightedPool = deployWeightedPoolMock(
            WeightedPool.NewPoolParams({
                name: label,
                symbol: "WEIGHTY",
                numTokens: 2,
                normalizedWeights: [uint256(50e16), uint256(50e16)].toMemoryArray(),
                version: "Version 1"
            }),
            vault
        );
        vm.label(address(weightedPool), label);

        vault.registerPool(
            address(weightedPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_SWAP_FEE,
            0,
            false,
            roleAccounts,
            address(0),
            liquidityManagement
        );

        return address(weightedPool);
    }

    function fuzzPoolParams(uint256[10] memory params) internal override {
        uint256 weightDai = params[0];
        weightDai = bound(weightDai, 1e16, 99e16);

        _setPoolBalancesWithDifferentWeights(weightDai);

        absoluteRoundingDelta = 1e14;

        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 2e16; // 2%
        defectRoundingDelta = 0.001e16; // 0.001%

        if (weightDai < 20e16 || weightDai > 80e16) {
            // TODO: check why the difference grows so large in the extremes (high fees, high dai weight).
            excessRoundingDelta = 10e16; // 10%
            defectRoundingDelta = 0.1e16; // 0.1%
        }
    }

    function getMaxDaiIn() internal view override returns (uint256) {
        uint256 weightDai = WeightedPool(liquidityPool).getNormalizedWeights()[daiIdx];
        // `maxAmount` must be lower than 30% of the lowest pool liquidity. Below, `maxAmount` is calculated as 25%
        // of the lowest liquidity to have some error margin.
        uint256 maxAmount = weightDai > 50e16
            ? poolInitAmount.mulDown(weightDai.complement())
            : poolInitAmount.mulDown(weightDai);
        return maxAmount.mulDown(25e16);
    }

    function getMaxBptOut() internal view override returns (uint256) {
        uint256 weightDai = WeightedPool(liquidityPool).getNormalizedWeights()[daiIdx];
        uint256 swapFeePercentage = vault.getStaticSwapFeePercentage(liquidityPool);

        uint256 totalSupply = IERC20(liquidityPool).totalSupply();
        // Compute the portion of the BPT supply that corresponds to the DAI tokens.
        uint256 daiSupply = totalSupply.mulDown(weightDai);
        // When we add liquidity unbalanced, fees will make the Vault request more tokens.
        // We need to offset this effect: we want to bring down the max amount even further when fees are larger,
        // so we multiply the DAI supply with a lower value as fees go higher.
        uint256 daiSupplyAccountingFees = daiSupply.mulDown(swapFeePercentage.complement());

        // Finally we multiply by 25% (30% is max in ratio, this leaves some margin for error).
        return daiSupplyAccountingFees.mulDown(25e16);
    }

    function testAddLiquidityUnbalancedSmallAmountsSpecific__Fuzz(
        uint256 daiAmountIn,
        uint256[10] memory params
    ) public {
        fuzzPoolParams(params);
        daiAmountIn = bound(daiAmountIn, 1, 1e6);

        setSwapFeePercentageInPools(0);

        // For small amounts, BPT amount out goes negative because of rounding and BasePoolMath reverts.
        // Perform an external call so that `expectRevert` catches the error.
        vm.expectRevert(stdError.arithmeticError);
        addUnbalancedOnlyDai(daiAmountIn);
    }

    function testAddLiquiditySingleTokenExactOutWeightsSmallAmounts__Fuzz(
        uint256 exactBptAmountOut,
        uint256[10] memory params
    ) public {
        fuzzPoolParams(params);
        exactBptAmountOut = bound(exactBptAmountOut, 1, 1e6);

        setSwapFeePercentageInPools(0);
        addExactOutArbitraryBptOut(exactBptAmountOut);
        assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquidityProportionalAndRemoveExactInWeightsSmallAmounts__Fuzz(
        uint256 exactBptAmount,
        uint256[10] memory params
    ) public {
        fuzzPoolParams(params);
        exactBptAmount = bound(exactBptAmount, 0, 1e6);

        setSwapFeePercentageInPools(0);

        // `amountOut` will go negative inside `BasePoolMath`.
        vm.expectRevert(stdError.arithmeticError);
        removeExactInAllBptIn(exactBptAmount);
    }

    function testAddLiquidityProportionalAndRemoveExactOutWeightsSmallAmounts__Fuzz(
        uint256 exactBptAmountOut,
        uint256[10] memory params
    ) public {
        fuzzPoolParams(params);
        exactBptAmountOut = bound(exactBptAmountOut, 1, 1e6);

        setSwapFeePercentageInPools(0);

        // Remove will ask more BPT than what the sender has; we care about the revert reason, not the exact amount.
        // TODO: use `expectPartialRevert` once forge is updated with `IVaultErrors.BptAmountInAboveMax.selector`:
        // `expectPartialRevert(IVaultErrors.BptAmountInAboveMax.selector)`
        vm.expectRevert();
        removeExactOutAllUsdcAmountOut(exactBptAmountOut);
    }

    //    function testRemoveLiquiditySingleTokenExactOutWeightsSmallAmounts__Fuzz(
    //        uint256 exactAmountOut,
    //        uint256 weightDai
    //    ) public {
    //        exactAmountOut = bound(exactAmountOut, 1, 1e6);
    //        weightDai = bound(weightDai, 1e16, 99e16);
    //
    //        try this.removeLiquiditySingleTokenExactOutWeights(exactAmountOut, 0, weightDai) {
    //            // OK, test passed.
    //        } catch (bytes memory result) {
    //            // Can also legitimately fail due to arithmetic underflow when computing `taxableAmount` in `BasePoolMath`.abi
    //            // live system will be protected by minimum amounts in any case.
    //            assertEq(bytes4(result), bytes4(stdError.arithmeticError), "Unexpected error");
    //        }
    //    }

    //    function testRemoveLiquiditySingleTokenExactInWeightsSmallAmounts__Fuzz(
    //        uint256 exactBptAmountIn,
    //        uint256 swapFeePercentage,
    //        uint256 weightDai
    //    ) public {
    //        exactBptAmountIn = bound(exactBptAmountIn, 1, 1e6);
    //        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
    //        weightDai = bound(weightDai, 1e16, 99e16);
    //
    //        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
    //        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
    //        defectRoundingDelta = 0.0001e16; // 0.0001%
    //
    //        // For very small invariant ratios, `BasePoolMath` reverts when calculated amount out < 0 because of rounding.
    //        // Perform an external call so that `expectRevert` catches the error.
    //        vm.expectRevert(stdError.arithmeticError);
    //        this.removeLiquiditySingleTokenExactInWeights(exactBptAmountIn, swapFeePercentage, weightDai);
    //    }

    // Utils

    function _setPoolBalancesWithDifferentWeights(
        uint256 weightDai
    ) private returns (uint256[] memory newPoolBalances) {
        uint256[2] memory newWeights;
        newWeights[daiIdx] = weightDai;
        newWeights[usdcIdx] = weightDai.complement();

        WeightedPoolMock(liquidityPool).setNormalizedWeights(newWeights);
        WeightedPoolMock(swapPool).setNormalizedWeights(newWeights);

        newPoolBalances = new uint256[](2);
        // This operation will change the invariant of the pool, but what matters is the proportion of each token.
        newPoolBalances[daiIdx] = (poolInitAmount).mulDown(newWeights[daiIdx]);
        newPoolBalances[usdcIdx] = (poolInitAmount).mulDown(newWeights[usdcIdx]);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(liquidityPool);
        // liveBalances = rawBalances because rate is 1 and both tokens are 18 decimals.
        vault.manualSetPoolTokensAndBalances(liquidityPool, tokens, newPoolBalances, newPoolBalances);
        vault.manualSetPoolTokensAndBalances(swapPool, tokens, newPoolBalances, newPoolBalances);
    }
}
