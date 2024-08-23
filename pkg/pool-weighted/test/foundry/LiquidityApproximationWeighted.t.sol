// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
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
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.5e16; // 0.1%

        swapFeePercentage = _setPoolWeightsAndSwapFee(swapFeePercentage, weightDai);

        uint256 amountOut = addUnbalancedOnlyDai(daiAmountIn, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquiditySingleTokenExactOutWeights__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.1e16; // 0.1%
        defectRoundingDelta = 0.001e16; // 0.001%
        absoluteRoundingDelta = 1e15;

        swapFeePercentage = _setPoolWeightsAndSwapFee(swapFeePercentage, weightDai);

        uint256 amountOut = addExactOutArbitraryBptOut(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquidityProportionalAndRemoveExactInWeights__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        defectRoundingDelta = 0.00001e16; // 0.00001%

        swapFeePercentage = _setPoolWeightsAndSwapFee(swapFeePercentage, weightDai);

        uint256 amountOut = removeExactInAllBptIn(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testAddLiquidityProportionalAndRemoveExactOutWeights__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.5e16; // 0.5%

        swapFeePercentage = _setPoolWeightsAndSwapFee(swapFeePercentage, weightDai);

        uint256 amountOut = removeExactOutAllUsdcAmountOut(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactOutWeights__Fuzz(
        uint256 exactAmountOut,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        excessRoundingDelta = 0.5e16; // 0.5%

        swapFeePercentage = _setPoolWeightsAndSwapFee(swapFeePercentage, weightDai);

        uint256 amountOut = removeExactOutArbitraryAmountOut(exactAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactInWeights__Fuzz(
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage,
        uint256 weightDai
    ) public {
        // Weights can introduce some differences in the swap fees calculated by the pool during unbalanced add/remove
        // liquidity, so the error tolerance needs to be a bit higher than the default tolerance.
        defectRoundingDelta = 0.00001e16; // 0.000001%

        swapFeePercentage = _setPoolWeightsAndSwapFee(swapFeePercentage, weightDai);

        uint256 amountOut = removeExactInArbitraryBptIn(exactBptAmountIn, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    /// Utils

    function _setPoolWeightsAndSwapFee(uint256 swapFeePercentage, uint256 weightDai) private returns (uint256) {
        // Vary DAI weight from 1% to 99%.
        weightDai = bound(weightDai, 1e16, 99e16);
        _setPoolBalancesWithDifferentWeights(weightDai);

        // maxAmount must be lower than 30% of the lowest pool liquidity. Below, maxAmount is calculated as 25% of the
        // lowest liquidity to have some error margin.
        maxAmount = weightDai > 50e16
            ? poolInitAmount.mulDown(weightDai.complement())
            : poolInitAmount.mulDown(weightDai);
        maxAmount = maxAmount.mulDown(25e16);

        // Vary swap fee from 0.0001% (min swap fee) - 10% (max swap fee).
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        return swapFeePercentage;
    }

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
