// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { E2eSwapRateProviderTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwapRateProvider.t.sol";
import { VaultContractsDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultContractsDeployer.sol";

import { Gyro2CLPPoolFactory } from "../../contracts/Gyro2CLPPoolFactory.sol";
import { Gyro2CLPPool } from "../../contracts/Gyro2CLPPool.sol";

contract E2eSwapRateProviderGyro2CLPTest is VaultContractsDeployer, E2eSwapRateProviderTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 poolCreationNonce;

    uint256 private _sqrtAlpha = 997496867163000167; // alpha (lower price rate) = 0.995
    uint256 private _sqrtBeta = 1002496882788171068; // beta (upper price rate) = 1.005

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        rateProviderTokenA = deployRateProviderMock();
        rateProviderTokenB = deployRateProviderMock();
        // Mock rates, so all tests that keep the rate constant use a rate different than 1.
        rateProviderTokenA.mockRate(5.2453235e18);
        rateProviderTokenB.mockRate(0.4362784e18);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[tokenAIdx] = IRateProvider(address(rateProviderTokenA));
        rateProviders[tokenBIdx] = IRateProvider(address(rateProviderTokenB));

        Gyro2CLPPoolFactory factory = new Gyro2CLPPoolFactory(IVault(address(vault)), 365 days);

        PoolRoleAccounts memory roleAccounts;

        Gyro2CLPPool newPool = Gyro2CLPPool(
            factory.create(
                "Gyro 2CLP Pool",
                "GRP",
                vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
                _sqrtAlpha,
                _sqrtBeta,
                roleAccounts,
                0,
                address(0),
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        return address(newPool);
    }

    function calculateMinAndMaxSwapAmounts() internal virtual override {
        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // The vault does not allow trade amounts (amountGivenScaled18 or amountCalculatedScaled18) to be less than
        // PRODUCTION_MIN_TRADE_AMOUNT. For "linear pools" (PoolMock), amountGivenScaled18 and amountCalculatedScaled18
        // are the same. So, minAmountGivenScaled18 > PRODUCTION_MIN_TRADE_AMOUNT. To derive the formula below, note
        // that `amountGivenRaw = amountGivenScaled18/(rateToken * scalingFactor)`. There's an adjustment for stable
        // math in the following steps.
        uint256 tokenAMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenA).mulUp(10 ** decimalsTokenA);
        uint256 tokenBMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenB).mulUp(10 ** decimalsTokenB);

        // Also, since we undo the operation (reverse swap with the output of the first swap), amountCalculatedRaw
        // cannot be 0. Considering that amountCalculated is tokenB, and amountGiven is tokenA:
        // 1) amountCalculatedRaw > 0
        // 2) amountCalculatedRaw = amountCalculatedScaled18 * 10^(decimalsB) / (rateB * 10^18)
        // 3) amountCalculatedScaled18 = amountGivenScaled18 // Linear math, there's a factor to stable math
        // 4) amountGivenScaled18 = amountGivenRaw * rateA * 10^18 / 10^(decimalsA)
        // Combining the four formulas above, we determine that:
        // amountCalculatedRaw > rateB * 10^(decimalsA) / (rateA * 10^(decimalsB))
        uint256 tokenACalculatedNotZero = (rateTokenB * (10 ** decimalsTokenA)) / (rateTokenA * (10 ** decimalsTokenB));
        uint256 tokenBCalculatedNotZero = (rateTokenA * (10 ** decimalsTokenB)) / (rateTokenB * (10 ** decimalsTokenA));

        // Use the larger of the two values above to calculate the minSwapAmount. Also, multiply by 100 to account for
        // swap fees and compensate for rate and math rounding issues.
        uint256 mathFactor = 100;
        minSwapAmountTokenA = (
            tokenAMinTradeAmount > tokenACalculatedNotZero
                ? mathFactor * tokenAMinTradeAmount
                : mathFactor * tokenACalculatedNotZero
        );
        minSwapAmountTokenB = (
            tokenBMinTradeAmount > tokenBCalculatedNotZero
                ? mathFactor * tokenBMinTradeAmount
                : mathFactor * tokenBCalculatedNotZero
        );

        // 50% of pool init amount to make sure LP has enough tokens to pay for the swap in case of EXACT_OUT.
        maxSwapAmountTokenA = poolInitAmountTokenA.mulDown(50e16);
        maxSwapAmountTokenB = poolInitAmountTokenB.mulDown(50e16);
    }
}
