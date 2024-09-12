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

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

contract LiquidityApproximationWeightedTest is LiquidityApproximationTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 internal poolCreationNonce;

    string private baseFilePath = ".invariant/";

    uint256[] private initialLiveBalances = new uint256[](2);

    modifier checkInvariant(string memory file) {
        _;
        (, , , uint256[] memory lastBalancesLiveScaled18After) = vault.getPoolTokenInfo(liquidityPool);

        // initialLiveBalances is populated before each test.
        string memory liveBalancesBeforeString = string(
            abi.encodePacked(vm.toString(initialLiveBalances[0]), ",", vm.toString(initialLiveBalances[1]))
        );
        string memory liveBalancesAfterString = string(
            abi.encodePacked(
                vm.toString(lastBalancesLiveScaled18After[0]),
                ",",
                vm.toString(lastBalancesLiveScaled18After[1])
            )
        );

        uint256[] memory normalizedWeights = WeightedPool(liquidityPool).getNormalizedWeights();
        string memory normalizedWeightsString = string(
            abi.encodePacked(vm.toString(normalizedWeights[0]), ",", vm.toString(normalizedWeights[1]))
        );

        vm.writeLine(
            string.concat(baseFilePath, file),
            string.concat(liveBalancesBeforeString, ",", liveBalancesAfterString, ",", normalizedWeightsString)
        );
    }

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();

        minSwapFeePercentage = IBasePool(swapPool).getMinimumSwapFeePercentage();
        maxSwapFeePercentage = IBasePool(swapPool).getMaximumSwapFeePercentage();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        LiquidityManagement memory liquidityManagement;
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        WeightedPoolMock weightedPool = new WeightedPoolMock(
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

    // Tests varying weight

    function testAddLiquidityUnbalancedWeights__Fuzz(
        uint256 daiAmountIn,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityUnbalancedWeights__Fuzz") {
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        weightDai = bound(weightDai, 1e16, 99e16);
        daiAmountIn = bound(daiAmountIn, minAmount, _computeMaxTokenAmount(weightDai));

        addLiquidityUnbalancedWeights(daiAmountIn, swapFeePercentage, weightDai);
    }

    function testAddLiquidityUnbalancedWeightsNoSwapFee__Fuzz(
        uint256 daiAmountIn,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityUnbalancedWeightsNoSwapFee__Fuzz") {
        weightDai = bound(weightDai, 1e16, 99e16);
        daiAmountIn = _computeMaxTokenAmount(weightDai);

        addLiquidityUnbalancedWeights(daiAmountIn, 0, weightDai);
    }

    function testAddLiquidityUnbalancedWeightsSmallAmounts__Fuzz(
        uint256 daiAmountIn,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityUnbalancedWeightsSmallAmounts__Fuzz") {
        daiAmountIn = bound(daiAmountIn, 1, 1e6);
        weightDai = bound(weightDai, 1e16, 99e16);

        // For small amounts, BPT amount out goes negative because of rounding and BasePoolMath reverts.
        // Perform an external call so that `expectRevert` catches the error.
        vm.expectRevert(stdError.arithmeticError);
        this.addLiquidityUnbalancedWeights(daiAmountIn, 0, weightDai);
    }

    function addLiquidityUnbalancedWeights(uint256 daiAmountIn, uint256 swapFeePercentage, uint256 weightDai) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.5e16; // 0.5%

        _setPoolBalancesWithDifferentWeights(weightDai);

        uint256 amountOut = addUnbalancedOnlyDai(daiAmountIn, swapFeePercentage);
        swapFeePercentage > 0
            ? assertLiquidityOperation(amountOut, swapFeePercentage, true)
            : assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquiditySingleTokenExactOutWeights__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public checkInvariant("testAddLiquiditySingleTokenExactOutWeights__Fuzz") {
        // exactBptAmountOut = bound(exactBptAmountOut, minAmount, maxAmount / 2 - 1);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        weightDai = bound(weightDai, 1e16, 99e16);
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, _computeMaxBptAmount(weightDai, swapFeePercentage));

        _addLiquiditySingleTokenExactOutWeights(exactBptAmountOut, swapFeePercentage, weightDai);
    }

    function testAddLiquiditySingleTokenExactOutWeightsNoSwapFee__Fuzz(
        uint256 exactBptAmountOut,
        uint256 weightDai
    ) public checkInvariant("testAddLiquiditySingleTokenExactOutWeightsNoSwapFee__Fuzz") {
        weightDai = bound(weightDai, 1e16, 99e16);
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, _computeMaxBptAmount(weightDai, 0));

        _addLiquiditySingleTokenExactOutWeights(exactBptAmountOut, 0, weightDai);
    }

    function testAddLiquiditySingleTokenExactOutWeightsSmallAmounts__Fuzz(
        uint256 exactBptAmountOut,
        uint256 weightDai
    ) public checkInvariant("testAddLiquiditySingleTokenExactOutWeightsSmallAmounts__Fuzz") {
        exactBptAmountOut = bound(exactBptAmountOut, 1, 1e6);
        weightDai = bound(weightDai, 1e16, 99e16);

        _addLiquiditySingleTokenExactOutWeights(exactBptAmountOut, 0, weightDai);
    }

    function _addLiquiditySingleTokenExactOutWeights(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) internal {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.1e16; // 0.1%
        defectRoundingDelta = 0.001e16; // 0.001%
        absoluteRoundingDelta = 1e15;

        _setPoolBalancesWithDifferentWeights(weightDai);

        uint256 amountOut = addExactOutArbitraryBptOut(exactBptAmountOut, swapFeePercentage);
        swapFeePercentage > 0
            ? assertLiquidityOperation(amountOut, swapFeePercentage, true)
            : assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquidityProportionalAndRemoveExactInWeights__Fuzz(
        uint256 exactBptAmount,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityProportionalAndRemoveExactInWeights__Fuzz") {
        exactBptAmount = bound(exactBptAmount, minAmount, maxAmount / 2 - 1);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        weightDai = bound(weightDai, 1e16, 99e16);

        addLiquidityProportionalAndRemoveExactInWeights(exactBptAmount, swapFeePercentage, weightDai);
    }

    function testAddLiquidityProportionalAndRemoveExactInWeightsNoSwapFee__Fuzz(
        uint256 exactBptAmount,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityProportionalAndRemoveExactInWeightsNoSwapFee__Fuzz") {
        exactBptAmount = bound(exactBptAmount, minAmount, maxAmount / 2 - 1);
        weightDai = bound(weightDai, 1e16, 99e16);

        addLiquidityProportionalAndRemoveExactInWeights(exactBptAmount, 0, weightDai);
    }

    function testAddLiquidityProportionalAndRemoveExactInWeightsSmallAmounts__Fuzz(
        uint256 exactBptAmount,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityProportionalAndRemoveExactInWeightsSmallAmounts__Fuzz") {
        exactBptAmount = bound(exactBptAmount, 0, 1e6);
        weightDai = bound(weightDai, 1e16, 99e16);

        // `amountOut` will go negative inside `BasePoolMath`.
        vm.expectRevert(stdError.arithmeticError);
        this.addLiquidityProportionalAndRemoveExactInWeights(exactBptAmount, 0, weightDai);
    }

    function addLiquidityProportionalAndRemoveExactInWeights(
        uint256 exactBptAmount,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        defectRoundingDelta = 0.00001e16; // 0.00001%

        _setPoolBalancesWithDifferentWeights(weightDai);

        uint256 amountOut = removeExactInAllBptIn(exactBptAmount, swapFeePercentage);
        swapFeePercentage > 0
            ? assertLiquidityOperation(amountOut, swapFeePercentage, false)
            : assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquidityProportionalAndRemoveExactOutWeights__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityProportionalAndRemoveExactOutWeights__Fuzz") {
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, maxAmount / 2 - 1);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        weightDai = bound(weightDai, 1e16, 99e16);

        addLiquidityProportionalAndRemoveExactOutWeights(exactBptAmountOut, swapFeePercentage, weightDai);
    }

    function testAddLiquidityProportionalAndRemoveExactOutWeightsNoSwapFee__Fuzz(
        uint256 exactBptAmountOut,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityProportionalAndRemoveExactOutWeightsNoSwapFee__Fuzz") {
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, maxAmount / 2 - 1);
        weightDai = bound(weightDai, 1e16, 99e16);

        addLiquidityProportionalAndRemoveExactOutWeights(exactBptAmountOut, 0, weightDai);
    }

    function testAddLiquidityProportionalAndRemoveExactOutWeightsSmallAmounts__Fuzz(
        uint256 exactBptAmountOut,
        uint256 weightDai
    ) public checkInvariant("testAddLiquidityProportionalAndRemoveExactOutWeightsSmallAmounts__Fuzz") {
        exactBptAmountOut = bound(exactBptAmountOut, 1, 1e6);
        weightDai = bound(weightDai, 1e16, 99e16);

        // Remove will ask more BPT than what the sender has; we care about the revert reason, not the exact amount.
        // TODO: use `expectPartialRevert` once forge is updated with `IVaultErrors.BptAmountInAboveMax.selector`:
        // `expectPartialRevert(IVaultErrors.BptAmountInAboveMax.selector)`
        vm.expectRevert();
        this.addLiquidityProportionalAndRemoveExactOutWeights(exactBptAmountOut, 0, weightDai);
    }

    function addLiquidityProportionalAndRemoveExactOutWeights(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.5e16; // 0.5%

        _setPoolBalancesWithDifferentWeights(weightDai);

        uint256 amountOut = removeExactOutAllUsdcAmountOut(exactBptAmountOut, swapFeePercentage);
        swapFeePercentage > 0
            ? assertLiquidityOperation(amountOut, swapFeePercentage, false)
            : assertLiquidityOperationNoSwapFee();
    }

    function testRemoveLiquiditySingleTokenExactOutWeights__Fuzz(
        uint256 exactAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public checkInvariant("testRemoveLiquiditySingleTokenExactOutWeights__Fuzz") {
        // This test adds 10x the initial liquidity to work, so we amplify the usual min amount.
        // On the other hand, we would need to add even more in the first step to work with large `exactAmountOut`,
        // so we also cap the maximum.
        exactAmountOut = bound(exactAmountOut, minAmount * 10, maxAmount / 10);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        weightDai = bound(weightDai, 1e16, 99e16);

        removeLiquiditySingleTokenExactOutWeights(exactAmountOut, swapFeePercentage, weightDai);
    }

    function testRemoveLiquiditySingleTokenExactOutWeightsNoSwapFee__Fuzz(
        uint256 exactAmountOut,
        uint256 weightDai
    ) public checkInvariant("testRemoveLiquiditySingleTokenExactOutWeightsNoSwapFee__Fuzz") {
        // This test adds 10x the initial liquidity to work, so we amplify the usual min amount.
        // On the other hand, we would need to add even more in the first step to work with large `exactAmountOut`,
        // so we also cap the maximum.
        exactAmountOut = bound(exactAmountOut, minAmount * 10, maxAmount / 10);
        weightDai = bound(weightDai, 1e16, 99e16);

        removeLiquiditySingleTokenExactOutWeights(exactAmountOut, 0, weightDai);
    }

    function testRemoveLiquiditySingleTokenExactOutWeightsSmallAmounts__Fuzz(
        uint256 exactAmountOut,
        uint256 weightDai
    ) public checkInvariant("testRemoveLiquiditySingleTokenExactOutWeightsSmallAmounts__Fuzz") {
        exactAmountOut = bound(exactAmountOut, 1, 1e6);
        weightDai = bound(weightDai, 1e16, 99e16);

        try this.removeLiquiditySingleTokenExactOutWeights(exactAmountOut, 0, weightDai) {
            // OK, test passed.
        } catch (bytes memory result) {
            // Can also legitimately fail due to arithmetic underflow when computing `taxableAmount` in `BasePoolMath`.abi
            // live system will be protected by minimum amounts in any case.
            assertEq(bytes4(result), bytes4(stdError.arithmeticError), "Unexpected error");
        }
    }

    function removeLiquiditySingleTokenExactOutWeights(
        uint256 exactAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.5e16; // 0.5%

        _setPoolBalancesWithDifferentWeights(weightDai);

        uint256 amountOut = removeExactOutArbitraryAmountOut(exactAmountOut, swapFeePercentage);
        swapFeePercentage > 0
            ? assertLiquidityOperation(amountOut, swapFeePercentage, false)
            : assertLiquidityOperationNoSwapFee();
    }

    function testRemoveLiquiditySingleTokenExactOut__Fuzz(
        uint256 exactAmountOut,
        uint256 swapFeePercentage
    ) public override checkInvariant("testRemoveLiquiditySingleTokenExactOut__Fuzz") {
        excessRoundingDelta = 0.5e16;
        super.testRemoveLiquiditySingleTokenExactOut__Fuzz(exactAmountOut, swapFeePercentage);
    }

    function testRemoveLiquiditySingleTokenExactOutNoSwapFee__Fuzz(
        uint256 exactAmountOut
    ) public override checkInvariant("testRemoveLiquiditySingleTokenExactOutNoSwapFee__Fuzz") {
        excessRoundingDelta = 0.5e16;
        super.testRemoveLiquiditySingleTokenExactOutNoSwapFee__Fuzz(exactAmountOut);
    }

    function testRemoveLiquiditySingleTokenExactInWeights__Fuzz(
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public checkInvariant("testRemoveLiquiditySingleTokenExactInWeights__Fuzz") {
        exactBptAmountIn = bound(exactBptAmountIn, minAmount, maxAmount);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        weightDai = bound(weightDai, 1e16, 99e16);

        removeLiquiditySingleTokenExactInWeights(exactBptAmountIn, swapFeePercentage, weightDai);
    }

    function testRemoveLiquiditySingleTokenExactInWeightsNoSwapFee__Fuzz(
        uint256 exactBptAmountIn,
        uint256 weightDai
    ) public checkInvariant("testRemoveLiquiditySingleTokenExactInWeightsNoSwapFee__Fuzz") {
        exactBptAmountIn = bound(exactBptAmountIn, minAmount, maxAmount);
        weightDai = bound(weightDai, 1e16, 99e16);

        removeLiquiditySingleTokenExactInWeights(exactBptAmountIn, 0, weightDai);
    }

    function testRemoveLiquiditySingleTokenExactInWeightsSmallAmounts__Fuzz(
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public checkInvariant("testRemoveLiquiditySingleTokenExactInWeightsSmallAmounts__Fuzz") {
        exactBptAmountIn = bound(exactBptAmountIn, 1, 1e6);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        weightDai = bound(weightDai, 1e16, 99e16);

        // For very small invariant ratios, `BasePoolMath` reverts when calculated amount out < 0 because of rounding.
        // Perform an external call so that `expectRevert` catches the error.
        vm.expectRevert(stdError.arithmeticError);
        this.removeLiquiditySingleTokenExactInWeights(exactBptAmountIn, swapFeePercentage, weightDai);
    }

    function removeLiquiditySingleTokenExactInWeights(
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        defectRoundingDelta = 0.0001e16; // 0.0001%

        _setPoolBalancesWithDifferentWeights(weightDai);

        uint256 amountOut = removeExactInArbitraryBptIn(exactBptAmountIn, swapFeePercentage);
        swapFeePercentage > 0
            ? assertLiquidityOperation(amountOut, swapFeePercentage, false)
            : assertLiquidityOperationNoSwapFee();
    }

    /// Utils

    function _computeMaxTokenAmount(uint256 weightDai) private view returns (uint256 maxAmount) {
        // `maxAmount` must be lower than 30% of the lowest pool liquidity. Below, `maxAmount` is calculated as 25%
        // of the lowest liquidity to have some error margin.
        maxAmount = weightDai > 50e16
            ? poolInitAmount.mulDown(weightDai.complement())
            : poolInitAmount.mulDown(weightDai);
        maxAmount = maxAmount.mulDown(25e16);
    }

    function _computeMaxBptAmount(
        uint256 weightDai,
        uint256 swapFeePercentage
    ) private view returns (uint256 maxAmount) {
        uint256 totalSupply = IERC20(liquidityPool).totalSupply();
        // Compute the portion of the BPT supply that corresponds to the DAI tokens.
        uint256 daiSupply = totalSupply.mulDown(weightDai);
        // When we add liquidity unbalanced, fees will make the vault request more tokens.
        // We need to offset this effect: we want to bring down the max amount even further when fees are larger,
        // so we multiply the DAI supply with a lower value as fees go higher.
        uint256 daiSupplyAccountingFees = daiSupply.mulDown(swapFeePercentage.complement());

        // Finally we multiply by 25% (30% is max in ratio, this leaves some margin for error).
        maxAmount = daiSupplyAccountingFees.mulDown(25e16);
    }

    // @dev Writes to storage the initial conditions.
    function _setPoolBalancesWithDifferentWeights(uint256 weightDai) private {
        uint256[2] memory newWeights;
        newWeights[daiIdx] = weightDai;
        newWeights[usdcIdx] = weightDai.complement();

        WeightedPoolMock(liquidityPool).setNormalizedWeights(newWeights);
        WeightedPoolMock(swapPool).setNormalizedWeights(newWeights);

        // This operation will change the invariant of the pool, but what matters is the proportion of each token.
        initialLiveBalances[daiIdx] = (poolInitAmount).mulDown(newWeights[daiIdx]);
        initialLiveBalances[usdcIdx] = (poolInitAmount).mulDown(newWeights[usdcIdx]);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(liquidityPool);
        // liveBalances = rawBalances because rate is 1 and both tokens are 18 decimals.
        vault.manualSetPoolTokensAndBalances(liquidityPool, tokens, initialLiveBalances, initialLiveBalances);
        vault.manualSetPoolTokensAndBalances(swapPool, tokens, initialLiveBalances, initialLiveBalances);
    }
}
