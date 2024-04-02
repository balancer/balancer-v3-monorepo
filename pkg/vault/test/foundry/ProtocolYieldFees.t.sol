// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { FEE_SCALING_FACTOR, PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { VaultStateLib } from "../../contracts/lib/VaultStateLib.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolYieldFeesTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    // Track the indices for the local dai/wsteth pool.
    uint256 internal wstethIdx;
    uint256 internal daiIdx;

    function setUp() public override {
        BaseVaultTest.setUp();

        (daiIdx, wstethIdx) = getSortedIndexes(address(dai), address(wsteth));
    }

    // Create wsteth / dai pool, with rate providers on wsteth (non-exempt), and dai (exempt)
    function createPool() internal override returns (address) {
        wstETHRateProvider = new RateProviderMock();
        daiRateProvider = new RateProviderMock();

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        bool[] memory yieldFeeFlags = new bool[](2);

        // These will be sorted with the tokens by buildTokenConfig.
        rateProviders[0] = wstETHRateProvider;
        rateProviders[1] = daiRateProvider;
        yieldFeeFlags[0] = true;

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

        factoryMock.registerTestPool(
            address(newPool),
            vault.buildTokenConfig(
                [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
                rateProviders,
                yieldFeeFlags
            )
        );

        vm.label(address(newPool), "pool");
        return address(newPool);
    }

    function setProtocolYieldFeePercentage(uint256 yieldFeePercentage) internal {
        bytes32 setFeeRole = vault.getActionId(IVaultAdmin.setProtocolYieldFeePercentage.selector);
        authorizer.grantRole(setFeeRole, alice);

        vm.prank(alice);
        vault.setProtocolYieldFeePercentage(yieldFeePercentage);
    }

    function testPoolDataAfterInitialization__Fuzz(bool roundUp) public {
        pool = createPool();
        initPool();

        verifyLiveBalances(FixedPoint.ONE, FixedPoint.ONE, roundUp);
    }

    function testLiveBalancesWithRates__Fuzz(uint256 wstethRate, uint256 daiRate, bool roundUp) public {
        wstethRate = bound(wstethRate, 1e18, 1.5e18);
        daiRate = bound(daiRate, 1e18, 1.5e18);

        pool = createPool();
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        initPool();

        verifyLiveBalances(wstethRate, daiRate, roundUp);
    }

    function testNoYieldFeesIfExempt__Fuzz(
        uint256 wstethRate,
        uint256 daiRate,
        uint256 yieldFeePercentage,
        bool roundUp
    ) public {
        wstethRate = bound(wstethRate, 1e18, 1.5e18);
        daiRate = bound(daiRate, 1e18, 1.5e18);

        // yield fee 0.000001-20%
        yieldFeePercentage = bound(yieldFeePercentage, 1, 2000000);
        // VaultState stores yieldFeePercentage as a 24 bits variable (from 0 to (2^24)-1, or 0% to ~167%)
        // Multiplying by FEE_SCALING_FACTOR (1e11) makes it 18 decimals scaled again
        yieldFeePercentage = yieldFeePercentage * FEE_SCALING_FACTOR;

        pool = createPool();
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        initPool();

        uint256[] memory originalLiveBalances = verifyLiveBalances(wstethRate, daiRate, roundUp);

        // Set non-zero yield fee
        setProtocolYieldFeePercentage(yieldFeePercentage);

        // Now raise both rates
        uint256 rateDelta = 0.2e18;
        wstethRate += rateDelta;
        daiRate += rateDelta;

        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        // We should now have accrued yield fees
        uint256[] memory newLiveBalances = verifyLiveBalances(wstethRate, daiRate, roundUp);
        uint256[] memory liveBalanceDeltas = new uint256[](2);

        for (uint256 i = 0; i < 2; i++) {
            liveBalanceDeltas[i] = newLiveBalances[i] - originalLiveBalances[i];
            // Balances should have increased
            assertTrue(liveBalanceDeltas[i] > 0, "Live balance delta is 0");
        }

        // Should be no protocol fees on dai, since it is yield fee exempt
        assertEq(vault.getProtocolFees(address(dai)), 0, "Protocol fees on exempt dai are not 0");
        uint256[] memory scalingFactors = PoolMock(pool).getDecimalScalingFactors();

        // There should be fees on non-exempt wsteth
        uint256 actualProtocolFee = vault.getProtocolFees(address(wsteth));
        assertTrue(actualProtocolFee > 0, "wstETH did not collect any protocol fees");

        // How much should the fee be?
        // Tricky, because the diff already has the fee subtracted. Need to add it back in
        uint256 protocolFeeScaled18 = actualProtocolFee.toScaled18ApplyRateRoundDown(
            scalingFactors[wstethIdx],
            wstethRate
        );
        uint256 feeScaled18 = (liveBalanceDeltas[wstethIdx] + protocolFeeScaled18).mulDown(yieldFeePercentage);
        uint256 expectedProtocolFee = feeScaled18.toRawUndoRateRoundDown(scalingFactors[wstethIdx], wstethRate);

        assertApproxEqAbs(actualProtocolFee, expectedProtocolFee, 1e3, "Actual protocol fee is not the expected one");
    }

    function testUpdateLiveTokenBalanceInPoolData__Fuzz(
        uint256 balanceRaw,
        uint8 decimals,
        uint256 tokenRate,
        bool roundUp
    ) public {
        balanceRaw = bound(balanceRaw, 0, 2 ** 120);
        decimals = uint8(bound(uint256(decimals), 2, 18));
        tokenRate = bound(tokenRate, 0, 100_000e18);
        uint256 decimalScalingFactor = getDecimalScalingFactor(decimals);

        PoolData memory poolData = _simplePoolData(balanceRaw, decimalScalingFactor, tokenRate);

        if (roundUp) {
            poolData = vault.updateLiveTokenBalanceInPoolData(poolData, Rounding.ROUND_UP, 0);
            assertEq(
                poolData.balancesLiveScaled18[0],
                balanceRaw.mulUp(decimalScalingFactor).mulUp(tokenRate),
                "Live scaled balance does not match (round up)"
            );
        } else {
            poolData = vault.updateLiveTokenBalanceInPoolData(poolData, Rounding.ROUND_DOWN, 0);
            assertEq(
                poolData.balancesLiveScaled18[0],
                balanceRaw.mulDown(decimalScalingFactor).mulDown(tokenRate),
                "Live scaled balance does not match (round down)"
            );
        }
    }

    function testComputeYieldProtocolFeesDue__Fuzz(
        uint256 balanceRaw,
        uint8 decimals,
        uint256 tokenRate,
        uint256 lastLiveBalance,
        uint256 yieldFeePercentage
    ) public {
        balanceRaw = bound(balanceRaw, 0, 2 ** 120);
        decimals = uint8(bound(uint256(decimals), 2, 18));
        tokenRate = bound(tokenRate, 0, 100_000e18);
        uint256 decimalScalingFactor = getDecimalScalingFactor(decimals);
        lastLiveBalance = bound(lastLiveBalance, 0, 2 ** 128);
        yieldFeePercentage = bound(yieldFeePercentage, 0, _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE);

        PoolData memory poolData = _simplePoolData(balanceRaw, decimalScalingFactor, tokenRate);
        uint256 liveBalance = poolData.balancesLiveScaled18[0];

        uint256 yieldFeesRaw = vault.computeYieldProtocolFeesDue(poolData, lastLiveBalance, 0, yieldFeePercentage);
        if (liveBalance <= lastLiveBalance) {
            assertEq(yieldFeesRaw, 0, "Yield fees are not 0 with decreasing live balance");
        } else {
            assertEq(
                yieldFeesRaw,
                (liveBalance - lastLiveBalance).mulDown(yieldFeePercentage).divDown(
                    decimalScalingFactor.mulDown(tokenRate)
                ),
                "Yield fees does not match the expected one"
            );
        }
    }

    function testYieldFeesOnSwap__Fuzz(uint256 wstethRate, uint256 daiRate) public {
        uint64 protocolYieldFeePercentage = 0.1e18;
        setProtocolYieldFeePercentage(protocolYieldFeePercentage); //  10%
        wstethRate = bound(wstethRate, 1e18, 1.5e18);
        daiRate = bound(daiRate, 1e18, 1.5e18);

        pool = createPool();
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        initPool();

        require(vault.getProtocolFees(address(dai)) == 0, "Initial protocol fees for DAI not 0");
        require(vault.getProtocolFees(address(wsteth)) == 0, "Initial protocol fees for wstETH not 0");

        // Pump the rates 10 times
        wstethRate *= 10;
        daiRate *= 10;
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        // Dummy swap
        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, dai, wsteth, 1e18, 0, MAX_UINT256, false, "");

        // No matter what the rates are, the value of wsteth grows from 1x to 10x.
        // Then, the protocol takes its cut out of the 9x difference.
        assertEq(
            vault.getProtocolFees(address(wsteth)),
            ((poolInitAmount * 9) / 10).mulDown(protocolYieldFeePercentage),
            "Yield fees for wstETH is not the expected one"
        );
        assertEq(vault.getProtocolFees(address(dai)), 0, "Yield fees for exempt dai are not 0");
    }

    function verifyLiveBalances(
        uint256 wstethRate,
        uint256 daiRate,
        bool roundUp
    ) internal returns (uint256[] memory liveBalances) {
        PoolData memory data = vault.computePoolDataUpdatingBalancesAndFees(
            address(pool),
            roundUp ? Rounding.ROUND_UP : Rounding.ROUND_DOWN
        );

        uint256[] memory expectedScalingFactors = PoolMock(pool).getDecimalScalingFactors();
        uint256[] memory expectedRawBalances = vault.getRawBalances(address(pool));
        uint256[] memory expectedRates = new uint256[](2);

        expectedRates[wstethIdx] = wstethRate;
        expectedRates[daiIdx] = daiRate;

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

            // Tolerate being off by 1 wei
            assertApproxEqAbs(data.balancesLiveScaled18[i], expectedLiveBalance, 1, "Live balance does not match");
        }

        return data.balancesLiveScaled18;
    }

    function _simplePoolData(
        uint256 balanceRaw,
        uint256 decimalScalingFactor,
        uint256 tokenRate
    ) internal pure returns (PoolData memory poolData) {
        poolData.balancesLiveScaled18 = new uint256[](1);
        poolData.balancesRaw = new uint256[](1);
        poolData.decimalScalingFactors = new uint256[](1);
        poolData.tokenRates = new uint256[](1);

        poolData.balancesRaw[0] = balanceRaw;
        poolData.decimalScalingFactors[0] = decimalScalingFactor;
        poolData.tokenRates[0] = tokenRate;
        uint256 liveBalance = balanceRaw.mulDown(decimalScalingFactor).mulDown(tokenRate);
        poolData.balancesLiveScaled18[0] = liveBalance;
    }
}
