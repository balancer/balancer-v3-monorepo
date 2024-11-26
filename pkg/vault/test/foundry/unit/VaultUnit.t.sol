// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { VaultContractsDeployer } from "../../../test/foundry/utils/VaultContractsDeployer.sol";
import { PoolConfigLib } from "../../../contracts/lib/PoolConfigLib.sol";

contract VaultUnitTest is BaseTest, VaultContractsDeployer {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using CastingHelpers for *;
    using FixedPoint for *;
    using PoolConfigLib for PoolConfigBits;
    using SafeCast for *;

    uint256 constant MIN_TRADE_AMOUNT = 1e6;
    uint256 constant MIN_WRAP_AMOUNT = 1e4;

    IVaultMock internal vault;

    address pool = address(0x1234);
    uint256 amountGivenRaw = 1 ether;
    uint256[] decimalScalingFactors = [1e18, 1e18];
    uint256[] tokenRates = [1e18, 2e18];

    function setUp() public virtual override {
        BaseTest.setUp();
        vault = deployVaultMock(MIN_TRADE_AMOUNT, MIN_WRAP_AMOUNT);
    }

    function testBuildPoolSwapParams() public view {
        VaultSwapParams memory vaultSwapParams;
        vaultSwapParams.kind = SwapKind.EXACT_IN;
        vaultSwapParams.userData = new bytes(20);
        vaultSwapParams.userData[0] = 0x01;
        vaultSwapParams.userData[19] = 0x05;

        SwapState memory state;
        state.amountGivenScaled18 = 2e18;
        state.indexIn = 3;
        state.indexOut = 4;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = [uint256(1e18), 1e18].toMemoryArray();

        PoolSwapParams memory poolSwapParams = vault.manualBuildPoolSwapParams(vaultSwapParams, state, poolData);

        assertEq(uint8(poolSwapParams.kind), uint8(vaultSwapParams.kind), "Unexpected kind");
        assertEq(poolSwapParams.amountGivenScaled18, state.amountGivenScaled18, "Unexpected amountGivenScaled18");
        assertEq(
            keccak256(abi.encodePacked(poolSwapParams.balancesScaled18)),
            keccak256(abi.encodePacked(poolData.balancesLiveScaled18)),
            "Unexpected balancesScaled18"
        );
        assertEq(poolSwapParams.indexIn, state.indexIn, "Unexpected indexIn");
        assertEq(poolSwapParams.indexOut, state.indexOut, "Unexpected indexOut");
        assertEq(poolSwapParams.router, address(this), "Unexpected router");
        assertEq(poolSwapParams.userData, vaultSwapParams.userData, "Unexpected userData");
    }

    function testComputeAndChargeAggregateSwapFees__Fuzz(
        uint256 totalSwapFeeAmountScaled18,
        uint256 aggregateSwapFeePercentage
    ) public {
        totalSwapFeeAmountScaled18 = bound(totalSwapFeeAmountScaled18, 0, 1e18);
        aggregateSwapFeePercentage = bound(aggregateSwapFeePercentage, 1e12, 50e16);

        vault.manualSetPoolRegistered(pool, true);
        vault.manualSetAggregateSwapFeeAmount(pool, dai, 0);
        uint256 tokenIndex = 0;

        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.poolConfigBits = poolData.poolConfigBits.setAggregateSwapFeePercentage(aggregateSwapFeePercentage);

        // The aggregate fee percentage is truncated in the pool config bits, so we do the same.
        aggregateSwapFeePercentage = (aggregateSwapFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;

        uint256 expectedTotalSwapFeeAmountRaw = totalSwapFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );

        uint256 expectedAggregateSwapFeeAmountRaw = expectedTotalSwapFeeAmountRaw.mulDown(aggregateSwapFeePercentage);

        (uint256 totalSwapFeeAmountRaw, uint256 aggregateSwapFeeAmountRaw) = vault
            .manualComputeAndChargeAggregateSwapFees(poolData, totalSwapFeeAmountScaled18, pool, dai, tokenIndex);

        assertEq(totalSwapFeeAmountRaw, expectedTotalSwapFeeAmountRaw, "Unexpected totalSwapFeeAmountRaw");
        assertEq(aggregateSwapFeeAmountRaw, expectedAggregateSwapFeeAmountRaw, "Unexpected aggregateSwapFeeAmountRaw");
        assertEq(
            vault.getAggregateSwapFeeAmount(pool, dai),
            expectedAggregateSwapFeeAmountRaw,
            "Unexpected protocol fees in storage"
        );
    }

    function testComputeAndChargeAggregateSwapFeeIfPoolIsInRecoveryMode() public {
        vault.manualSetPoolRegistered(pool, true);

        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.poolConfigBits = poolData.poolConfigBits.setAggregateSwapFeePercentage(1.56464e16);
        poolData.poolConfigBits = poolData.poolConfigBits.setPoolInRecoveryMode(true);

        (uint256 totalSwapFeeAmountRaw, uint256 aggregateSwapFeeAmountRaw) = vault
            .manualComputeAndChargeAggregateSwapFees(poolData, 2e18, pool, dai, 0);

        assertEq(totalSwapFeeAmountRaw, 2, "Unexpected totalSwapFeeAmountRaw");
        assertEq(aggregateSwapFeeAmountRaw, 0, "Unexpected aggregateSwapFeeAmountRaw");
        assertEq(vault.getAggregateSwapFeeAmount(pool, dai), 0, "Unexpected protocol fees in storage");
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

        // Live balances will be updated, so we just set them equal to the raw ones.
        vault.manualSetPoolTokensAndBalances(pool, defaultTokens, tokenBalances, tokenBalances);

        vm.mockCall(rateProvider, abi.encodeWithSelector(IRateProvider.getRate.selector), abi.encode(secondTokenRate));
        poolData = vault.manualUpdatePoolDataLiveBalancesAndRates(pool, poolData, Rounding.ROUND_UP);

        // check _updateTokenRatesInPoolData is called.
        assertEq(poolData.tokenRates[0], FixedPoint.ONE, "Unexpected tokenRates[0]");
        assertEq(poolData.tokenRates[1], secondTokenRate, "Unexpected tokenRates[1]");

        // check balances
        assertEq(poolData.balancesRaw[0], tokenBalances[0], "Unexpected balancesRaw[0]");
        assertEq(poolData.balancesRaw[1], tokenBalances[1], "Unexpected balancesRaw[1]");

        // check _updateRawAndLiveTokenBalancesInPoolData is called.
        assertEq(
            poolData.balancesLiveScaled18[0],
            (poolData.balancesRaw[0] * poolData.decimalScalingFactors[0]).mulUp(poolData.tokenRates[0]),
            "Unexpected balancesLiveScaled18[0]"
        );
        assertEq(
            poolData.balancesLiveScaled18[1],
            (poolData.balancesRaw[1] * poolData.decimalScalingFactors[1]).mulUp(poolData.tokenRates[1]),
            "Unexpected balancesLiveScaled18[1]"
        );
    }

    function testSettle__Fuzz(uint256 initialReserves, uint256 addedReserves, uint256 settleHint) public {
        initialReserves = bound(initialReserves, 0, 1e12 * 1e18);
        addedReserves = bound(addedReserves, 0, 1e12 * 1e18);
        settleHint = bound(settleHint, 0, addedReserves * 2);

        vault.forceUnlock();
        vault.manualSetReservesOf(dai, initialReserves);

        dai.mint(address(vault), initialReserves);
        uint256 daiReservesBefore = vault.getReservesOf(dai);
        assertEq(daiReservesBefore, initialReserves, "Wrong initial reserves");
        assertEq(vault.getTokenDelta(dai), 0, "Wrong initial credit");

        dai.mint(address(vault), addedReserves);
        assertEq(daiReservesBefore, vault.getReservesOf(dai), "Wrong reserves before settle");

        uint256 settlementAmount = vault.settle(dai, settleHint);
        uint256 reserveDiff = vault.getReservesOf(dai) - daiReservesBefore;
        assertEq(reserveDiff, addedReserves, "Wrong reserves after settle");
        assertEq(settlementAmount, Math.min(settleHint, reserveDiff), "Wrong settle return value");
        assertEq(vault.getTokenDelta(dai), -settlementAmount.toInt256(), "Wrong credit after settle");
    }

    function testSettleNegative() public {
        vault.forceUnlock();
        vault.manualSetReservesOf(dai, 100);
        // Simulate balance decrease.
        vm.mockCall(address(dai), abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(99));

        vm.expectRevert(stdError.arithmeticError);
        vault.settle(dai, 0);
    }

    function testPoolGetTokenCountAndIndexOfTokenNotRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, pool));
        vault.getPoolTokenCountAndIndexOfToken(pool, dai);
    }

    function testPoolGetTokenCountAndIndexOfToken() public {
        vault.manualSetPoolRegistered(pool, true);
        vault.manualSetPoolTokensAndBalances(
            pool,
            [address(dai), address(usdc), address(weth), address(wsteth), address(veBAL)].toMemoryArray().asIERC20(),
            new uint256[](5),
            new uint256[](5)
        );

        uint256 count;
        uint256 index;

        (count, index) = vault.getPoolTokenCountAndIndexOfToken(pool, dai);
        assertEq(count, 5, "wrong token count (dai)");
        assertEq(index, 0, "wrong token count (dai)");

        (count, index) = vault.getPoolTokenCountAndIndexOfToken(pool, usdc);
        assertEq(count, 5, "wrong token count (usdc)");
        assertEq(index, 1, "wrong token count (usdc)");

        (count, index) = vault.getPoolTokenCountAndIndexOfToken(pool, weth);
        assertEq(count, 5, "wrong token count (weth)");
        assertEq(index, 2, "wrong token count (weth)");

        (count, index) = vault.getPoolTokenCountAndIndexOfToken(pool, wsteth);
        assertEq(count, 5, "wrong token count (wsteth)");
        assertEq(index, 3, "wrong token count (wsteth)");

        (count, index) = vault.getPoolTokenCountAndIndexOfToken(pool, veBAL);
        assertEq(count, 5, "wrong token count (veBAL)");
        assertEq(index, 4, "wrong token count (veBAL)");

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.TokenNotRegistered.selector, alice));
        vault.getPoolTokenCountAndIndexOfToken(pool, IERC20(alice));
    }

    function testFeeConstants() public pure {
        assertLt(FixedPoint.ONE / FEE_SCALING_FACTOR, 2 ** FEE_BITLENGTH, "Fee constants are not consistent");
        assertEq(
            (MAX_FEE_PERCENTAGE / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR,
            MAX_FEE_PERCENTAGE,
            "Max fee percentage requires too much precision"
        );
    }

    function testMinimumTradeAmountWithZero() public view {
        // Should succeed with 0 or the minimum.
        vault.ensureValidTradeAmount(0);

        // Should succeed when it's the minimum.
        vault.ensureValidTradeAmount(vault.getMinimumTradeAmount());
    }

    function testMinimumTradeAmountBelowMinimum() public {
        // Should fail below minimum.
        uint256 tradeAmount = vault.getMinimumTradeAmount() - 1;

        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        vault.ensureValidTradeAmount(tradeAmount);
    }

    function testMinimumSwapAmount() public {
        uint256 minAmount = vault.getMinimumTradeAmount();

        // Should succeed when it's the minimum
        vault.ensureValidSwapAmount(minAmount);

        // Should fail below minimum.
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        vault.ensureValidSwapAmount(minAmount - 1);

        // Should fail with 0 (unlike testMinimumTradeAmount).
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        vault.ensureValidSwapAmount(0);
    }

    function testWritePoolBalancesToStorage() public {
        uint256 numTokens = 3;
        PoolData memory poolData;
        poolData.balancesRaw = new uint256[](numTokens);
        poolData.balancesLiveScaled18 = new uint256[](numTokens);

        poolData.balancesRaw[0] = 1;
        poolData.balancesRaw[1] = 2;
        poolData.balancesRaw[2] = 3;
        poolData.balancesLiveScaled18[0] = 10;
        poolData.balancesLiveScaled18[1] = 20;
        poolData.balancesLiveScaled18[2] = 30;

        vault.manualSetPoolTokens(pool, new IERC20[](numTokens)); // The length must match

        vault.manualWritePoolBalancesToStorage(pool, poolData);

        uint256[] memory rawBalances = vault.getRawBalances(pool);
        uint256[] memory liveBalances = vault.getLastLiveBalances(pool);

        assertEq(rawBalances.length, numTokens, "Wrong raw balance length");
        assertEq(liveBalances.length, numTokens, "Wrong live balance length");

        assertEq(rawBalances[0], 1, "Wrong rawBalances[0]");
        assertEq(rawBalances[1], 2, "Wrong rawBalances[1]");
        assertEq(rawBalances[2], 3, "Wrong rawBalances[2]");
        assertEq(liveBalances[0], 10, "Wrong liveBalances[0]");
        assertEq(liveBalances[1], 20, "Wrong liveBalances[1]");
        assertEq(liveBalances[2], 30, "Wrong liveBalances[2]");
    }
}
