// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SwapParams,
    SwapLocals,
    PoolData,
    SwapKind,
    VaultState
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultUnitTest is BaseVaultTest {
    using ArrayHelpers for *;
    using ScalingHelpers for *;
    using FixedPoint for *;

    address constant POOL = address(0x1234);
    IERC20 constant TOKEN_IN = IERC20(address(0x2345));
    IERC20 constant TOKEN_OUT = IERC20(address(0x3456));

    uint256[] initialBalances = [uint256(10 ether), 10 ether];
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];

    uint256 amountGivenRaw = 1 ether;
    uint256 mockedAmountCalculatedScaled18 = 5e17;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testSwapExactInWithZeroFee() public {
        (
            SwapParams memory params,
            SwapLocals memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        ) = _makeParams(SwapKind.EXACT_IN, amountGivenRaw, 0, 0, 0);
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
    }

    function testSwapExactInWithFee() public {
        // set zero pool creator fee
        vault.manualSetPoolCreatorFees(POOL, TOKEN_OUT, 0);

        (
            SwapParams memory params,
            SwapLocals memory vars,
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
    }

    function testSwapExactInSwapLimitRevert() public {
        uint256 swapLimit = mockedAmountCalculatedScaled18 - 1;

        (
            SwapParams memory params,
            SwapLocals memory vars,
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
            SwapLocals memory vars,
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
            SwapLocals memory vars,
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

    function testSwapExactOutWithFee() public {
        (
            SwapParams memory params,
            SwapLocals memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        ) = _makeParams(SwapKind.EXACT_OUT, amountGivenRaw, mockedAmountCalculatedScaled18, 5e16, 10e16);
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

    // #region Helpers
    function _checkSwapExactInResult(
        uint256 mockedAmountCalculatedScaled18_,
        uint256 amountGivenRaw_,
        uint256 amountCalculated,
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapLocals memory vars,
        PoolData memory poolData,
        VaultState memory vaultState
    ) internal {
        uint256 fee = mockedAmountCalculatedScaled18_.mulUp(vars.swapFeePercentage);

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
        assertEq(
            vars.protocolSwapFeeAmountRaw,
            vars.swapFeeAmountScaled18.mulUp(vaultState.protocolSwapFeePercentage).toRawUndoRateRoundDown(
                poolData.decimalScalingFactors[vars.indexOut],
                poolData.tokenRates[vars.indexOut]
            ),
            "Unexpected swapFeeAmountScaled18"
        );
        assertEq(
            vars.creatorSwapFeeAmountRaw,
            (vars.swapFeeAmountScaled18 - vars.protocolSwapFeeAmountRaw)
                .mulUp(poolData.poolConfig.poolCreatorFeePercentage)
                .toRawUndoRateRoundDown(
                    poolData.decimalScalingFactors[vars.indexOut],
                    poolData.tokenRates[vars.indexOut]
                ),
            "Unexpected creatorSwapFeeAmountRaw"
        );

        _checkSwapResult(amountIn, amountOut, params, vars, poolData, vaultState);
    }

    function _checkSwapExactOutResult(
        uint256 mockedAmountCalculatedScaled18_,
        uint256 amountGivenRaw_,
        uint256 amountCalculated,
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapLocals memory vars,
        PoolData memory poolData,
        VaultState memory vaultState
    ) internal {
        uint256 expectedAmountCalculatedScaled18 = mockedAmountCalculatedScaled18_;
        uint256 expectedAmountIn = expectedAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[vars.indexIn],
            poolData.tokenRates[vars.indexIn]
        );

        assertEq(amountCalculated, expectedAmountIn, "Unexpected amountCalculated");
        assertEq(amountIn, expectedAmountIn, "Unexpected amountIn");
        assertEq(amountOut, amountGivenRaw_, "Unexpected amountOut");
        assertEq(
            vars.amountCalculatedScaled18,
            expectedAmountCalculatedScaled18,
            "Unexpected amountCalculatedScaled18"
        );

        // check fees
        assertEq(vars.swapFeeAmountScaled18, 0, "Unexpected swapFeeAmountScaled18");
        assertEq(vars.protocolSwapFeeAmountRaw, 0, "Unexpected swapFeeAmountScaled18");
        assertEq(vars.creatorSwapFeeAmountRaw, 0, "Unexpected creatorSwapFeeAmountRaw");

        _checkSwapResult(amountIn, amountOut, params, vars, poolData, vaultState);
    }

    function _checkSwapResult(
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapLocals memory vars,
        PoolData memory poolData,
        VaultState memory vaultState
    ) internal {
        // check balances updated
        assertEq(
            poolData.balancesRaw[vars.indexIn],
            initialBalances[vars.indexIn] + amountIn,
            "Unexpected balanceRaw[vars.indexIn]"
        );
        assertEq(
            poolData.balancesRaw[vars.indexOut],
            initialBalances[vars.indexOut] - amountOut - vars.protocolSwapFeeAmountRaw - vars.creatorSwapFeeAmountRaw,
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

        // check _takeDebt called
        assertEq(vault.getTokenDelta(address(this), TOKEN_IN), int256(amountIn), "Unexpected tokenIn delta");

        // check _supplyCredit called
        assertEq(vault.getTokenDelta(address(this), TOKEN_OUT), -int256(amountOut), "Unexpected tokenOut delta");
    }

    function _mockOnSwap(
        uint256 mockedAmountCalculatedScaled18_,
        SwapParams memory params,
        SwapLocals memory vars,
        PoolData memory poolData
    ) internal {
        vm.mockCall(
            POOL,
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

    function _makeParams(
        SwapKind kind,
        uint256 amountGivenRaw_,
        uint256 limitRaw,
        uint256 swapFeePercentage_,
        uint256 poolCreatorFeePercentage_
    )
        internal
        returns (
            SwapParams memory params,
            SwapLocals memory vars,
            PoolData memory poolData,
            VaultState memory vaultState
        )
    {
        params = SwapParams({
            kind: kind,
            pool: POOL,
            tokenIn: TOKEN_IN,
            tokenOut: TOKEN_OUT,
            amountGivenRaw: amountGivenRaw_,
            limitRaw: limitRaw,
            userData: new bytes(0)
        });

        vars.indexIn = 0;
        vars.indexOut = 1;

        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.balancesRaw = initialBalances;

        vars.swapFeePercentage = swapFeePercentage_;
        vaultState.protocolSwapFeePercentage = swapFeePercentage_;
        poolData.poolConfig.poolCreatorFeePercentage = poolCreatorFeePercentage_;
    }
    // #endregion
}
