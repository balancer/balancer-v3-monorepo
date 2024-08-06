// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract PoolDataTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        wstETHRateProvider = new RateProviderMock();
        daiRateProvider = new RateProviderMock();

        // Providers will be sorted along with the tokens by `buildTokenConfig`.
        rateProviders[0] = daiRateProvider;
        rateProviders[1] = wstETHRateProvider;

        address newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        factoryMock.registerTestPool(
            newPool,
            vault.buildTokenConfig([address(dai), address(wsteth)].toMemoryArray().asIERC20(), rateProviders),
            poolHooksContract,
            lp
        );

        return newPool;
    }

    function testPoolData__Fuzz(uint256 daiRate, uint256 wstETHRate, bool roundUp) public {
        daiRate = bound(daiRate, 1, 100e18);
        wstETHRate = bound(wstETHRate, 1, 100e18);

        daiRateProvider.mockRate(daiRate);
        wstETHRateProvider.mockRate(wstETHRate);

        // `loadPoolDataUpdatingBalancesAndYieldFees` and `getRawBalances` are functions in VaultMock.

        PoolData memory data = vault.loadPoolDataUpdatingBalancesAndYieldFees(
            pool,
            roundUp ? Rounding.ROUND_UP : Rounding.ROUND_DOWN
        );

        // Compute decimal scaling factors from the tokens, in the mock.
        uint256[] memory expectedScalingFactors = PoolMock(pool).getDecimalScalingFactors();
        uint256[] memory expectedRawBalances = vault.getRawBalances(pool);
        uint256[] memory expectedRates = new uint256[](2);
        expectedRates[0] = daiRate;
        expectedRates[1] = wstETHRate;

        uint256 expectedLiveBalance;

        for (uint256 i = 0; i < expectedRawBalances.length; ++i) {
            assertEq(data.decimalScalingFactors[i], expectedScalingFactors[i]);
            assertEq(data.balancesRaw[i], expectedRawBalances[i]);
            assertEq(data.tokenRates[i], expectedRates[i]);

            if (roundUp) {
                expectedLiveBalance = FixedPoint.mulUp(
                    expectedRawBalances[i],
                    expectedScalingFactors[i].mulUp(expectedRates[i])
                );
            } else {
                expectedLiveBalance = FixedPoint.mulDown(
                    expectedRawBalances[i],
                    expectedScalingFactors[i].mulDown(expectedRates[i])
                );
            }

            assertEq(data.balancesLiveScaled18[i], expectedLiveBalance);
        }

        assertEq(address(data.tokens[0]), address(dai));
        assertEq(address(data.tokens[1]), address(wsteth));

        assertEq(address(data.tokenInfo[0].rateProvider), address(daiRateProvider));
        assertEq(address(data.tokenInfo[1].rateProvider), address(wstETHRateProvider));
    }
}
