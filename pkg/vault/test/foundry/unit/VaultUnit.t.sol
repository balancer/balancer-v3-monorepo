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
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
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

    // #region _swap
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

    // #endregion

    // #region Other tests
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
        (, , PoolData memory poolData, ) = _makeParams(SwapKind.EXACT_IN, amountGivenRaw, 0, 5e16, 10e16);

        uint swapFeeAmountScaled18 = 1e18;
        uint protocolSwapFeePercentage_ = 10e16;

        uint expectSwapFeeAmountScaled18 = swapFeeAmountScaled18
            .mulUp(protocolSwapFeePercentage_)
            .toRawUndoRateRoundDown(poolData.decimalScalingFactors[0], poolData.tokenRates[0]);

        vm.expectEmit();
        emit IVaultEvents.ProtocolSwapFeeCharged(POOL, address(TOKEN_IN), expectSwapFeeAmountScaled18);
        uint256 protocolSwapFeeAmountRaw = vault.manualComputeAndChargeProtocolFees(
            poolData,
            swapFeeAmountScaled18,
            protocolSwapFeePercentage_,
            POOL,
            TOKEN_IN,
            0
        );

        assertEq(protocolSwapFeeAmountRaw, expectSwapFeeAmountScaled18, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(
            vault.getProtocolFees(address(TOKEN_IN)),
            protocolSwapFeeAmountRaw,
            "Unexpected protocol fees in storage"
        );
    }

    function testComputeAndChargeProtocolFeesIfPoolIsInRecoveryMode() public {
        PoolData memory poolData;
        poolData.poolConfig.isPoolInRecoveryMode = true;
        uint256 protocolSwapFeeAmountRaw = vault.manualComputeAndChargeProtocolFees(
            poolData,
            1e18,
            10e16,
            POOL,
            TOKEN_IN,
            0
        );

        assertEq(protocolSwapFeeAmountRaw, 0, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(vault.getProtocolFees(address(TOKEN_IN)), 0, "Unexpected protocol fees in storage");
    }

    function testComputeAndChargeProtocolAndCreatorFees() public {
        uint256 initVault = 10e18;
        vault.manualSetPoolCreatorFees(POOL, TOKEN_IN, initVault);

        (, , PoolData memory poolData, ) = _makeParams(SwapKind.EXACT_IN, amountGivenRaw, 0, 5e16, 10e16);

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
        emit IVaultEvents.ProtocolSwapFeeCharged(POOL, address(TOKEN_IN), expectSwapFeeAmountScaled18);

        vm.expectEmit();
        emit IVaultEvents.PoolCreatorFeeCharged(POOL, address(TOKEN_IN), expectCreatorFeeAmountRaw);

        (uint256 protocolSwapFeeAmountRaw, uint256 creatorSwapFeeAmountRaw) = vault
            .manualComputeAndChargeProtocolAndCreatorFees(
                poolData,
                swapFeeAmountScaled18,
                protocolSwapFeePercentage_,
                creatorFeePercentage,
                POOL,
                TOKEN_IN,
                0
            );

        assertEq(protocolSwapFeeAmountRaw, expectSwapFeeAmountScaled18, "Unexpected protocolSwapFeeAmountRaw");
        assertEq(creatorSwapFeeAmountRaw, expectCreatorFeeAmountRaw, "Unexpected creatorSwapFeeAmountRaw");
        assertEq(
            vault.getPoolCreatorFees(POOL, TOKEN_IN),
            initVault + creatorSwapFeeAmountRaw,
            "Unexpected creator fees in storage"
        );
    }

    // #endregion

    // #region Helpers
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
        assertEq(vault.getTokenDelta(TOKEN_IN), int256(amountIn), "Unexpected tokenIn delta");

        // check _supplyCredit called
        assertEq(vault.getTokenDelta(TOKEN_OUT), -int256(amountOut), "Unexpected tokenOut delta");
    }

    function _checkComputeAndChargeProtocolAndCreatorFees() internal {
        // TODO
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
    // #endregion
}
