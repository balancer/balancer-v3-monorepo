// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolConfigLib, PoolConfigBits } from "../../../contracts/lib/PoolConfigLib.sol";
import { VaultMockDeployer } from "../../../test/foundry/utils/VaultMockDeployer.sol";

struct TestStateLocals {
    SwapParams params;
    SwapState swapState;
    PoolData poolData;
}

contract VaultUnitSwapTest is BaseTest {
    using ScalingHelpers for *;
    using FixedPoint for *;
    using PoolConfigLib for PoolConfigBits;

    IVaultMock internal vault;
    address pool = address(0x1234);

    uint256 immutable defaultAmountGivenRaw = 1e18;
    uint256 immutable defaultSwapFeePercentage = 5e16;
    uint256 immutable defaultProtocolFeePercentage = 50e16;
    uint256 immutable defaultCreatorFeePercentage = 10e16;
    uint256 immutable mockedPoolAmountCalculatedScaled18 = 5e17;

    IERC20[] swapTokens;
    uint256[] initialBalances = [uint256(10e18), 10e18];
    uint256[] decimalScalingFactors = [uint256(1e18), 1e18];
    uint256[] tokenRates = [uint256(1e18), 2e18];

    IProtocolFeeController feeController;

    function setUp() public virtual override {
        BaseTest.setUp();
        vault = IVaultMock(address(VaultMockDeployer.deploy()));
        feeController = vault.getProtocolFeeController();

        swapTokens = [dai, usdc];
        // We don't care about last live balances, so we set them equal to the raw ones.
        vault.manualSetPoolTokensAndBalances(pool, swapTokens, initialBalances, initialBalances);

        vault.manualSetAggregateSwapFeeAmount(pool, swapTokens[0], 0);
        vault.manualSetAggregateSwapFeeAmount(pool, swapTokens[1], 0);
        vault.manualSetPoolRegistered(pool, true);
    }

    function testMakeParams() public view {
        uint256 limitRaw = 1000e18;
        uint256 swapFeePercentage = 1e16;
        uint256 protocolFeePercentage = 20e16;
        uint256 poolCreatorFeePercentage = 50e16;

        (, SwapState memory state, PoolData memory poolData) = _makeParams(
            SwapKind.EXACT_IN,
            defaultAmountGivenRaw,
            limitRaw,
            swapFeePercentage,
            protocolFeePercentage,
            poolCreatorFeePercentage
        );

        assertEq(state.indexIn, 0, "Incorrect index in");
        assertEq(state.indexOut, 1, "Incorrect index out");
        assertEq(state.swapFeePercentage, swapFeePercentage, "Incorrect swap fee percentage");
        assertEq(
            state.amountGivenScaled18,
            defaultAmountGivenRaw.toScaled18ApplyRateRoundDown(
                poolData.decimalScalingFactors[0],
                poolData.tokenRates[0]
            ),
            "Incorrect amountGivenScaled18"
        );
    }

    function testSwapExactInWithZeroFee() public {
        TestStateLocals memory locals;
        (locals.params, locals.swapState, locals.poolData) = _makeParams(
            SwapKind.EXACT_IN,
            defaultAmountGivenRaw,
            0,
            0,
            0,
            0
        );
        uint256 amountGivenScaled18 = locals.swapState.amountGivenScaled18;

        _mockOnSwap(mockedPoolAmountCalculatedScaled18, locals.params, locals.swapState, locals.poolData);

        (uint256 amountCalculatedRaw, uint256 amountCalculatedScaled18, uint256 amountIn, uint256 amountOut) = (
            0,
            0,
            0,
            0
        );
        (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut) = _manualInternalSwap(locals);

        _checkSwapStateUnchanged(locals.swapState, 0, 1, 0, amountGivenScaled18);
        _checkSwapExactInResult(
            defaultAmountGivenRaw,
            amountCalculatedRaw,
            amountCalculatedScaled18,
            amountIn,
            amountOut,
            locals.params,
            locals.swapState,
            locals.poolData
        );
    }

    function testSwapExactInWithFee() public {
        TestStateLocals memory locals;
        (locals.params, locals.swapState, locals.poolData) = _makeParams(
            SwapKind.EXACT_IN,
            defaultAmountGivenRaw,
            0,
            defaultSwapFeePercentage,
            defaultProtocolFeePercentage,
            defaultCreatorFeePercentage
        );
        uint256 amountGivenScaled18 = locals.swapState.amountGivenScaled18;

        _mockOnSwap(mockedPoolAmountCalculatedScaled18, locals.params, locals.swapState, locals.poolData);

        (uint256 amountCalculatedRaw, uint256 amountCalculatedScaled18, uint256 amountIn, uint256 amountOut) = (
            0,
            0,
            0,
            0
        );
        (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut) = _manualInternalSwap(locals);

        _checkSwapStateUnchanged(locals.swapState, 0, 1, defaultSwapFeePercentage, amountGivenScaled18);
        _checkSwapExactInResult(
            defaultAmountGivenRaw,
            amountCalculatedRaw,
            amountCalculatedScaled18,
            amountIn,
            amountOut,
            locals.params,
            locals.swapState,
            locals.poolData
        );
    }

    function testSwapExactInSwapLimitRevert() public {
        uint256 swapLimit = mockedPoolAmountCalculatedScaled18 - 1;

        (SwapParams memory params, SwapState memory state, PoolData memory poolData) = _makeParams(
            SwapKind.EXACT_IN,
            defaultAmountGivenRaw,
            swapLimit,
            0,
            0,
            0
        );

        uint256 amount = mockedPoolAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[state.indexOut],
            poolData.tokenRates[state.indexOut]
        );

        _mockOnSwap(mockedPoolAmountCalculatedScaled18, params, state, poolData);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, amount, swapLimit));
        vault.manualInternalSwap(params, state, poolData);
    }

    function testSwapExactOutSwapLimitRevert() public {
        (SwapParams memory params, SwapState memory state, PoolData memory poolData) = _makeParams(
            SwapKind.EXACT_OUT,
            defaultAmountGivenRaw,
            0,
            0,
            0,
            0
        );

        uint256 amount = mockedPoolAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[state.indexIn],
            poolData.tokenRates[state.indexIn]
        );

        _mockOnSwap(mockedPoolAmountCalculatedScaled18, params, state, poolData);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, amount, 0));
        vault.manualInternalSwap(params, state, poolData);
    }

    function testSwapExactOutWithZeroFee() public {
        TestStateLocals memory locals;
        (locals.params, locals.swapState, locals.poolData) = _makeParams(
            SwapKind.EXACT_OUT,
            defaultAmountGivenRaw,
            mockedPoolAmountCalculatedScaled18,
            0,
            0,
            0
        );
        uint256 amountGivenScaled18 = locals.swapState.amountGivenScaled18;

        _mockOnSwap(mockedPoolAmountCalculatedScaled18, locals.params, locals.swapState, locals.poolData);

        (uint256 amountCalculatedRaw, uint256 amountCalculatedScaled18, uint256 amountIn, uint256 amountOut) = (
            0,
            0,
            0,
            0
        );

        (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut) = _manualInternalSwap(locals);

        _checkSwapStateUnchanged(locals.swapState, 0, 1, 0, amountGivenScaled18);
        _checkSwapExactOutResult(
            defaultAmountGivenRaw,
            amountCalculatedRaw,
            amountCalculatedScaled18,
            amountIn,
            amountOut,
            locals.params,
            locals.swapState,
            locals.poolData
        );
    }

    function testSwapExactOutWithFee() public {
        TestStateLocals memory locals;
        {
            uint256 swapFeeAmount = mockedPoolAmountCalculatedScaled18.mulDivUp(
                defaultSwapFeePercentage,
                defaultSwapFeePercentage.complement()
            );

            uint256 amountCalculatedWithFee = mockedPoolAmountCalculatedScaled18 + swapFeeAmount;
            // This sets the protocol swap fee percentage to the same as the swap fee percentage
            (locals.params, locals.swapState, locals.poolData) = _makeParams(
                SwapKind.EXACT_OUT,
                defaultAmountGivenRaw,
                amountCalculatedWithFee,
                defaultSwapFeePercentage,
                defaultProtocolFeePercentage,
                defaultCreatorFeePercentage
            );
        }
        uint256 amountGivenScaled18 = locals.swapState.amountGivenScaled18;

        _mockOnSwap(mockedPoolAmountCalculatedScaled18, locals.params, locals.swapState, locals.poolData);
        (uint256 amountCalculatedRaw, uint256 amountCalculatedScaled18, uint256 amountIn, uint256 amountOut) = (
            0,
            0,
            0,
            0
        );
        (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut) = _manualInternalSwap(locals);

        _checkSwapStateUnchanged(locals.swapState, 0, 1, defaultSwapFeePercentage, amountGivenScaled18);
        _checkSwapExactOutResult(
            defaultAmountGivenRaw,
            amountCalculatedRaw,
            amountCalculatedScaled18,
            amountIn,
            amountOut,
            locals.params,
            locals.swapState,
            locals.poolData
        );
    }

    // #region Helpers
    function _makeParams(
        SwapKind kind,
        uint256 amountGivenRaw,
        uint256 limitRaw,
        uint256 swapFeePercentage,
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) internal view returns (SwapParams memory params, SwapState memory swapState, PoolData memory poolData) {
        params = SwapParams({
            kind: kind,
            pool: pool,
            tokenIn: swapTokens[0],
            tokenOut: swapTokens[1],
            amountGivenRaw: amountGivenRaw,
            limitRaw: limitRaw,
            userData: new bytes(0)
        });

        swapState.indexIn = 0;
        swapState.indexOut = 1;
        swapState.swapFeePercentage = swapFeePercentage;
        swapState.amountGivenScaled18 = amountGivenRaw.toScaled18ApplyRateRoundDown(
            decimalScalingFactors[kind == SwapKind.EXACT_IN ? swapState.indexIn : swapState.indexOut],
            tokenRates[kind == SwapKind.EXACT_IN ? swapState.indexIn : swapState.indexOut]
        );

        poolData.decimalScalingFactors = decimalScalingFactors;
        poolData.tokenRates = tokenRates;
        poolData.balancesRaw = initialBalances;

        poolData.poolConfigBits = poolData
            .poolConfigBits
            .setStaticSwapFeePercentage(swapFeePercentage)
            .setAggregateSwapFeePercentage(
                feeController.computeAggregateFeePercentage(protocolFeePercentage, poolCreatorFeePercentage)
            );

        poolData.balancesLiveScaled18 = new uint256[](initialBalances.length);
    }

    function _checkSwapExactInResult(
        uint256 amountGivenRaw,
        uint256 amountCalculatedRaw,
        uint256 amountCalculatedScaled18,
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapState memory swapState,
        PoolData memory poolData
    ) internal view {
        // Check swap state
        assertEq(swapState.indexIn, 0, "Unexpected index in");
        assertEq(swapState.indexOut, 1, "Unexpected index out");
        assertEq(
            swapState.swapFeePercentage,
            poolData.poolConfigBits.getStaticSwapFeePercentage(),
            "Unexpected swapFeePercentage"
        );
        assertEq(
            swapState.amountGivenScaled18,
            amountGivenRaw.toScaled18ApplyRateRoundDown(
                poolData.decimalScalingFactors[swapState.indexIn],
                poolData.tokenRates[swapState.indexIn]
            ),
            "Unexpected amount given scaled 18"
        );

        uint256 expectedSwapFeeAmountScaled18 = mockedPoolAmountCalculatedScaled18.mulUp(
            poolData.poolConfigBits.getStaticSwapFeePercentage()
        );

        uint256 expectedAmountCalculatedScaled18 = mockedPoolAmountCalculatedScaled18 - expectedSwapFeeAmountScaled18;
        uint256 expectedAmountOut = expectedAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[swapState.indexOut],
            poolData.tokenRates[swapState.indexOut]
        );

        assertEq(amountCalculatedRaw, amountOut, "Unexpected amountCalculated");
        assertEq(amountIn, amountGivenRaw, "Unexpected amountIn");
        assertEq(amountOut, expectedAmountOut, "Unexpected amountOut");
        assertEq(amountCalculatedScaled18, expectedAmountCalculatedScaled18, "Unexpected amountCalculatedScaled18");

        // Expected fees
        uint256 expectedProtocolSwapFeeAmountScaled18 = expectedSwapFeeAmountScaled18.mulUp(
            poolData.poolConfigBits.getAggregateSwapFeePercentage()
        );

        uint256 expectedProtocolFeeAmountRaw = expectedProtocolSwapFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[swapState.indexOut],
            poolData.tokenRates[swapState.indexOut]
        );

        assertEq(
            vault.getAggregateSwapFeeAmount(pool, swapTokens[swapState.indexOut]),
            expectedProtocolFeeAmountRaw,
            "Unexpected protocol fees in storage"
        );
        assertEq(
            vault.getAggregateSwapFeeAmount(pool, swapTokens[swapState.indexIn]),
            0,
            "Unexpected non-zero protocol fees in storage"
        );

        _checkCommonSwapResult(amountIn, amountOut, expectedProtocolFeeAmountRaw, params, swapState, poolData);
    }

    function _checkSwapExactOutResult(
        uint256 amountGivenRaw,
        uint256 amountCalculatedRaw,
        uint256 amountCalculatedScaled18,
        uint256 amountIn,
        uint256 amountOut,
        SwapParams memory params,
        SwapState memory swapState,
        PoolData memory poolData
    ) internal view {
        // Check swap state
        assertEq(swapState.indexIn, 0, "Unexpected index in");
        assertEq(swapState.indexOut, 1, "Unexpected index out");
        assertEq(
            swapState.swapFeePercentage,
            poolData.poolConfigBits.getStaticSwapFeePercentage(),
            "Unexpected swapFeePercentage"
        );
        assertEq(
            swapState.amountGivenScaled18,
            amountGivenRaw.toScaled18ApplyRateRoundDown(
                poolData.decimalScalingFactors[swapState.indexOut],
                poolData.tokenRates[swapState.indexOut]
            ),
            "Unexpected amount given scaled 18"
        );

        uint256 swapFee = poolData.poolConfigBits.getStaticSwapFeePercentage();
        uint256 expectedSwapFeeAmountScaled18 = mockedPoolAmountCalculatedScaled18.mulDivUp(
            swapFee,
            swapFee.complement()
        );

        uint256 expectedAmountCalculatedScaled18 = mockedPoolAmountCalculatedScaled18 + expectedSwapFeeAmountScaled18;
        uint256 expectedAmountIn = expectedAmountCalculatedScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[swapState.indexIn],
            poolData.tokenRates[swapState.indexIn]
        );

        assertEq(amountCalculatedRaw, expectedAmountIn, "Unexpected amountCalculated");
        assertEq(amountIn, expectedAmountIn, "Unexpected amountIn");
        assertEq(amountOut, amountGivenRaw, "Unexpected amountOut");
        assertEq(amountCalculatedScaled18, expectedAmountCalculatedScaled18, "Unexpected amountCalculatedScaled18");

        // Expected fees
        uint256 expectedProtocolFeeAmountScaled18 = expectedSwapFeeAmountScaled18.mulUp(
            poolData.poolConfigBits.getAggregateSwapFeePercentage()
        );

        uint256 expectedProtocolFeeAmountRaw = expectedProtocolFeeAmountScaled18.toRawUndoRateRoundDown(
            poolData.decimalScalingFactors[swapState.indexIn],
            poolData.tokenRates[swapState.indexIn]
        );

        assertEq(
            vault.getAggregateSwapFeeAmount(pool, swapTokens[swapState.indexIn]),
            expectedProtocolFeeAmountRaw,
            "Unexpected protocol fees in storage"
        );
        assertEq(
            vault.getAggregateSwapFeeAmount(pool, swapTokens[swapState.indexOut]),
            0,
            "Unexpected non-zero protocol fees in storage"
        );

        _checkCommonSwapResult(amountIn, amountOut, expectedProtocolFeeAmountRaw, params, swapState, poolData);
    }

    function _checkCommonSwapResult(
        uint256 amountIn,
        uint256 amountOut,
        uint256 totalFees,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal view {
        uint256 feesOnAmountOut = params.kind == SwapKind.EXACT_IN ? totalFees : 0;
        uint256 feesOnAmountIn = params.kind == SwapKind.EXACT_IN ? 0 : totalFees;

        // check balances updated
        assertEq(
            poolData.balancesRaw[state.indexIn],
            initialBalances[state.indexIn] + amountIn - feesOnAmountIn,
            "Unexpected balanceRaw[state.indexIn]"
        );
        assertEq(
            poolData.balancesRaw[state.indexOut],
            initialBalances[state.indexOut] - amountOut - feesOnAmountOut,
            "Unexpected balanceRaw[state.indexOut]"
        );

        // check _writePoolBalancesToStorage called
        uint256[] memory expectedBalancesLiveScaled18 = poolData.balancesRaw.copyToScaled18ApplyRateRoundDownArray(
            poolData.decimalScalingFactors,
            poolData.tokenRates
        );
        assertEq(
            poolData.balancesLiveScaled18[state.indexIn],
            expectedBalancesLiveScaled18[state.indexIn],
            "Unexpected balancesLiveScaled18[state.indexIn]"
        );
        assertEq(
            poolData.balancesLiveScaled18[state.indexOut],
            expectedBalancesLiveScaled18[state.indexOut],
            "Unexpected balancesLiveScaled18[state.indexOut]"
        );

        uint256[] memory storageRawBalances = vault.getRawBalances(params.pool);
        assertEq(storageRawBalances.length, poolData.balancesRaw.length, "Unexpected storageRawBalances length");
        assertEq(
            storageRawBalances[state.indexIn],
            poolData.balancesRaw[state.indexIn],
            "Unexpected storageRawBalances[state.indexIn]"
        );
        assertEq(
            storageRawBalances[state.indexOut],
            poolData.balancesRaw[state.indexOut],
            "Unexpected storageRawBalances[state.indexIn]"
        );

        uint256[] memory storageLiveBalances = vault.getLastLiveBalances(params.pool);
        assertEq(
            storageLiveBalances.length,
            poolData.balancesLiveScaled18.length,
            "Unexpected storageRawBalances length"
        );
        assertEq(
            storageLiveBalances[state.indexIn],
            poolData.balancesLiveScaled18[state.indexIn],
            "Unexpected storageLiveBalances[state.indexIn]"
        );
        assertEq(
            storageLiveBalances[state.indexOut],
            poolData.balancesLiveScaled18[state.indexOut],
            "Unexpected storageLiveBalances[state.indexIn]"
        );

        // check _takeDebt called
        assertEq(vault.getTokenDelta(swapTokens[0]), int256(amountIn), "Unexpected tokenIn delta");

        // check _supplyCredit called
        assertEq(vault.getTokenDelta(swapTokens[1]), -int256(amountOut), "Unexpected tokenOut delta");
    }

    function _checkSwapStateUnchanged(
        SwapState memory swapState,
        uint256 expectedIndexIn,
        uint256 expectedIndexOut,
        uint256 expectedSwapFeePercentage,
        uint256 expectedAmountGivenScaled18
    ) internal pure {
        assertEq(swapState.indexIn, expectedIndexIn, "index in changed");
        assertEq(swapState.indexOut, expectedIndexOut, "index out changed");
        assertEq(swapState.swapFeePercentage, expectedSwapFeePercentage, "swap fee percentage changed");
        assertEq(swapState.amountGivenScaled18, expectedAmountGivenScaled18, "amount given scaled 18 changed");
    }

    function _mockOnSwap(
        uint256 amountCalculatedScaled18,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal {
        vm.mockCall(
            pool,
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                PoolSwapParams({
                    kind: params.kind,
                    amountGivenScaled18: state.amountGivenScaled18,
                    balancesScaled18: poolData.balancesLiveScaled18,
                    indexIn: state.indexIn,
                    indexOut: state.indexOut,
                    router: address(this),
                    userData: params.userData
                })
            ),
            abi.encodePacked(amountCalculatedScaled18)
        );
    }

    /**
     * @dev Prevents stack-too-deep while preserving any side-effects applied to the memory inside the Vault.
     */
    function _manualInternalSwap(
        TestStateLocals memory locals
    )
        internal
        returns (uint256 amountCalculatedRaw, uint256 amountCalculatedScaled18, uint256 amountIn, uint256 amountOut)
    {
        (
            amountCalculatedRaw,
            amountCalculatedScaled18,
            amountIn,
            amountOut,
            locals.params,
            locals.swapState,
            locals.poolData
        ) = vault.manualInternalSwap(locals.params, locals.swapState, locals.poolData);
        return (amountCalculatedRaw, amountCalculatedScaled18, amountIn, amountOut);
    }
    // #endregion
}
