// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

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

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        wstETHRateProvider = deployRateProviderMock();
        daiRateProvider = deployRateProviderMock();

        // Providers will be sorted along with the tokens by `buildTokenConfig`.
        rateProviders[0] = daiRateProvider;
        rateProviders[1] = wstETHRateProvider;

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));

        factoryMock.registerTestPool(
            newPool,
            vault.buildTokenConfig([address(dai), address(wsteth)].toMemoryArray().asIERC20(), rateProviders),
            poolHooksContract(),
            lp
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    function testPoolData__Fuzz(uint256 daiRate, uint256 wstETHRate, bool roundUp) public {
        daiRate = bound(daiRate, 1, 100e18);
        wstETHRate = bound(wstETHRate, 1, 100e18);

        daiRateProvider.mockRate(daiRate);
        wstETHRateProvider.mockRate(wstETHRate);

        // `loadPoolDataUpdatingBalancesAndYieldFees` and `getRawBalances` are functions in VaultMock.

        PoolData memory data = vault.loadPoolDataUpdatingBalancesAndYieldFees(
            pool(),
            roundUp ? Rounding.ROUND_UP : Rounding.ROUND_DOWN
        );

        // Compute decimal scaling factors from the tokens, in the mock.
        uint256[] memory expectedScalingFactors = PoolMock(pool()).getDecimalScalingFactors();
        uint256[] memory expectedRawBalances = vault.getRawBalances(pool());
        uint256[] memory expectedRates = new uint256[](2);
        expectedRates[0] = daiRate;
        expectedRates[1] = wstETHRate;

        uint256 expectedLiveBalance;

        for (uint256 i = 0; i < expectedRawBalances.length; ++i) {
            assertEq(data.decimalScalingFactors[i], expectedScalingFactors[i], "Wrong decimal scaling factor");
            assertEq(data.balancesRaw[i], expectedRawBalances[i], "Wrong raw balance");
            assertEq(data.tokenRates[i], expectedRates[i], "Wrong rate");

            if (roundUp) {
                expectedLiveBalance = FixedPoint.mulUp(
                    expectedRawBalances[i] * expectedScalingFactors[i],
                    expectedRates[i]
                );
            } else {
                expectedLiveBalance = FixedPoint.mulDown(
                    expectedRawBalances[i] * expectedScalingFactors[i],
                    expectedRates[i]
                );
            }

            assertEq(data.balancesLiveScaled18[i], expectedLiveBalance, "Wrong live balance");
        }

        assertEq(address(data.tokens[0]), address(dai));
        assertEq(address(data.tokens[1]), address(wsteth));

        assertEq(address(data.tokenInfo[0].rateProvider), address(daiRateProvider));
        assertEq(address(data.tokenInfo[1].rateProvider), address(wstETHRateProvider));
    }
}
