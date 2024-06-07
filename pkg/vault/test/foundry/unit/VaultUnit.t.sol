// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";

import { PoolConfigLib } from "../../../contracts/lib/PoolConfigLib.sol";

contract VaultUnitTest is BaseTest {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using FixedPoint for *;
    using PoolConfigLib for PoolConfig;

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

        SwapState memory state;
        state.amountGivenScaled18 = 2e18;
        state.indexIn = 3;
        state.indexOut = 4;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = [uint256(1e18), 1e18].toMemoryArray();

        IBasePool.PoolSwapParams memory poolSwapParams = vault.manualBuildPoolSwapParams(params, state, poolData);

        assertEq(uint8(poolSwapParams.kind), uint8(params.kind), "Unexpected kind");
        assertEq(poolSwapParams.amountGivenScaled18, state.amountGivenScaled18, "Unexpected amountGivenScaled18");
        assertEq(
            keccak256(abi.encodePacked(poolSwapParams.balancesScaled18)),
            keccak256(abi.encodePacked(poolData.balancesLiveScaled18)),
            "Unexpected balancesScaled18"
        );
        assertEq(poolSwapParams.indexIn, state.indexIn, "Unexpected indexIn");
        assertEq(poolSwapParams.indexOut, state.indexOut, "Unexpected indexOut");
        assertEq(poolSwapParams.router, address(this), "Unexpected router");
        assertEq(poolSwapParams.userData, params.userData, "Unexpected userData");
    }

    function testComputeAndChargeAggregateProtocolSwapFees() public {
        uint256 tokenIndex = 0;
        vault.manualSetAggregateProtocolSwapFeeAmount(pool, dai, 0);

        uint256 swapFeeAmountScaled18 = 1e18;
        uint256 protocolSwapFeePercentage = 10e16;

        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.poolConfig.setAggregateProtocolSwapFeePercentage(protocolSwapFeePercentage);

        uint256 expectedSwapFeeAmountRaw = swapFeeAmountScaled18
            .mulUp(protocolSwapFeePercentage)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[tokenIndex], poolData.tokenRates[tokenIndex]);

        uint256 totalFeesRaw = vault.manualComputeAndChargeAggregateProtocolSwapFees(
            poolData,
            swapFeeAmountScaled18,
            pool,
            dai,
            tokenIndex
        );

        // No creator fees, so protocol fees is equal to the total
        assertEq(totalFeesRaw, expectedSwapFeeAmountRaw, "Unexpected totalFeesRaw");
        assertEq(
            vault.getAggregateProtocolSwapFeeAmount(pool, dai),
            expectedSwapFeeAmountRaw,
            "Unexpected protocol fees in storage"
        );
    }

    function testComputeAndChargeAggregateProtocolSwapFeeIfPoolIsInRecoveryMode() public {
        PoolData memory poolData;
        poolData.poolConfig.isPoolInRecoveryMode = true;

        uint256 totalFeesRaw = vault.manualComputeAndChargeAggregateProtocolSwapFees(poolData, 1e18, pool, dai, 0);

        assertEq(totalFeesRaw, 0, "Unexpected totalFeesRaw");
        assertEq(vault.getAggregateProtocolSwapFeeAmount(pool, dai), 0, "Unexpected protocol fees in storage");
    }

    function testManualUpdatePoolDataLiveBalancesAndRates() public {
        PoolData memory poolData;
        poolData.tokens = new IERC20[](2);
        poolData.balancesRaw = new uint256[](2);
        poolData.tokenRates = new uint256[](2);
        poolData.balancesLiveScaled18 = new uint256[](2);

        address rateProvider = address(0xFF123);
        uint256 secondTokenRate = 3e25;

        poolData.decimalScalingFactors = decimalScalingFactors;

        poolData.tokenInfo = new TokenInfo[](2);
        poolData.tokenInfo[0].tokenType = TokenType.STANDARD;
        poolData.tokenInfo[1].tokenType = TokenType.WITH_RATE;
        poolData.tokenInfo[1].rateProvider = IRateProvider(rateProvider);

        uint256[] memory tokenBalances = [uint256(1e18), 2e18].toMemoryArray();

        IERC20[] memory defaultTokens = new IERC20[](2);
        defaultTokens[0] = dai;
        defaultTokens[1] = usdc;
        poolData.tokens[0] = dai;
        poolData.tokens[1] = usdc;

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
