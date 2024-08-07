// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { PoolConfigLib } from "../../../contracts/lib/PoolConfigLib.sol";
import { VaultMockDeployer } from "../../../test/foundry/utils/VaultMockDeployer.sol";

contract VaultUnitTest is BaseTest {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using CastingHelpers for *;
    using FixedPoint for *;
    using PoolConfigLib for PoolConfigBits;
    using SafeCast for *;

    IVaultMock internal vault;

    address pool = address(0x1234);
    uint256 amountGivenRaw = 1 ether;
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];

    function setUp() public virtual override {
        BaseTest.setUp();
        vault = IVaultMock(address(VaultMockDeployer.deploy()));
    }

    function testBuildPoolSwapParams() public view {
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

        PoolSwapParams memory poolSwapParams = vault.manualBuildPoolSwapParams(params, state, poolData);

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

    function testComputeAndChargeAggregateSwapFees() public {
        vault.manualSetPoolRegistered(pool, true);

        uint256 tokenIndex = 0;
        vault.manualSetAggregateSwapFeeAmount(pool, dai, 0);

        uint256 swapFeeAmountScaled18 = 1e18;
        uint256 protocolSwapFeePercentage = 10e16;

        PoolData memory poolData;
        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.poolConfigBits = poolData.poolConfigBits.setAggregateSwapFeePercentage(protocolSwapFeePercentage);

        uint256 expectedSwapFeeAmountRaw = swapFeeAmountScaled18
            .mulUp(protocolSwapFeePercentage)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[tokenIndex], poolData.tokenRates[tokenIndex]);

        uint256 totalFeesRaw = vault.manualComputeAndChargeAggregateSwapFees(
            poolData,
            swapFeeAmountScaled18,
            pool,
            dai,
            tokenIndex
        );

        // No creator fees, so protocol fees is equal to the total
        assertEq(totalFeesRaw, expectedSwapFeeAmountRaw, "Unexpected totalFeesRaw");
        assertEq(
            vault.getAggregateSwapFeeAmount(pool, dai),
            expectedSwapFeeAmountRaw,
            "Unexpected protocol fees in storage"
        );
    }

    function testComputeAndChargeAggregateSwapFeeIfPoolIsInRecoveryMode() public {
        vault.manualSetPoolRegistered(pool, true);

        PoolData memory poolData;
        poolData.poolConfigBits = poolData.poolConfigBits.setPoolInRecoveryMode(true);

        uint256 totalFeesRaw = vault.manualComputeAndChargeAggregateSwapFees(poolData, 1e18, pool, dai, 0);

        assertEq(totalFeesRaw, 0, "Unexpected totalFeesRaw");
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

    function testSettle__Fuzz(uint256 initialReserves, uint256 addedReserves, uint256 settleHint) public {
        initialReserves = bound(initialReserves, 0, 1e12 * 1e18);
        addedReserves = bound(addedReserves, 0, 1e12 * 1e18);
        settleHint = bound(settleHint, 0, addedReserves * 2);

        vault.manualSetIsUnlocked(true);
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
        vault.manualSetIsUnlocked(true);
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
        assertLt(MAX_FEE_PERCENTAGE / FEE_SCALING_FACTOR, 2 ** FEE_BITLENGTH, "Fee constants are not consistent");
    }
}
