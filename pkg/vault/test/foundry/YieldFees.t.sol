// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract YieldFeesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ScalingHelpers for uint256;
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    // Track the indices for the local dai/wsteth pool.
    uint256 internal wstethIdx;
    uint256 internal daiIdx;

    function setUp() public override {
        BaseVaultTest.setUp();

        (daiIdx, wstethIdx) = getSortedIndexes(address(dai), address(wsteth));
    }

    // Create wsteth / dai pool, with rate providers on wsteth (non-exempt), and dai (exempt).
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
            ),
            poolHooksContract,
            lp
        );

        vm.label(address(newPool), "pool");
        return address(newPool);
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

    struct YieldTestLocals {
        uint256 liveBalanceBeforeRaw;
        uint256 liveBalanceAfterRaw;
        uint256 expectedProtocolFee;
    }

    function testNoYieldFeesIfExempt__Fuzz(
        uint256 wstethRate,
        uint256 daiRate,
        uint256 aggregateYieldFeePercentage,
        bool roundUp
    ) public {
        wstethRate = bound(wstethRate, 1e18, 1.5e18);
        daiRate = bound(daiRate, 1e18, 1.5e18);
        aggregateYieldFeePercentage = bound(aggregateYieldFeePercentage, 1e12, 10e16);
        // Prevent PrecisionTooHigh error.
        aggregateYieldFeePercentage = (aggregateYieldFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;

        pool = createPool();
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        initPool();

        // Set non-zero yield fee.
        vault.manualSetAggregateYieldFeePercentage(pool, aggregateYieldFeePercentage);

        uint256[] memory originalLiveBalances = verifyLiveBalances(wstethRate, daiRate, roundUp);

        // Now raise both rates.
        uint256 rateDelta = 0.2e18;
        wstethRate += rateDelta;
        daiRate += rateDelta;

        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        // We should now have accrued yield fees.
        uint256[] memory newLiveBalances = verifyLiveBalances(wstethRate, daiRate, roundUp);
        uint256[] memory liveBalanceDeltas = new uint256[](2);

        for (uint256 i = 0; i < 2; ++i) {
            liveBalanceDeltas[i] = newLiveBalances[i] - originalLiveBalances[i];
            // Balances should have increased, but delta can be 0 if creator fee is 100%.
            assertTrue(liveBalanceDeltas[i] >= 0, "Live balance delta is 0");
        }

        // Should be no protocol fees on dai, since it is yield fee exempt.
        assertEq(vault.manualGetAggregateYieldFeeAmount(pool, dai), 0, "Protocol fees on exempt dai are not 0");

        // There should be fees on non-exempt wsteth.
        uint256 actualProtocolFee = vault.manualGetAggregateYieldFeeAmount(pool, wsteth);
        assertTrue(actualProtocolFee > 0, "wstETH did not collect any protocol fees");

        // How much should the fee be?
        // Tricky, because the diff already has the fee subtracted. Need to add it back in.
        YieldTestLocals memory vars;
        uint256[] memory scalingFactors = PoolMock(pool).getDecimalScalingFactors();
        vars.liveBalanceAfterRaw = liveBalanceDeltas[wstethIdx].toRawUndoRateRoundDown(
            scalingFactors[wstethIdx],
            wstethRate
        );
        vars.liveBalanceBeforeRaw = vars.liveBalanceAfterRaw + actualProtocolFee;
        vars.expectedProtocolFee = vars.liveBalanceBeforeRaw.mulDown(aggregateYieldFeePercentage);

        assertApproxEqAbs(actualProtocolFee, vars.expectedProtocolFee, 1e3, "Wrong protocol fee");
    }

    function testUpdateLiveTokenBalanceInPoolData__Fuzz(
        uint256 balanceRaw,
        uint8 decimals,
        uint256 tokenRate,
        bool roundUp
    ) public view {
        balanceRaw = bound(balanceRaw, 0, 2 ** 120);
        decimals = uint8(bound(uint256(decimals), 2, 18));
        tokenRate = bound(tokenRate, 0, 100_000e18);
        uint256 decimalScalingFactor = getDecimalScalingFactor(decimals);

        PoolData memory poolData = _simplePoolData(balanceRaw, decimalScalingFactor, tokenRate);

        if (roundUp) {
            poolData = vault.updateLiveTokenBalanceInPoolData(poolData, balanceRaw, Rounding.ROUND_UP, 0);
            assertEq(
                poolData.balancesLiveScaled18[0],
                balanceRaw.mulUp(decimalScalingFactor).mulUp(tokenRate),
                "Live scaled balance does not match (round up)"
            );
        } else {
            poolData = vault.updateLiveTokenBalanceInPoolData(poolData, balanceRaw, Rounding.ROUND_DOWN, 0);
            assertEq(
                poolData.balancesLiveScaled18[0],
                balanceRaw.mulDown(decimalScalingFactor).mulDown(tokenRate),
                "Live scaled balance does not match (round down)"
            );
        }
    }

    function testComputeYieldFeesDue__Fuzz(
        uint256 balanceRaw,
        uint8 decimals,
        uint256 tokenRate,
        uint256 lastLiveBalance,
        uint256 yieldFeePercentage
    ) public view {
        uint256 MAX_PROTOCOL_YIELD_FEE_PERCENTAGE = 50e16; // 50%

        balanceRaw = bound(balanceRaw, 0, 2 ** 120);
        decimals = uint8(bound(uint256(decimals), 2, 18));
        tokenRate = bound(tokenRate, 0, 100_000e18);
        uint256 decimalScalingFactor = getDecimalScalingFactor(decimals);
        lastLiveBalance = bound(lastLiveBalance, 0, 2 ** 128);
        yieldFeePercentage = bound(yieldFeePercentage, 0, MAX_PROTOCOL_YIELD_FEE_PERCENTAGE);

        PoolData memory poolData = _simplePoolData(balanceRaw, decimalScalingFactor, tokenRate);
        uint256 liveBalance = poolData.balancesLiveScaled18[0];

        uint256 protocolYieldFeesRaw = vault.computeYieldFeesDue(poolData, lastLiveBalance, 0, yieldFeePercentage);
        if (liveBalance <= lastLiveBalance) {
            assertEq(protocolYieldFeesRaw, 0, "Yield fees are not 0 with decreasing live balance");
        } else {
            assertEq(
                protocolYieldFeesRaw,
                (liveBalance - lastLiveBalance).mulUp(yieldFeePercentage).divDown(
                    decimalScalingFactor.mulDown(tokenRate)
                ),
                "Wrong protocol yield fees"
            );
        }
    }

    function testYieldFeesOnSwap__Fuzz(
        uint256 wstethRate,
        uint256 daiRate,
        uint256 aggregateYieldFeePercentage
    ) public {
        aggregateYieldFeePercentage = bound(aggregateYieldFeePercentage, 1e12, 10e16);
        // Prevent PrecisionTooHigh error.
        aggregateYieldFeePercentage = (aggregateYieldFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;

        wstethRate = bound(wstethRate, 1e18, 1.5e18);
        daiRate = bound(daiRate, 1e18, 1.5e18);

        _testYieldFeesOnSwap(wstethRate, daiRate, aggregateYieldFeePercentage);
    }

    function testYieldFeesOnSwap() public {
        // Protocol yield fee 20%, and pool creator yield fees 100%.
        uint256 protocolYieldFeePercentage = 20e16;
        uint256 poolCreatorFeePercentage = 100e16;

        uint256 aggregateYieldFeePercentage = feeController.computeAggregateFeePercentage(
            protocolYieldFeePercentage,
            poolCreatorFeePercentage
        );

        uint256 wstethRate = 1.3e18;
        uint256 daiRate = 1.3e18;

        _testYieldFeesOnSwap(wstethRate, daiRate, aggregateYieldFeePercentage);
    }

    function _testYieldFeesOnSwap(uint256 wstethRate, uint256 daiRate, uint256 aggregateYieldFeePercentage) private {
        pool = createPool();
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        initPool();

        require(vault.manualGetAggregateYieldFeeAmount(pool, dai) == 0, "Initial protocol fees for DAI not 0");
        require(vault.manualGetAggregateYieldFeeAmount(pool, wsteth) == 0, "Initial protocol fees for wstETH not 0");

        vault.manualSetAggregateYieldFeePercentage(pool, aggregateYieldFeePercentage);

        // Pump the rates 10 times.
        wstethRate *= 10;
        daiRate *= 10;
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        // Dummy swap.
        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, dai, wsteth, 1e18, 0, MAX_UINT256, false, "");

        // No matter what the rates are, the value of wsteth grows from 1x to 10x.
        // Then, the protocol takes its cut out of the 9x difference.

        assertApproxEqAbs(
            vault.manualGetAggregateYieldFeeAmount(pool, wsteth),
            ((poolInitAmount * 9) / 10).mulDown(aggregateYieldFeePercentage),
            1e3,
            "Yield fees for wstETH is not the expected one"
        );
        assertEq(vault.manualGetAggregateYieldFeeAmount(pool, dai), 0, "Yield fees for exempt dai are not 0");
    }

    function verifyLiveBalances(
        uint256 wstethRate,
        uint256 daiRate,
        bool roundUp
    ) internal returns (uint256[] memory liveBalances) {
        PoolData memory data = vault.loadPoolDataUpdatingBalancesAndYieldFees(
            pool,
            roundUp ? Rounding.ROUND_UP : Rounding.ROUND_DOWN
        );

        uint256[] memory expectedScalingFactors = PoolMock(pool).getDecimalScalingFactors();
        uint256[] memory expectedRawBalances = vault.getRawBalances(pool);
        uint256[] memory expectedRates = new uint256[](2);

        expectedRates[wstethIdx] = wstethRate;
        expectedRates[daiIdx] = daiRate;

        uint256 expectedLiveBalance;

        for (uint256 i = 0; i < expectedRawBalances.length; ++i) {
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

            // Tolerate being off by 1 wei.
            assertApproxEqAbs(data.balancesLiveScaled18[i], expectedLiveBalance, 1, "Wrong live balances");
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

    function _initializeFees(
        uint256 protocolFeePercentage,
        uint256 creatorFeePercentage
    ) private pure returns (uint256 finalProtocolFeePercentage, uint256 finalCreatorFeePercentage) {
        // Fees are stored as a 24 bits variable (from 0 to (2^24)-1, or 0% to ~167%) in vaultConfig and poolConfigBits
        // Multiplying by FEE_SCALING_FACTOR (1e11) makes it 18 decimals scaled again.

        // Yield fee 0.000001-20%.
        finalProtocolFeePercentage = bound(protocolFeePercentage, 1, 2e6) * FEE_SCALING_FACTOR;

        // Creator yield fees 1-100%.
        finalCreatorFeePercentage = bound(creatorFeePercentage, 1, 1e7) * FEE_SCALING_FACTOR;
    }
}
