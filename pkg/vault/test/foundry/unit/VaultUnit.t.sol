// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SwapParams,
    SwapVars,
    PoolData,
    SwapKind,
    TokenConfig,
    TokenType,
    Rounding
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
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

    function testBuildPoolSwapParams() public {
        SwapParams memory params;
        params.kind = SwapKind.EXACT_IN;
        params.userData = new bytes(20);
        params.userData[0] = 0x01;
        params.userData[19] = 0x05;

        SwapVars memory vars;
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

    /*TODO
    function testComputeAndChargeProtocolFees() public {
        uint256 tokenIndex = 0;
        vault.manualSetPoolCreatorFees(pool, dai, tokenIndex);

        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;

        uint256 swapFeeAmountScaled18 = 1e18;
        uint256 protocolSwapFeePercentage = 10e16;

        uint256 expectedSwapFeeAmountScaled18 = swapFeeAmountScaled18
            .mulUp(protocolSwapFeePercentage)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[tokenIndex], poolData.tokenRates[tokenIndex]);

        vm.expectEmit();
        emit IVaultEvents.ProtocolSwapFeeCharged(pool, address(dai), expectedSwapFeeAmountScaled18);

        (uint256 protocolSwapFeeAmountRaw, uint256 creatorSwapFeeAmountRaw) = vault
            .manualComputeAndChargeProtocolAndCreatorFees(
                poolData,
                swapFeeAmountScaled18,
                protocolSwapFeePercentage,
                pool,
                dai,
                tokenIndex
            );

        assertEq(creatorSwapFeeAmountRaw, 0, "Unexpected creatorSwapFeeAmountRaw");
        assertEq(protocolSwapFeeAmountRaw, expectedSwapFeeAmountScaled18, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(vault.getProtocolFees(pool, dai), protocolSwapFeeAmountRaw, "Unexpected protocol fees in storage");
        assertEq(vault.getPoolCreatorFees(pool, dai), 0, "Unexpected creator fees in storage");
    }

    function testComputeAndChargeCreatorFees() public {
        uint256 tokenIndex = 0;
        uint256 initVault = 10e18;
        vault.manualSetPoolCreatorFees(pool, dai, initVault);

        uint256 swapFeeAmountScaled18 = 1e18;
        uint256 swapFeeAmountRaw = 1e18;
        uint256 protocolSwapFeePercentage = 5e16;
        uint256 creatorFeePercentage = 5e16;

        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.poolConfig.poolCreatorFeePercentage = creatorFeePercentage;
        poolData.tokenRates = tokenRates;

        uint256 expectedSwapFeeAmountScaled18 = swapFeeAmountScaled18.mulUp(protocolSwapFeePercentage);

        uint256 expectSwapFeeAmountRaw = expectedSwapFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );

        uint256 expectCreatorFeeAmountRaw = (swapFeeAmountScaled18 - expectedSwapFeeAmountScaled18)
            .mulUp(creatorFeePercentage)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[tokenIndex], poolData.tokenRates[tokenIndex]);

        vm.expectEmit();
        emit IVaultEvents.ProtocolSwapFeeCharged(pool, address(dai), expectSwapFeeAmountRaw);

        vm.expectEmit();
        emit IVaultEvents.PoolCreatorSwapFeeCharged(pool, address(dai), expectCreatorFeeAmountRaw);

        (uint256 protocolSwapFeeAmountRaw, uint256 creatorSwapFeeAmountRaw) = vault
            .manualComputeAndChargeProtocolAndCreatorFees(
                poolData,
                swapFeeAmountScaled18,
                protocolSwapFeePercentage,
                pool,
                dai,
                0
            );

        assertEq(protocolSwapFeeAmountRaw, expectedSwapFeeAmountScaled18, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(creatorSwapFeeAmountRaw, expectCreatorFeeAmountRaw, "Unexpected creatorSwapFeeAmountRaw");
        assertEq(
            vault.getPoolCreatorFees(pool, dai),
            initVault + creatorSwapFeeAmountRaw,
            "Unexpected creator fees in storage"
        );
        assertEq(vault.getProtocolFees(pool, dai), protocolSwapFeeAmountRaw, "Unexpected protocol fees in storage");
    }

    function testComputeAndChargeProtocolAndCreatorFeesIfPoolIsInRecoveryMode() public {
        PoolData memory poolData;
        poolData.poolConfig.isPoolInRecoveryMode = true;

        (uint256 protocolSwapFeeAmountRaw, uint256 creatorSwapFeeAmountRaw) = vault
            .manualComputeAndChargeProtocolAndCreatorFees(poolData, 1e18, 10e16, pool, dai, 0);

        assertEq(protocolSwapFeeAmountRaw, 0, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(creatorSwapFeeAmountRaw, 0, "Unexpected creatorSwapFeeAmountRaw");
        assertEq(vault.getProtocolFees(pool, dai), 0, "Unexpected protocol fees in storage");
    }*/

    function testManualUpdatePoolDataLiveBalancesAndRates() public {
        PoolData memory poolData;
        poolData.balancesRaw = new uint256[](2);
        poolData.tokenRates = new uint256[](2);
        poolData.balancesLiveScaled18 = new uint256[](2);

        address rateProvider = address(0xFF123);
        uint256 secondTokenRate = 3e25;

        poolData.decimalScalingFactors = decimalScalingFactors;

        poolData.tokenConfig = new TokenConfig[](2);
        poolData.tokenConfig[0].tokenType = TokenType.STANDARD;
        poolData.tokenConfig[1].tokenType = TokenType.WITH_RATE;
        poolData.tokenConfig[1].rateProvider = IRateProvider(rateProvider);

        uint256[] memory tokenBalances = [uint256(1e18), 2e18].toMemoryArray();

        IERC20[] memory defaultTokens = new IERC20[](2);
        defaultTokens[0] = dai;
        defaultTokens[1] = usdc;

        vault.manualSetPoolTokenBalances(pool, defaultTokens, tokenBalances);

        vm.mockCall(rateProvider, abi.encodeWithSelector(IRateProvider.getRate.selector), abi.encode(secondTokenRate));
        poolData = vault.manualUpdatePoolDataLiveBalancesAndRates(pool, poolData, Rounding.ROUND_UP);

        // check _updateTokenRatesInPoolData is called
        assertEq(poolData.tokenRates[0], FixedPoint.ONE, "Unexpected tokenRates[0]");
        assertEq(poolData.tokenRates[1], secondTokenRate, "Unexpected tokenRates[1]");

        // check balances
        assertEq(poolData.balancesRaw[0], tokenBalances[0], "Unexpected balancesRaw[0]");
        assertEq(poolData.balancesRaw[1], tokenBalances[1], "Unexpected balancesRaw[1]");

        // check _updateRawAndLiveTokenBalancesInPoolData is called
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
