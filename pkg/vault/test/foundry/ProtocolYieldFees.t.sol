// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolYieldFeesTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    function setUp() public override {
        BaseVaultTest.setUp();
    }

    // Create wsteth / dai pool, with rate providers on wsteth (non-exempt), and dai (exempt)
    function createPool() internal override returns (address) {
        wstETHRateProvider = new RateProviderMock();
        daiRateProvider = new RateProviderMock();

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        bool[] memory yieldExemptFlags = new bool[](2);

        rateProviders[0] = wstETHRateProvider;
        rateProviders[1] = daiRateProvider;
        yieldExemptFlags[1] = true;

        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
            rateProviders,
            yieldExemptFlags,
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "pool");
        return address(newPool);
    }

    function setProtocolYieldFeePercentage(uint256 yieldFeePercentage) internal {
        bytes32 setFeeRole = vault.getActionId(IVaultExtension.setProtocolYieldFeePercentage.selector);
        authorizer.grantRole(setFeeRole, alice);

        vm.prank(alice);
        vault.setProtocolYieldFeePercentage(yieldFeePercentage);
    }

    function testPoolDataAfterInitialization(bool roundUp) public {
        pool = createPool();
        initPool();

        verifyLiveBalances(FixedPoint.ONE, FixedPoint.ONE, roundUp);
    }

    function testLiveBalancesWithRates(uint256 wstETHRate, uint256 daiRate, bool roundUp) public {
        wstETHRate = bound(wstETHRate, 1e18, 1.5e18);
        daiRate = bound(daiRate, 1e18, 1.5e18);

        pool = createPool();
        wstETHRateProvider.mockRate(wstETHRate);
        daiRateProvider.mockRate(daiRate);

        initPool();

        verifyLiveBalances(wstETHRate, daiRate, roundUp);
    }

    function testNoYieldFeesIfExempt(uint256 wstETHRate, uint256 daiRate, uint256 yieldFeePercentage, bool roundUp) public {
        wstETHRate = bound(wstETHRate, 1e18, 1.5e18);
        daiRate = bound(daiRate, 1e18, 1.5e18);
        // yield fee 1-20%
        yieldFeePercentage = bound(yieldFeePercentage, 0.01e18, 0.2e18);

        pool = createPool();
        wstETHRateProvider.mockRate(wstETHRate);
        daiRateProvider.mockRate(daiRate);

        initPool();

        uint256[] memory originalLiveBalances = verifyLiveBalances(wstETHRate, daiRate, roundUp);

        // Set non-zero yield fee
        setProtocolYieldFeePercentage(yieldFeePercentage);

        // Now raise both rates
        uint256 rateDelta = 0.2e18;
        wstETHRate += rateDelta;
        daiRate += rateDelta;

        wstETHRateProvider.mockRate(wstETHRate);
        daiRateProvider.mockRate(daiRate);

        // We should now have accrued yield fees
        uint256[] memory newLiveBalances = verifyLiveBalances(wstETHRate, daiRate, roundUp);
        uint256[] memory liveBalanceDeltas = new uint256[](2);

        for (uint256 i = 0; i < 2; i++) {
            liveBalanceDeltas[i] = newLiveBalances[i] - originalLiveBalances[i];
            // Balances should have increased
            assertTrue(liveBalanceDeltas[i] > 0);
        }

        // Should be no protocol fees on dai, since it is yield fee exempt
        assertEq(vault.getProtocolFees(address(dai)), 0);
        uint256[] memory scalingFactors = PoolMock(pool).getDecimalScalingFactors();

        // There should be fees on non-exempt wsteth
        uint256 actualProtocolFee = vault.getProtocolFees(address(wsteth));
        assertTrue(actualProtocolFee > 0);

        // How much should the fee be?
        // Tricky, because the diff already has the fee subtracted. Need to add it back in
        uint256 protocolFeeScaled18 = actualProtocolFee.toScaled18ApplyRateRoundDown(scalingFactors[0], wstETHRate);
        uint256 feeScaled18 = (liveBalanceDeltas[0] + protocolFeeScaled18).mulDown(yieldFeePercentage);
        uint256 expectedProtocolFee = feeScaled18.toRawUndoRateRoundDown(scalingFactors[0], wstETHRate);

        assertApproxEqAbs(actualProtocolFee, expectedProtocolFee, 1e3);
    }

    function verifyLiveBalances(uint256 wstETHRate, uint256 daiRate, bool roundUp) internal returns (uint256[] memory liveBalances) {
        PoolData memory data = vault.computePoolDataUpdatingBalancesAndFees(address(pool), roundUp ? Rounding.ROUND_UP : Rounding.ROUND_DOWN);

        uint256[] memory expectedScalingFactors = PoolMock(pool).getDecimalScalingFactors();
        uint256[] memory expectedRawBalances = vault.getRawBalances(address(pool));
        uint256[] memory expectedRates = new uint256[](2);

        expectedRates[0] = wstETHRate;
        expectedRates[1] = daiRate;

        uint256 expectedLiveBalance;

        for (uint256 i = 0; i < expectedRawBalances.length; i++) {
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

        return data.balancesLiveScaled18;
    }
}
