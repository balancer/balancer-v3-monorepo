// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SwapParams,
    SwapLocals,
    PoolData,
    SwapKind,
    TokenConfig,
    TokenType,
    Rounding
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

contract VaultUnitTest is BaseTest {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using FixedPoint for *;

    IVaultMock internal vault;

    address pool = address(0x1234);
    uint256 amountGivenRaw = 1 ether;
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];

    function setUp() public virtual override {
        BaseTest.setUp();
        vault = IVaultMock(address(VaultMockDeployer.deploy()));
    }

    function testGetSwapFeePercentageIfHasDynamicSwapFee() public {
        PoolConfig memory config;
        config.hasDynamicSwapFee = true;

        assertEq(vault.manualGetSwapFeePercentage(config), 0, "Unexpected swap fee percentage");
    }

    function testGetSwapFeePercentageIfHasNoDynamicSwapFee() public {
        PoolConfig memory config;
        config.staticSwapFeePercentage = 5e16;

        assertEq(
            vault.manualGetSwapFeePercentage(config),
            config.staticSwapFeePercentage,
            "Unexpected swap fee percentage"
        );
    }

    function testBuildPoolSwapParams() public {
        SwapParams memory params;
        params.kind = SwapKind.EXACT_IN;
        params.userData = new bytes(20);
        params.userData[0] = 0x01;
        params.userData[19] = 0x05;

        SwapLocals memory vars;
        vars.amountGivenScaled18 = 2e18;
        vars.indexIn = 3;
        vars.indexOut = 4;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = [uint256(1e18), 1e18].toMemoryArray();

        IBasePool.PoolSwapParams memory poolSwapParams = vault.manualBuildPoolSwapParams(params, vars, poolData);

        assertEq(uint8(poolSwapParams.kind), uint8(params.kind), "Unexpected kind");
        assertEq(poolSwapParams.amountGivenScaled18, vars.amountGivenScaled18, "Unexpected amountGivenScaled18");
        assertEq(
            keccak256(abi.encodePacked(poolSwapParams.balancesScaled18)),
            keccak256(abi.encodePacked(poolData.balancesLiveScaled18)),
            "Unexpected balancesScaled18"
        );
        assertEq(poolSwapParams.indexIn, vars.indexIn, "Unexpected indexIn");
        assertEq(poolSwapParams.indexOut, vars.indexOut, "Unexpected indexOut");
        assertEq(poolSwapParams.sender, address(this), "Unexpected sender");
        assertEq(poolSwapParams.userData, params.userData, "Unexpected userData");
    }

    function testComputeAndChargeProtocolFees() public {
        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;

        uint swapFeeAmountScaled18 = 1e18;
        uint protocolSwapFeePercentage_ = 10e16;

        uint expectSwapFeeAmountScaled18 = swapFeeAmountScaled18
            .mulUp(protocolSwapFeePercentage_)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[0], poolData.tokenRates[0]);

        vm.expectEmit();
        emit IVaultEvents.ProtocolSwapFeeCharged(pool, address(dai), expectSwapFeeAmountScaled18);

        uint256 protocolSwapFeeAmountRaw = vault.manualComputeAndChargeProtocolFees(
            poolData,
            swapFeeAmountScaled18,
            protocolSwapFeePercentage_,
            pool,
            dai,
            0
        );

        assertEq(protocolSwapFeeAmountRaw, expectSwapFeeAmountScaled18, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(vault.getProtocolFees(address(dai)), protocolSwapFeeAmountRaw, "Unexpected protocol fees in storage");
    }

    function testComputeAndChargeProtocolFeesIfPoolIsInRecoveryMode() public {
        PoolData memory poolData;
        poolData.poolConfig.isPoolInRecoveryMode = true;

        uint256 protocolSwapFeeAmountRaw = vault.manualComputeAndChargeProtocolFees(
            poolData,
            1e18,
            10e16,
            pool,
            dai,
            0
        );

        assertEq(protocolSwapFeeAmountRaw, 0, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(vault.getProtocolFees(address(dai)), 0, "Unexpected protocol fees in storage");
    }

    function testComputeAndChargeProtocolAndCreatorFees() public {
        uint256 initVault = 10e18;
        vault.manualSetPoolCreatorFees(pool, dai, initVault);

        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;

        uint swapFeeAmountScaled18 = 1e18;
        uint protocolSwapFeePercentage_ = 5e16;
        uint creatorFeePercentage = 5e16;

        uint expectSwapFeeAmountScaled18 = swapFeeAmountScaled18
            .mulUp(protocolSwapFeePercentage_)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[0], poolData.tokenRates[0]);

        uint expectCreatorFeeAmountRaw = (swapFeeAmountScaled18 - expectSwapFeeAmountScaled18)
            .mulUp(creatorFeePercentage)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[0], poolData.tokenRates[0]);

        vm.expectEmit();
        emit IVaultEvents.ProtocolSwapFeeCharged(pool, address(dai), expectSwapFeeAmountScaled18);

        vm.expectEmit();
        emit IVaultEvents.PoolCreatorFeeCharged(pool, address(dai), expectCreatorFeeAmountRaw);

        (uint256 protocolSwapFeeAmountRaw, uint256 creatorSwapFeeAmountRaw) = vault
            .manualComputeAndChargeProtocolAndCreatorFees(
                poolData,
                swapFeeAmountScaled18,
                protocolSwapFeePercentage_,
                creatorFeePercentage,
                pool,
                dai,
                0
            );

        assertEq(protocolSwapFeeAmountRaw, expectSwapFeeAmountScaled18, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(creatorSwapFeeAmountRaw, expectCreatorFeeAmountRaw, "Unexpected creatorSwapFeeAmountRaw");
        assertEq(
            vault.getPoolCreatorFees(pool, dai),
            initVault + creatorSwapFeeAmountRaw,
            "Unexpected creator fees in storage"
        );
    }

    function testManualUpdatePoolDataLiveBalancesAndRates() public {
        PoolData memory poolData;
        poolData.balancesRaw = new uint256[](2);
        poolData.tokenRates = new uint256[](2);
        poolData.balancesLiveScaled18 = new uint256[](2);

        poolData.decimalScalingFactors = decimalScalingFactors;

        poolData.tokenConfig = new TokenConfig[](2);
        poolData.tokenConfig[0].tokenType = TokenType.STANDARD;
        poolData.tokenConfig[1].tokenType = TokenType.STANDARD;

        uint256[] memory tokenBalances = [uint256(1e18), 2e18].toMemoryArray();

        IERC20[] memory defaultTokens = new IERC20[](2);
        defaultTokens[0] = dai;
        defaultTokens[1] = usdc;

        vault.manualSetPoolTokenBalances(pool, defaultTokens, tokenBalances);

        poolData = vault.manualUpdatePoolDataLiveBalancesAndRates(pool, poolData, Rounding.ROUND_UP);

        // check _updateTokenRatesInPoolData is called
        assertEq(poolData.tokenRates[0], FixedPoint.ONE, "Unexpected tokenRates[0]");
        assertEq(poolData.tokenRates[1], FixedPoint.ONE, "Unexpected tokenRates[1]");

        // check balances
        assertEq(poolData.balancesRaw[0], tokenBalances[0], "Unexpected balancesRaw[0]");
        assertEq(poolData.balancesRaw[1], tokenBalances[1], "Unexpected balancesRaw[1]");

        // check _updateLiveTokenBalanceInPoolData is called
        assertEq(
            poolData.balancesLiveScaled18[0],
            poolData.balancesRaw[0].mulUp(poolData.decimalScalingFactors[0]).mulUp(poolData.tokenRates[0]),
            "Unexpected balancesLiveScaled18[0]"
        );
        assertEq(
            poolData.balancesLiveScaled18[1],
            poolData.balancesRaw[1].mulUp(poolData.decimalScalingFactors[1]).mulUp(poolData.tokenRates[1]),
            "Unexpected balancesLiveScaled18[1]"
        );
    }
}
