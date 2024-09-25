// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { E2eSwapRateProviderTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwapRateProvider.t.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract E2eSwapRateProviderStableTest is E2eSwapRateProviderTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        rateProviderTokenA = new RateProviderMock();
        rateProviderTokenB = new RateProviderMock();
        // Mock rates, so all tests that keep the rate constant use a rate different than 1.
        rateProviderTokenA.mockRate(5.2453235e18);
        rateProviderTokenB.mockRate(0.4362784e18);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[tokenAIdx] = IRateProvider(address(rateProviderTokenA));
        rateProviders[tokenBIdx] = IRateProvider(address(rateProviderTokenB));

        StablePoolFactory factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        StablePool newPool = StablePool(
            factory.create(
                "Stable Pool",
                "STABLE",
                vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                DEFAULT_SWAP_FEE, // 1% swap fee, but test will override it
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
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
        // 4) amountGivenScaled18 = amountGivenRaw * rateA * 10^18 / 10^(decumalsA)
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

    function testMockPoolBalanceWithRate() public {
        uint tokenAmount = 1179465241898852517841248;
        uint dustAmount = 2;
        vault.manualSetPoolTokensAndBalances(
            pool,
            [address(tokenA), address(tokenB)].toMemoryArray().asIERC20(),
            [tokenAmount, dustAmount].toMemoryArray(),
            [tokenAmount, dustAmount].toMemoryArray()
        );

        rateProviderTokenA.mockRate(1e18);
        rateProviderTokenB.mockRate(1e18);
        vm.startPrank(lp);

        uint256[] memory exactAmountsIn = [tokenAmount, uint(0)].toMemoryArray();
        uint mintLp = router.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, "");
        uint lpBurned = router.removeLiquiditySingleTokenExactOut(pool, 1e50, usdc, tokenAmount, false, "");
        vm.assertGt(mintLp, lpBurned);
    }

    function testFuzzEdgeTokenAmount(uint tokenAmount) public {
        tokenAmount = bound(tokenAmount, 1e6 ether, 1e12 ether);
        uint dustAmount = 2;
        uint[] memory currentBalances = [tokenAmount, dustAmount].toMemoryArray();
        bool first = false;
        bool second = false;
        uint256 invariantA;
        uint256 invariantB;
        try StablePool(pool).computeInvariant(currentBalances, Rounding.ROUND_UP) returns (uint256 invariant) {
            first = true;
            invariantA = invariant;
        } catch {
        }
        if(first) {
            currentBalances = [tokenAmount, dustAmount + 1].toMemoryArray();
            try StablePool(pool).computeInvariant(currentBalances, Rounding.ROUND_DOWN) returns (uint256 invariant) {
                second = true;
                invariantB = invariant;
            } catch {
            }
        }

        if (second) {
            assertFalse(true);
            assertGe(invariantB, invariantA, "Invariant decreased");
        }
    }
}
