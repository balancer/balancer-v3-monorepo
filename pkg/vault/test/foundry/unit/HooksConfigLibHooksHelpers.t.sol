// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigConst } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigConst.sol";
import { HooksConfigLib } from "@balancer-labs/v3-vault/contracts/lib/HooksConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { HooksConfigLibMock } from "@balancer-labs/v3-vault/contracts/test/HooksConfigLibMock.sol";

contract HooksConfigLibHooksHelpersTest is Test {
    using WordCodec for bytes32;
    using HooksConfigLib for PoolConfigBits;

    address router = address(0x00);
    address pool = address(0x11);
    address hooksContract = address(0x1234567890123456789012345678901234567890);
    HooksConfigLibMock hooksConfigLibMock;

    function setUp() public {
        hooksConfigLibMock = new HooksConfigLibMock();
    }
    //#region callComputeDynamicSwapFeeHook
    function testCallComputeDynamicSwapFeeHook() public {
        uint256 swapFeePercentage = 6e5;

        IBasePool.PoolSwapParams memory swapParams;
        uint256 staticSwapFeePercentage = 3e5;
        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onComputeDynamicSwapFeePercentage.selector,
                swapParams,
                pool,
                staticSwapFeePercentage
            ),
            abi.encode(true, swapFeePercentage)
        );

        PoolConfigBits config;
        (bool success, uint256 value) = hooksConfigLibMock.callComputeDynamicSwapFeeHook(
            swapParams,
            pool,
            staticSwapFeePercentage,
            IHooks(hooksContract)
        );

        assertEq(success, true, "callComputeDynamicSwapFeeHook is not successful");
        assertEq(value, swapFeePercentage, "swap fee percentage mismatch");
    }

    function testCallComputeDynamicSwapFeeHookRevertIfCallIsNotSuccess() public {
        uint256 swapFeePercentage = 6e5;

        IBasePool.PoolSwapParams memory swapParams;
        uint256 staticSwapFeePercentage = 3e5;
        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onComputeDynamicSwapFeePercentage.selector,
                swapParams,
                pool,
                staticSwapFeePercentage
            ),
            abi.encode(false, swapFeePercentage)
        );
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.DynamicSwapFeeHookFailed.selector));

        PoolConfigBits config;
        hooksConfigLibMock.callComputeDynamicSwapFeeHook(
            swapParams,
            pool,
            staticSwapFeePercentage,
            IHooks(hooksContract)
        );
    }

    //#endregion

    // #region callBeforeSwapHook tests

    // #endregion

    //#region callAfterSwapHook tests
    function testCallAfterSwapHookExactIn() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwapHook(SwapKind.EXACT_IN, 0);

        PoolConfigBits config;
        uint256 value = _callAfterSwapHook(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );

        assertEq(value, amountCalculatedRaw, "return value mismatch");
    }

    function testCallAfterSwapHookExactOut() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwapHook(SwapKind.EXACT_OUT, type(uint256).max);

        PoolConfigBits config;
        uint256 value = _callAfterSwapHook(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );

        assertEq(value, amountCalculatedRaw, "return value mismatch");
    }

    function testCallAfterSwapHookExactInWithAdjustedAmounts() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwapHook(SwapKind.EXACT_IN, 0);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        uint256 value = _callAfterSwapHook(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );

        assertEq(value, hookAdjustedAmountCalculatedRaw, "return value mismatch");
    }

    function testCallAfterSwapHookExactOutWithAdjustedAmounts() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwapHook(SwapKind.EXACT_OUT, type(uint256).max);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        uint256 value = _callAfterSwapHook(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );

        assertEq(value, hookAdjustedAmountCalculatedRaw, "return value mismatch");
    }

    function testCallAfterSwapHookExactInRevertHookAdjustedSwapLimit() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwapHook(SwapKind.EXACT_IN, type(uint256).max);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        _callAfterSwapHookAndExpectRevert(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );
    }

    function testCallAfterSwapHookExactOutRevertHookAdjustedSwapLimit() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwapHook(SwapKind.EXACT_OUT, 0);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        _callAfterSwapHookAndExpectRevert(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );
    }

    function _getParamsForCallAfterSwapHook(
        SwapKind kind,
        uint256 limitRaw
    )
        internal
        pure
        returns (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        )
    {
        amountCalculatedScaled18 = 1e18;
        amountCalculatedRaw = 2e18;
        hookAdjustedAmountCalculatedRaw = 12e18;

        params.kind = kind;
        params.tokenIn = IERC20(address(0x01));
        params.tokenOut = IERC20(address(0x02));
        params.limitRaw = limitRaw;

        state.indexIn = 0;
        state.indexOut = 1;
        state.amountGivenScaled18 = 1e18;

        poolData.balancesLiveScaled18 = new uint256[](2);
    }

    function _callAfterSwapHook(
        PoolConfigBits config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        uint256 hookAdjustedAmountCalculatedRaw,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal returns (uint256 value) {
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
                    kind: params.kind,
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    amountInScaled18: amountInScaled18,
                    amountOutScaled18: amountOutScaled18,
                    tokenInBalanceScaled18: poolData.balancesLiveScaled18[state.indexIn],
                    tokenOutBalanceScaled18: poolData.balancesLiveScaled18[state.indexOut],
                    amountCalculatedScaled18: amountCalculatedScaled18,
                    amountCalculatedRaw: amountCalculatedRaw,
                    router: router,
                    pool: params.pool,
                    userData: params.userData
                })
            ),
            abi.encode(true, hookAdjustedAmountCalculatedRaw)
        );

        return
            hooksConfigLibMock.callAfterSwapHook(
                config,
                amountCalculatedScaled18,
                amountCalculatedRaw,
                router,
                params,
                state,
                poolData,
                IHooks(hooksContract)
            );
    }

    function _callAfterSwapHookAndExpectRevert(
        PoolConfigBits config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        uint256 hookAdjustedAmountCalculatedRaw,
        SwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal {
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onAfterSwap.selector,
                IHooks.AfterSwapParams({
                    kind: params.kind,
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    amountInScaled18: amountInScaled18,
                    amountOutScaled18: amountOutScaled18,
                    tokenInBalanceScaled18: poolData.balancesLiveScaled18[state.indexIn],
                    tokenOutBalanceScaled18: poolData.balancesLiveScaled18[state.indexOut],
                    amountCalculatedScaled18: amountCalculatedScaled18,
                    amountCalculatedRaw: amountCalculatedRaw,
                    router: router,
                    pool: params.pool,
                    userData: params.userData
                })
            ),
            abi.encode(true, hookAdjustedAmountCalculatedRaw)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookAdjustedSwapLimit.selector,
                hookAdjustedAmountCalculatedRaw,
                params.limitRaw
            )
        );

        hooksConfigLibMock.callAfterSwapHook(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            router,
            params,
            state,
            poolData,
            IHooks(hooksContract)
        );
    }
    //#endregion
}
