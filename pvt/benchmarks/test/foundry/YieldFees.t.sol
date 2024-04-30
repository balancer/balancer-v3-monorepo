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

import { VaultStateLib } from "@balancer-labs/v3-vault/contracts/lib/VaultStateLib.sol";

import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

contract YieldFeesTest is BaseVaultTest {
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
            ),
            address(lp)
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

    function testSwapWithoutYieldFeesSnapshot() public {
        uint256 yieldFeePercentage;
        uint256 creatorYieldFeePercentage;

        // yield fee 20% and creator yield fees 100%
        (yieldFeePercentage, creatorYieldFeePercentage) = _initializeFees(
            yieldFeePercentage,
            creatorYieldFeePercentage,
            0,
            0
        );

        uint256 wstethRate = 1.3e18;
        uint256 daiRate = 1.3e18;

        _initializePoolAndRateProviders(wstethRate, daiRate);

        // Warm-up storage slots
        _testYieldFeesOnSwap(wstethRate, daiRate, 5, yieldFeePercentage, creatorYieldFeePercentage, false, "");

        _testYieldFeesOnSwap(
            wstethRate,
            daiRate,
            10,
            yieldFeePercentage,
            creatorYieldFeePercentage,
            true,
            "testSwapWithoutYieldFeesSnapshot"
        );
    }

    function testSwapWithProtocolYieldFeesSnapshot() public {
        uint256 yieldFeePercentage;
        uint256 creatorYieldFeePercentage;

        // yield fee 20% and creator yield fees 100%
        (yieldFeePercentage, creatorYieldFeePercentage) = _initializeFees(
            yieldFeePercentage,
            creatorYieldFeePercentage,
            2e6,
            0
        );

        uint256 wstethRate = 1.3e18;
        uint256 daiRate = 1.3e18;

        _initializePoolAndRateProviders(wstethRate, daiRate);

        // Warm-up storage slots
        _testYieldFeesOnSwap(wstethRate, daiRate, 5, yieldFeePercentage, creatorYieldFeePercentage, false, "");

        _testYieldFeesOnSwap(
            wstethRate,
            daiRate,
            10,
            yieldFeePercentage,
            creatorYieldFeePercentage,
            true,
            "testSwapWithProtocolYieldFeesSnapshot"
        );
    }

    function testSwapWithProtocolAndCreatorYieldFeesSnapshot() public {
        uint256 yieldFeePercentage;
        uint256 creatorYieldFeePercentage;

        // yield fee 20% and creator yield fees 100%
        (yieldFeePercentage, creatorYieldFeePercentage) = _initializeFees(
            yieldFeePercentage,
            creatorYieldFeePercentage,
            2e6,
            1e7
        );

        uint256 wstethRate = 1.3e18;
        uint256 daiRate = 1.3e18;

        _initializePoolAndRateProviders(wstethRate, daiRate);

        // Warm-up storage slots
        _testYieldFeesOnSwap(wstethRate, daiRate, 5, yieldFeePercentage, creatorYieldFeePercentage, false, "");

        _testYieldFeesOnSwap(
            wstethRate,
            daiRate,
            10,
            yieldFeePercentage,
            creatorYieldFeePercentage,
            true,
            "swapWithProtocolAndCreatorYieldFeesSnapshot"
        );
    }

    function _testYieldFeesOnSwap(
        uint256 wstethRate,
        uint256 daiRate,
        uint256 pumpRate,
        uint256 protocolYieldFeePercentage,
        uint256 creatorYieldFeePercentage,
        bool shouldSnap,
        string memory snapName
    ) private {
        setProtocolYieldFeePercentage(protocolYieldFeePercentage);
        // lp is the pool creator, the only user who can change the pool creator fee percentage
        vm.prank(lp);
        vault.setPoolCreatorFeePercentage(address(pool), creatorYieldFeePercentage);

        // Pump the rates [pumpRate] times
        wstethRate *= pumpRate;
        daiRate *= pumpRate;
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        // Dummy swap
        vm.prank(alice);
        if (shouldSnap) {
            snapStart(snapName);
        }
        router.swapSingleTokenExactIn(pool, dai, wsteth, 1e18, 0, MAX_UINT256, false, "");
        if (shouldSnap) {
            snapEnd();
        }
    }

    function _initializePoolAndRateProviders(uint256 wstethRate, uint256 daiRate) private {
        pool = createPool();
        wstETHRateProvider.mockRate(wstethRate);
        daiRateProvider.mockRate(daiRate);

        initPool();
    }

    function _initializeFees(
        uint256 yieldFeePercentage,
        uint256 creatorYieldFeePercentage,
        uint256 fixedYieldFee,
        uint256 fixedCreatorFee
    ) private returns (uint256 finalYieldFeePercentage, uint256 finalCreatorFeePercentage) {
        // Fees are stored as a 24 bits variable (from 0 to (2^24)-1, or 0% to ~167%) in vaultConfig and poolConfig
        // Multiplying by FEE_SCALING_FACTOR (1e11) makes it 18 decimals scaled again

        finalYieldFeePercentage = fixedYieldFee * FEE_SCALING_FACTOR;
        finalCreatorFeePercentage = fixedCreatorFee * FEE_SCALING_FACTOR;
    }
}
