// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

contract VaultUnitSwapTest is BaseTest {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using FixedPoint for *;

    IVaultMock internal vault;
    address pool = address(0x1234);

    uint256 amountGivenRaw = 1e18;
    uint256 mockedAmountCalculatedScaled18 = 5e17;

    IERC20[] swapTokens;
    uint256[] initialBalances = [uint256(10e18), 10e18];
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];

    function setUp() public virtual override {
        BaseTest.setUp();
        vault = IVaultMock(address(VaultMockDeployer.deploy()));

        swapTokens = [dai, usdc];
        vault.manualSetPoolTokenBalances(pool, swapTokens, initialBalances);

        for (uint256 i = 0; i < swapTokens.length; i++) {
            vault.manualSetPoolCreatorFees(pool, swapTokens[i], 0);
        }
    }

    function testSwapExactInWithZeroFee() public {
        (
            SwapParams memory params,
            SwapVars memory vars,
            PoolData memory poolData
        ) = _makeParams(SwapKind.EXACT_IN, amountGivenRaw, 0, 0, 0);
        _mockOnSwap(mockedAmountCalculatedScaled18, params, vars, poolData);

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = (0, 0, 0);
        (amountCalculated, amountIn, amountOut, params, vars, poolData) = vault.manualInternalSwap(
            params,
            vars,
            poolData
        );

        _checkSwapExactInResult(
            mockedAmountCalculatedScaled18,
            amountGivenRaw,
            amountCalculated,
            amountIn,
            amountOut,
            params,
            vars,
            poolData,
            vaultState
        );
    }

    /*TODO
    function testSwapExactInWithFee() public {
        // set zero pool creator fee
        vault.manualSetPoolCreatorFees(pool, swapTokens[1], 0);

        (
            SwapParams memory params,
            SwapVars memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        ) = _makeParams(SwapKind.EXACT_IN, amountGivenRaw, 0, 5e16, 10e16);
        _mockOnSwap(mockedAmountCalculatedScaled18, params, vars, poolData);

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = (0, 0, 0);
        (amountCalculated, amountIn, amountOut, params, vars, poolData, vaultState) = vault.manualInternalSwap(
            params,
            vars,
            poolData,
            vaultState
        );

        _checkSwapExactInResult(
            mockedAmountCalculatedScaled18,
            amountGivenRaw,
            amountCalculated,
            amountIn,
            amountOut,
            params,
            vars,
            poolData,
            vaultState
        );
    }*/

    function testSwapExactInSwapLimitRevert() public {
        uint256 swapLimit = mockedAmountCalculatedScaled18 - 1;

        (
            SwapParams memory params,
            SwapVars memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        ) = _makeParams(SwapKind.EXACT_IN, amountGivenRaw, swapLimit, 0, 0);

        uint256 amount = mockedAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[vars.indexOut],
            poolData.tokenRates[vars.indexOut]
        );

        _mockOnSwap(mockedAmountCalculatedScaled18, params, vars, poolData);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, amount, swapLimit));
        vault.manualInternalSwap(params, vars, poolData, vaultState);
    }

    function testSwapExactOutSwapLimitRevert() public {
        (
            SwapParams memory params,
            SwapVars memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        ) = _makeParams(SwapKind.EXACT_OUT, amountGivenRaw, 0, 0, 0);

        uint256 amount = mockedAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[vars.indexIn],
            poolData.tokenRates[vars.indexIn]
        );

        _mockOnSwap(mockedAmountCalculatedScaled18, params, vars, poolData);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, amount, 0));
        vault.manualInternalSwap(params, vars, poolData, vaultState);
    }

    function testSwapExactOutWithZeroFee() public {
        (
            SwapParams memory params,
            SwapVars memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        ) = _makeParams(SwapKind.EXACT_OUT, amountGivenRaw, mockedAmountCalculatedScaled18, 0, 0);
        _mockOnSwap(mockedAmountCalculatedScaled18, params, vars, poolData);

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = (0, 0, 0);
        (amountCalculated, amountIn, amountOut, params, vars, poolData, vaultState) = vault.manualInternalSwap(
            params,
            vars,
            poolData,
            vaultState
        );

        _checkSwapExactOutResult(
            mockedAmountCalculatedScaled18,
            amountGivenRaw,
            amountCalculated,
            amountIn,
            amountOut,
            params,
            vars,
            poolData,
            vaultState
        );
    }

    /*TODO
    function testSwapExactOutWithFee() public {
        uint256 swapFeePct = 5e16;
        uint256 creatorFeePct = 10e16;
        uint256 swapFeeAmount = mockedAmountCalculatedScaled18.mulDown(swapFeePct);

        uint256 amountCalculatedWithFee = mockedAmountCalculatedScaled18 + swapFeeAmount;
        // This sets the protocol swap fee percentage to the same as the swap fee percentage
        (
            SwapParams memory params,
            SwapVars memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        ) = _makeParams(SwapKind.EXACT_OUT, amountGivenRaw, amountCalculatedWithFee, swapFeePct, creatorFeePct);
        _mockOnSwap(mockedAmountCalculatedScaled18, params, vars, poolData);
        vault.manualSetPoolCreatorFees(pool, swapTokens[0], 0);

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = (0, 0, 0);
        (amountCalculated, amountIn, amountOut, params, vars, poolData, vaultState) = vault.manualInternalSwap(
            params,
            vars,
            poolData,
            vaultState
        );

        _checkSwapExactOutResult(
            mockedAmountCalculatedScaled18,
            amountGivenRaw,
            amountCalculated,
            amountIn,
            amountOut,
            params,
            vars,
            poolData,
            vaultState
        );
    }*/

    // #region Helpers
    function _makeParams(
        SwapKind kind,
        uint256 amountGivenRaw_,
        uint256 limitRaw,
        uint256 swapFeePercentage_,
        uint256 poolCreatorFeePercentage_
    )
        internal
        returns (SwapParams memory params, SwapVars memory vars, PoolData memory poolData)
    {
        params = SwapParams({
            kind: kind,
            pool: pool,
            tokenIn: swapTokens[0],
            tokenOut: swapTokens[1],
            amountGivenRaw: amountGivenRaw_,
            limitRaw: limitRaw,
            userData: new bytes(0)
        });

        vars.indexIn = 0;
        vars.indexOut = 1;
        vars.swapFeePercentage = swapFeePercentage_;

        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.balancesRaw = initialBalances;

        poolData.poolConfig.staticSwapFeePercentage = swapFeePercentage_;
        poolData.poolConfig.aggregateProtocolSwapFeePercentage = _getAggregateFeePercentage(swapFeePercentage_, poolCreatorFeePercentage_);

        // TODO: check these after the operations.
        poolData.balancesLiveScaled18 = new uint256[](initialBalances.length);
    }

    function _checkSwapExactInResult(
        uint256 mockedAmountCalculatedScaled18_,
        uint256 amountGivenRaw_,
        uint256 amountCalculated,
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData
    ) internal {
        uint256 fee = mockedAmountCalculatedScaled18_.mulUp(poolData.poolConfig.staticSwapFeePercentage);

        uint256 expectedAmountCalculatedScaled18 = mockedAmountCalculatedScaled18_ - fee;
        uint256 expectedAmountOut = expectedAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[vars.indexOut],
            poolData.tokenRates[vars.indexOut]
        );

        assertEq(amountCalculated, amountOut, "Unexpected amountCalculated");
        assertEq(amountIn, amountGivenRaw_, "Unexpected amountIn");
        assertEq(amountOut, expectedAmountOut, "Unexpected amountOut");
        assertEq(
            vars.amountCalculatedScaled18,
            expectedAmountCalculatedScaled18,
            "Unexpected amountCalculatedScaled18"
        );

        // check fees
        assertEq(vars.swapFeeAmountScaled18, fee, "Unexpected swapFeeAmountScaled18");
        uint256 protocolSwapFeeAmountScaled18 = vars.swapFeeAmountScaled18.mulUp(poolData.poolConfig.aggregateProtocolSwapFeePercentage);
        /*TODOassertEq(
            vars.protocolSwapFeeAmountRaw,
            protocolSwapFeeAmountScaled18.toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[vars.indexOut],
                poolData.tokenRates[vars.indexOut]
            ),
            "Unexpected swapFeeAmountScaled18"
        );
        assertEq(
            vault.getProtocolFees(pool, swapTokens[vars.indexOut]),
            vars.protocolSwapFeeAmountRaw,
            "Unexpected protocol fees in storage"
        );

        assertEq(
            vars.creatorSwapFeeAmountRaw,
            (vars.swapFeeAmountScaled18 - protocolSwapFeeAmountScaled18)
                .mulUp(poolData.poolConfig.poolCreatorFeePercentage)
                .toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[vars.indexOut],
                    poolData.tokenRates[vars.indexOut]
                ),
            "Unexpected creatorSwapFeeAmountRaw"
        );*/

        _checkCommonSwapResult(amountIn, amountOut, params, vars, poolData);
    }

    function _checkSwapExactOutResult(
        uint256 mockedAmountCalculatedScaled18_,
        uint256 amountGivenRaw_,
        uint256 amountCalculated,
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData
    ) internal {
        uint256 expectedSwapFeeAmountScaled18 = mockedAmountCalculatedScaled18_.mulDown(
            poolData.poolConfig.staticSwapFeePercentage
        );

        uint256 expectedAmountCalculatedScaled18 = mockedAmountCalculatedScaled18_ + expectedSwapFeeAmountScaled18;
        uint256 expectedAmountIn = expectedAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[vars.indexIn],
            poolData.tokenRates[vars.indexIn]
        );

        uint256 expectedProtocolFeeAmountScaled18 = expectedSwapFeeAmountScaled18.mulUp(
            poolData.poolConfig.aggregateProtocolSwapFeePercentage
        );

        uint256 expectedProtocolFeeAmountRaw = expectedProtocolFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[vars.indexIn],
            poolData.tokenRates[vars.indexIn]
        );

        uint256 expectedCreatorFeeAmountRaw = (expectedSwapFeeAmountScaled18 - expectedProtocolFeeAmountScaled18)
            .mulUp(poolData.poolConfig.poolCreatorFeePercentage)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[vars.indexIn], poolData.tokenRates[vars.indexIn]);

        assertEq(amountCalculated, expectedAmountIn, "Unexpected amountCalculated");
        assertEq(amountIn, expectedAmountIn, "Unexpected amountIn");
        assertEq(amountOut, amountGivenRaw_, "Unexpected amountOut");
        assertEq(
            vars.amountCalculatedScaled18,
            expectedAmountCalculatedScaled18,
            "Unexpected amountCalculatedScaled18"
        );

        // check fees
        assertEq(vars.swapFeeAmountScaled18, expectedSwapFeeAmountScaled18, "Unexpected swapFeeAmountScaled18");
        //TODOassertEq(vars.protocolSwapFeeAmountRaw, expectedProtocolFeeAmountRaw, "Unexpected protocolFeeAmountRaw");
        //TODOassertEq(vars.creatorSwapFeeAmountRaw, expectedCreatorFeeAmountRaw, "Unexpected creatorSwapFeeAmountRaw");

        assertEq(vault.getProtocolFees(pool, swapTokens[vars.indexOut]), 0, "Unexpected protocol fees in storage");
        assertEq(vault.getPoolCreatorFees(pool, swapTokens[vars.indexOut]), 0, "Unexpected creator fees in storage");

        _checkCommonSwapResult(amountIn, amountOut, params, vars, poolData, vaultState);
    }

    function _checkCommonSwapResult(
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData
    ) internal {
        //TODO
        uint256 totalFees = 0; //vars.protocolSwapFeeAmountRaw + vars.creatorSwapFeeAmountRaw;
        uint256 feesOnAmountOut = params.kind == SwapKind.EXACT_IN ? totalFees : 0;
        uint256 feesOnAmountIn = params.kind == SwapKind.EXACT_IN ? 0 : totalFees;

        // check balances updated
        assertEq(
            poolData.balancesRaw[vars.indexIn],
            initialBalances[vars.indexIn] + amountIn - feesOnAmountIn,
            "Unexpected balanceRaw[vars.indexIn]"
        );
        assertEq(
            poolData.balancesRaw[vars.indexOut],
            initialBalances[vars.indexOut] - amountOut - feesOnAmountOut,
            "Unexpected balanceRaw[vars.indexOut]"
        );

        // check _setPoolBalances called
        uint256[] memory expectedBalancesLiveScaled18 = poolData.balancesRaw.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );
        assertEq(
            poolData.balancesLiveScaled18[vars.indexIn],
            expectedBalancesLiveScaled18[vars.indexIn],
            "Unexpected balancesLiveScaled18[vars.indexIn]"
        );
        assertEq(
            poolData.balancesLiveScaled18[vars.indexOut],
            expectedBalancesLiveScaled18[vars.indexOut],
            "Unexpected balancesLiveScaled18[vars.indexOut]"
        );

        uint256[] memory storageRawBalances = vault.getRawBalances(params.pool);
        assertEq(storageRawBalances.length, poolData.balancesRaw.length, "Unexpected storageRawBalances length");
        assertEq(
            storageRawBalances[vars.indexIn],
            poolData.balancesRaw[vars.indexIn],
            "Unexpected storageRawBalances[vars.indexIn]"
        );
        assertEq(
            storageRawBalances[vars.indexOut],
            poolData.balancesRaw[vars.indexOut],
            "Unexpected storageRawBalances[vars.indexIn]"
        );

        uint256[] memory storageLastLiveBalances = vault.getLastLiveBalances(params.pool);
        assertEq(
            storageLastLiveBalances.length,
            poolData.balancesLiveScaled18.length,
            "Unexpected storageLastLiveBalances length"
        );
        assertEq(
            storageLastLiveBalances[vars.indexIn],
            poolData.balancesLiveScaled18[vars.indexIn],
            "Unexpected storageLastLiveBalances[vars.indexIn]"
        );
        assertEq(
            storageLastLiveBalances[vars.indexOut],
            poolData.balancesLiveScaled18[vars.indexOut],
            "Unexpected storageLastLiveBalances[vars.indexIn]"
        );

        // check _takeDebt called
        assertEq(vault.getTokenDelta(swapTokens[0]), int256(amountIn), "Unexpected tokenIn delta");

        // check _supplyCredit called
        assertEq(vault.getTokenDelta(swapTokens[1]), -int256(amountOut), "Unexpected tokenOut delta");
    }

    function _mockOnSwap(
        uint256 mockedAmountCalculatedScaled18_,
        SwapParams memory params,
        SwapVars memory vars,
        PoolData memory poolData
    ) internal {
        vm.mockCall(
            pool,
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.PoolSwapParams({
                    kind: params.kind,
                    amountGivenScaled18: vars.amountGivenScaled18,
                    balancesScaled18: poolData.balancesLiveScaled18,
                    indexIn: vars.indexIn,
                    indexOut: vars.indexOut,
                    sender: address(this),
                    userData: params.userData
                })
            ),
            abi.encodePacked(mockedAmountCalculatedScaled18_)
        );
    }
    // #endregion
}
