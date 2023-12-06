// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault, PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { Router } from "../../contracts/Router.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

contract PoolDataTest is Test {
    using AssetHelpers for *;
    using ArrayHelpers for address[2];
    using FixedPoint for uint256;

    VaultMock vault;
    Router router;
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    ERC20TestToken WSTETH;
    ERC20TestToken DAI;
    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), new WETHTestToken());
        WSTETH = new ERC20TestToken("WSTETH", "WSTETH", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        wstETHRateProvider = new RateProviderMock();
        daiRateProvider = new RateProviderMock();

        rateProviders[0] = daiRateProvider;
        rateProviders[1] = wstETHRateProvider;

        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(WSTETH)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );
    }

    function testPoolData(uint256 daiRate, uint256 wstETHRate, bool roundUp) public {
        daiRate = bound(daiRate, 1, 100e18);
        wstETHRate = bound(wstETHRate, 1, 100e18);

        daiRateProvider.mockRate(daiRate);
        wstETHRateProvider.mockRate(wstETHRate);

        // `getPoolData` and `getRawBalances` are functions in VaultMock.

        PoolData memory data = vault.getPoolData(address(pool), roundUp ? Rounding.ROUND_UP : Rounding.ROUND_DOWN);

        // Compute decimal scaling factors from the tokens, in the mock.
        uint256[] memory expectedScalingFactors = pool.getDecimalScalingFactors();
        uint256[] memory expectedRawBalances = vault.getRawBalances(address(pool));
        uint256[] memory expectedRates = new uint256[](2);
        expectedRates[0] = daiRate;
        expectedRates[1] = wstETHRate;

        uint256 expectedLiveBalance;

        for (uint256 i = 0; i < expectedRawBalances.length; i++) {
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

        assertEq(address(data.tokens[0]), address(DAI));
        assertEq(address(data.tokens[1]), address(WSTETH));

        assertEq(address(data.rateProviders[0]), address(daiRateProvider));
        assertEq(address(data.rateProviders[1]), address(wstETHRateProvider));
    }
}
