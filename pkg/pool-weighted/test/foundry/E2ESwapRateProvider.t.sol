// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { RateProviderMock } from "@balancer-labs/v3-solidity-utils/contracts/test/RateProviderMock.sol";
import { E2eSwapRateProviderTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwapRateProvider.t.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { WeightedPoolMock } from "../../contracts/test/WeightedPoolMock.sol";

contract E2eSwapRateProviderWeightedTest is E2eSwapRateProviderTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 internal poolCreationNonce;

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        rateProviderTokenA = new RateProviderMock();
        rateProviderTokenB = new RateProviderMock();
        // Mock rates, so all tests that keep the rate constant use a rate different than 1.
        rateProviderTokenA.mockRate(5.2453235e18);
        rateProviderTokenB.mockRate(0.4362784e18);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[tokenAIdx] = IRateProvider(address(rateProviderTokenA));
        rateProviders[tokenBIdx] = IRateProvider(address(rateProviderTokenB));

        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            factory.create(
                "50/50 Weighted Pool",
                "50_50WP",
                vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                roleAccounts,
                DEFAULT_SWAP_FEE, // 1% swap fee, but test will override it
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer weighted pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        return address(newPool);
    }

    function calculateMinAndMaxSwapAmounts() internal override {
        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // The vault does not allow trade amounts (amountGivenScaled18 or amountCalculatedScaled18) to be less than
        // MIN_TRADE_AMOUNT. For "linear pools" (PoolMock), amountGivenScaled18 and amountCalculatedScaled18 are
        // the same. So, minAmountGivenScaled18 > MIN_TRADE_AMOUNT. To derive the formula below, note that
        // `amountGivenRaw = amountGivenScaled18/(rateToken * scalingFactor)`. There's an adjustment for weighted math
        // in the following steps.
        uint256 tokenAMinTradeAmount = MIN_TRADE_AMOUNT.divUp(rateTokenA).mulUp(10 ** decimalsTokenA);
        uint256 tokenBMinTradeAmount = MIN_TRADE_AMOUNT.divUp(rateTokenB).mulUp(10 ** decimalsTokenB);

        // Also, since we undo the operation (reverse swap with the output of the first swap), amountCalculatedRaw
        // cannot be 0. Considering that amountCalculated is tokenB, and amountGiven is tokenA:
        // 1) amountCalculatedRaw > 0
        // 2) amountCalculatedRaw = amountCalculatedScaled18 * 10^(decimalsB) / (rateB * 10^18)
        // 3) amountCalculatedScaled18 = amountGivenScaled18 // Linear math, there's a factor to weighted math
        // introduced in the next step
        // 4) amountGivenScaled18 = amountGivenRaw * rateA * 10^18 / 10^(decumalsA)
        // Combining the four formulas above, we determine that:
        // amountCalculatedRaw > rateB * 10^(decimalsA) / (rateA * 10^(decimalsB))
        uint256 tokenACalculatedNotZero = (rateTokenB * (10 ** decimalsTokenA)) / (rateTokenA * (10 ** decimalsTokenB));
        uint256 tokenBCalculatedNotZero = (rateTokenA * (10 ** decimalsTokenB)) / (rateTokenB * (10 ** decimalsTokenA));

        // Use the larger of the two values above to calculate the minSwapAmount. Also, multiply by 10000 to account
        // for both swap fees, and compensate for approximation errors between weighted and linear math.
        uint256 weightedMathFactor = 1e4;
        minSwapAmountTokenA = (
            tokenAMinTradeAmount > tokenACalculatedNotZero
                ? weightedMathFactor * tokenAMinTradeAmount
                : weightedMathFactor * tokenACalculatedNotZero
        );
        minSwapAmountTokenB = (
            tokenBMinTradeAmount > tokenBCalculatedNotZero
                ? weightedMathFactor * tokenBMinTradeAmount
                : weightedMathFactor * tokenBCalculatedNotZero
        );

        // 20% of initial liquidity to make sure weighted math ratios are respected.
        // We cannot trade more than 30% of pool liquidity.
        maxSwapAmountTokenA = poolInitAmountTokenA.mulDown(20e16);
        maxSwapAmountTokenB = poolInitAmountTokenB.mulDown(20e16);
    }
}
