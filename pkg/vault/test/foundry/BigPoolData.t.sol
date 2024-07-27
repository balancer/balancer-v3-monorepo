// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenInfo, PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BigPoolDataTest is BaseVaultTest {
    using FixedPoint for uint256;

    IRateProvider[] internal bigPoolRateProviders;
    IERC20[] internal bigPoolTokens;
    uint256[] internal initAmounts;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        uint256 numTokens = vault.getMaximumPoolTokens();

        bigPoolRateProviders = new IRateProvider[](numTokens);
        bigPoolTokens = new IERC20[](numTokens);
        initAmounts = new uint256[](numTokens);

        for (uint8 i = 0; i < numTokens; ++i) {
            bigPoolTokens[i] = createERC20(string.concat("TKN", Strings.toString(i)), 18 - i);
            ERC20TestToken(address(bigPoolTokens[i])).mint(lp, poolInitAmount);
            bigPoolRateProviders[i] = new RateProviderMock();
            initAmounts[i] = poolInitAmount;
        }

        address newPool = address(new PoolMock(IVault(address(vault)), "Big Pool", "BIGPOOL"));

        _approveForPool(IERC20(newPool));

        factoryMock.registerTestPool(
            address(newPool),
            vault.buildTokenConfig(bigPoolTokens, bigPoolRateProviders),
            poolHooksContract,
            lp
        );

        // Get the sorted list of tokens and rate providers.
        TokenInfo[] memory tokenInfo = new TokenInfo[](numTokens);
        (bigPoolTokens, tokenInfo, , ) = vault.getPoolTokenInfo(newPool);

        for (uint8 i = 0; i < numTokens; ++i) {
            bigPoolRateProviders[i] = tokenInfo[i].rateProvider;
        }

        return newPool;
    }

    function initPool() internal override {
        vm.startPrank(lp);
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();
    }

    function _approveForSender() internal {
        for (uint256 i = 0; i < bigPoolTokens.length; ++i) {
            bigPoolTokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(bigPoolTokens[i]), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(bigPoolTokens[i]), address(batchRouter), type(uint160).max, type(uint48).max);
        }
    }

    function _approveForPool(IERC20 bpt) internal {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);

            _approveForSender();

            bpt.approve(address(router), type(uint256).max);
            bpt.approve(address(batchRouter), type(uint256).max);

            IERC20(bpt).approve(address(permit2), type(uint256).max);
            permit2.approve(address(bpt), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(bpt), address(batchRouter), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }
    }

    function testPoolData__Fuzz(uint256[8] memory rates, bool roundUp) public {
        uint256 numTokens = vault.getMaximumPoolTokens();

        for (uint256 i = 0; i < numTokens; ++i) {
            rates[i] = bound(rates[i], 1, 100e18);
            RateProviderMock(address(bigPoolRateProviders[i])).mockRate(rates[i]);
        }

        // `loadPoolDataUpdatingBalancesAndYieldFees` and `getRawBalances` are functions in VaultMock.

        PoolData memory data = vault.loadPoolDataUpdatingBalancesAndYieldFees(
            pool,
            roundUp ? Rounding.ROUND_UP : Rounding.ROUND_DOWN
        );

        // Compute decimal scaling factors from the tokens, in the mock.
        uint256[] memory expectedScalingFactors = PoolMock(pool).getDecimalScalingFactors();
        uint256[] memory expectedRawBalances = vault.getRawBalances(pool);
        uint256 expectedLiveBalance;

        for (uint256 i = 0; i < expectedRawBalances.length; ++i) {
            assertEq(data.decimalScalingFactors[i], expectedScalingFactors[i]);
            assertEq(data.balancesRaw[i], expectedRawBalances[i]);
            assertEq(data.tokenRates[i], rates[i]);

            if (roundUp) {
                expectedLiveBalance = FixedPoint.mulUp(
                    expectedRawBalances[i],
                    expectedScalingFactors[i].mulUp(rates[i])
                );
            } else {
                expectedLiveBalance = FixedPoint.mulDown(
                    expectedRawBalances[i],
                    expectedScalingFactors[i].mulDown(rates[i])
                );
            }

            assertEq(data.balancesLiveScaled18[i], expectedLiveBalance);
        }

        for (uint256 i = 0; i < numTokens; ++i) {
            assertEq(address(data.tokens[i]), address(bigPoolTokens[i]));

            assertEq(address(data.tokenInfo[i].rateProvider), address(bigPoolRateProviders[i]));
        }
    }
}
