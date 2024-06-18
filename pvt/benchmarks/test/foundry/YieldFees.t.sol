// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { FEE_SCALING_FACTOR, PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

contract YieldFeesTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    RateProviderMock internal wstETHRateProvider;
    RateProviderMock internal daiRateProvider;

    WeightedPool internal weightedPoolWithRate;
    WeightedPoolFactory internal factory;

    // Track the indices for the local dai/wsteth pool.
    uint256 internal wstethIdx;
    uint256 internal daiIdx;
    uint256 constant swapFee = 1e16; // 1%

    function setUp() public override {
        BaseVaultTest.setUp();

        (daiIdx, wstethIdx) = getSortedIndexes(address(dai), address(wsteth));
    }

    // Create wsteth / dai pool, with rate providers on wsteth (non-exempt), and dai (exempt)
    function createPool() internal override returns (address) {
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        wstETHRateProvider = new RateProviderMock();
        daiRateProvider = new RateProviderMock();

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        bool[] memory yieldFeeFlags = new bool[](2);

        // These will be sorted with the tokens by buildTokenConfig.
        rateProviders[0] = wstETHRateProvider;
        rateProviders[1] = daiRateProvider;
        yieldFeeFlags[0] = true;
        yieldFeeFlags[1] = true;

        PoolRoleAccounts memory poolRoleAccounts;

        weightedPoolWithRate = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(
                    [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
                    rateProviders,
                    yieldFeeFlags
                ),
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                poolRoleAccounts,
                swapFee,
                address(0),
                bytes32(0)
            )
        );

        vm.label(address(weightedPoolWithRate), "weightedPoolWithRate");
        return address(weightedPoolWithRate);
    }

    function testSwapWithoutYieldFeesSnapshot() public {
        uint256 yieldFeePercentage;
        uint256 creatorYieldFeePercentage;

        uint256 wstethRate = 1.3e18;
        uint256 daiRate = 1.3e18;

        _testYieldFeesOnSwap(wstethRate, daiRate, 10, yieldFeePercentage, creatorYieldFeePercentage);
    }

    function testSwapWithProtocolYieldFeesSnapshot() public {
        // yield fee 20% and creator yield fees 100%
        (uint256 yieldFeePercentage, uint256 creatorYieldFeePercentage) = _initializeFees(2e6, 0);

        uint256 wstethRate = 1.3e18;
        uint256 daiRate = 1.3e18;

        _testYieldFeesOnSwap(wstethRate, daiRate, 10, yieldFeePercentage, creatorYieldFeePercentage);
    }

    function testSwapWithProtocolAndCreatorYieldFeesSnapshot() public {
        (uint256 yieldFeePercentage, uint256 creatorYieldFeePercentage) = _initializeFees(2e6, 1e7);

        uint256 wstethRate = 1.3e18;
        uint256 daiRate = 1.3e18;

        _testYieldFeesOnSwap(wstethRate, daiRate, 10, yieldFeePercentage, creatorYieldFeePercentage);
    }

    function _testYieldFeesOnSwap(
        uint256 wstethRate,
        uint256 daiRate,
        uint256 pumpRate,
        uint256 protocolYieldFeePercentage,
        uint256 creatorYieldFeePercentage
    ) private {
        _initializePoolAndRateProviders(wstethRate, daiRate);

        vault.manualSetAggregateYieldFeePercentage(
            pool,
            _getAggregateFeePercentage(protocolYieldFeePercentage, creatorYieldFeePercentage)
        );

        // Warm-up storage slots (using a different pool)
        // Pump the original rates [pumpRate / 2] times
        wstETHRateProvider.mockRate((wstethRate * pumpRate) / 2);
        daiRateProvider.mockRate((daiRate * pumpRate) / 2);

        vm.prank(alice);
        uint256 amountOut = router.swapSingleTokenExactIn(pool, dai, wsteth, 1e18, 0, MAX_UINT256, false, "");

        // Pump the original rates [pumpRate] times
        wstETHRateProvider.mockRate(wstethRate * pumpRate);
        daiRateProvider.mockRate(daiRate * pumpRate);

        // Dummy swap
        vm.prank(alice);
        router.swapSingleTokenExactIn(pool, wsteth, dai, amountOut, 0, MAX_UINT256, false, "");
    }

    function _initializePoolAndRateProviders(uint256 wstethRate, uint256 daiRate) private {
        pool = createPool();
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        initPool();
    }

    function _initializeFees(
        uint256 fixedYieldFee,
        uint256 fixedCreatorFee
    ) private pure returns (uint256 finalYieldFeePercentage, uint256 finalCreatorFeePercentage) {
        // Fees are stored as a 24 bits variable (from 0 to (2^24)-1, or 0% to ~167%) in vaultConfig and poolConfigBits
        // Multiplying by FEE_SCALING_FACTOR (1e11) makes it 18 decimals scaled again

        finalYieldFeePercentage = fixedYieldFee * FEE_SCALING_FACTOR;
        finalCreatorFeePercentage = fixedCreatorFee * FEE_SCALING_FACTOR;
    }
}
