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

contract HooksConfigLibHelpersTest is Test {
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
        uint256 swapFeePercentage = MAX_FEE_PERCENTAGE;

        PoolSwapParams memory swapParams;
        uint256 staticSwapFeePercentage = swapFeePercentage - 1;
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

        uint256 value = hooksConfigLibMock.callComputeDynamicSwapFeeHook(
            swapParams,
            pool,
            staticSwapFeePercentage,
            IHooks(hooksContract)
        );

        assertEq(value, swapFeePercentage, "swap fee percentage mismatch");
    }

    function testCallComputeDynamicSwapFeeHookRevertIfCallIsNotSuccess() public {
        uint256 swapFeePercentage = MAX_FEE_PERCENTAGE;

        PoolSwapParams memory swapParams;
        uint256 staticSwapFeePercentage = swapFeePercentage - 1;
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

        hooksConfigLibMock.callComputeDynamicSwapFeeHook(
            swapParams,
            pool,
            staticSwapFeePercentage,
            IHooks(hooksContract)
        );
    }

    //#endregion

    //#region callBeforeSwapHook tests
    function testCallBeforeSwapHook() public {
        PoolSwapParams memory swapParams;
        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(IHooks.onBeforeSwap.selector, swapParams, pool),
            abi.encode(true)
        );

        hooksConfigLibMock.callBeforeSwapHook(swapParams, pool, IHooks(hooksContract));
    }

    function testCallBeforeSwapHookRevertIfCallIsNotSuccess() public {
        PoolSwapParams memory swapParams;
        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(IHooks.onBeforeSwap.selector, swapParams, pool),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeSwapHookFailed.selector));

        hooksConfigLibMock.callBeforeSwapHook(swapParams, pool, IHooks(hooksContract));
    }

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

        assertEq(value, amountCalculatedRaw, "Wrong amountCalculatedRaw");
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

        assertEq(value, amountCalculatedRaw, "Wrong amountCalculatedRaw");
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
                AfterSwapParams({
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
                AfterSwapParams({
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

    //#region callBeforeAddLiquidityHook tests
    function testCallBeforeAddLiquidityHook() public {
        uint256[] memory maxAmountsInScaled18 = new uint256[](2);

        AddLiquidityParams memory params;
        params.pool = pool;
        params.kind = AddLiquidityKind.PROPORTIONAL;
        params.minBptAmountOut = 1e18;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onBeforeAddLiquidity.selector,
                router,
                params.pool,
                params.kind,
                maxAmountsInScaled18,
                params.minBptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(true)
        );

        hooksConfigLibMock.callBeforeAddLiquidityHook(
            router,
            maxAmountsInScaled18,
            params,
            poolData,
            IHooks(hooksContract)
        );
    }

    function testCallBeforeAddLiquidityHookRevertIfCallIsNotSuccess() public {
        uint256[] memory maxAmountsInScaled18 = new uint256[](2);

        AddLiquidityParams memory params;
        params.pool = pool;
        params.kind = AddLiquidityKind.PROPORTIONAL;
        params.minBptAmountOut = 1e18;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onBeforeAddLiquidity.selector,
                router,
                params.pool,
                params.kind,
                maxAmountsInScaled18,
                params.minBptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(false)
        );
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeAddLiquidityHookFailed.selector));

        hooksConfigLibMock.callBeforeAddLiquidityHook(
            router,
            maxAmountsInScaled18,
            params,
            poolData,
            IHooks(hooksContract)
        );
    }

    //#endregion

    //#region callAfterAddLiquidityHook tests
    function testCallAfterAddLiquidityHook() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidityHook();

        PoolConfigBits config;
        uint256[] memory values = _callAfterAddLiquidityHook(
            config,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            hookAdjustedAmountsInRaw,
            params,
            poolData
        );

        assertEq(values.length, amountsInRaw.length, "values length mismatch");
        assertEq(values[0], amountsInRaw[0], "amountsInRaw[0] mismatch");
        assertEq(values[1], amountsInRaw[1], "amountsInRaw[1] mismatch");
    }

    function testCallAfterAddLiquidityHookWithHookAdjustedAmounts() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidityHook();

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
        uint256[] memory values = _callAfterAddLiquidityHook(
            config,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            hookAdjustedAmountsInRaw,
            params,
            poolData
        );

        assertEq(values.length, hookAdjustedAmountsInRaw.length, "values length mismatch");
        assertEq(values[0], hookAdjustedAmountsInRaw[0], "hookAdjustedAmountsInRaw[0] mismatch");
        assertEq(values[1], hookAdjustedAmountsInRaw[1], "hookAdjustedAmountsInRaw[1] mismatch");
    }

    function testCallAfterAddLiquidityHookRevertIfHookAdjustedAmountsInRawHaveDifferentLength() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidityHook();

        hookAdjustedAmountsInRaw = new uint256[](3);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterAddLiquidityHookFailed.selector));
        _callAfterAddLiquidityHook(
            config,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            hookAdjustedAmountsInRaw,
            params,
            poolData
        );
    }

    function testCallAfterAddLiquidityHookRevertIfCallIsNotSuccess() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidityHook();

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                router,
                params.pool,
                params.kind,
                amountsInScaled18,
                amountsInRaw,
                bptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(false, hookAdjustedAmountsInRaw)
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterAddLiquidityHookFailed.selector));

        PoolConfigBits config;
        hooksConfigLibMock.callAfterAddLiquidityHook(
            config,
            router,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            params,
            poolData,
            IHooks(hooksContract)
        );
    }

    function testCallAfterAddLiquidityHookRevertIfHookAdjustedAmountsInRawAboveMaxAmountsIn() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidityHook();

        params.maxAmountsIn = new uint256[](2);
        params.maxAmountsIn[0] = hookAdjustedAmountsInRaw[0] - 1;
        params.maxAmountsIn[1] = hookAdjustedAmountsInRaw[1] - 1;

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookAdjustedAmountInAboveMax.selector,
                poolData.tokens[0],
                hookAdjustedAmountsInRaw[0],
                params.maxAmountsIn[0]
            )
        );
        _callAfterAddLiquidityHook(
            config,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            hookAdjustedAmountsInRaw,
            params,
            poolData
        );
    }

    function _getParamsForCallAfterAddLiquidityHook()
        internal
        view
        returns (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        )
    {
        amountsInScaled18 = new uint256[](2);
        amountsInRaw = new uint256[](2);
        amountsInRaw[0] = 2e18;
        amountsInRaw[1] = 3e18;

        bptAmountOut = 1e18;
        hookAdjustedAmountsInRaw = new uint256[](2);
        hookAdjustedAmountsInRaw[0] = 34e18;
        hookAdjustedAmountsInRaw[1] = 45e18;

        params.pool = pool;
        params.kind = AddLiquidityKind.PROPORTIONAL;
        params.minBptAmountOut = 1e18;
        params.maxAmountsIn = new uint256[](2);
        params.maxAmountsIn[0] = type(uint256).max;
        params.maxAmountsIn[1] = type(uint256).max;

        poolData.balancesLiveScaled18 = new uint256[](2);
        poolData.tokens = new IERC20[](2);
    }

    function _callAfterAddLiquidityHook(
        PoolConfigBits config,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        uint256[] memory hookAdjustedAmountsInRaw,
        AddLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (uint256[] memory values) {
        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onAfterAddLiquidity.selector,
                router,
                params.pool,
                params.kind,
                amountsInScaled18,
                amountsInRaw,
                bptAmountOut,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(true, hookAdjustedAmountsInRaw)
        );

        return
            hooksConfigLibMock.callAfterAddLiquidityHook(
                config,
                router,
                amountsInScaled18,
                amountsInRaw,
                bptAmountOut,
                params,
                poolData,
                IHooks(hooksContract)
            );
    }

    //#endregion

    //#region callBeforeRemoveLiquidityHook tests
    function callBeforeRemoveLiquidityHook() public {
        uint256[] memory minAmountsOutScaled18 = new uint256[](2);

        RemoveLiquidityParams memory params;
        params.pool = pool;
        params.maxBptAmountIn = 1e18;
        params.kind = RemoveLiquidityKind.PROPORTIONAL;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onBeforeRemoveLiquidity.selector,
                router,
                params.pool,
                params.kind,
                params.maxBptAmountIn,
                minAmountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(true)
        );

        hooksConfigLibMock.callBeforeRemoveLiquidityHook(
            minAmountsOutScaled18,
            router,
            params,
            poolData,
            IHooks(hooksContract)
        );
    }

    function callBeforeRemoveLiquidityHookRevertIfCallIsNotSuccess() public {
        uint256[] memory minAmountsOutScaled18 = new uint256[](2);

        RemoveLiquidityParams memory params;
        params.pool = pool;
        params.maxBptAmountIn = 1e18;
        params.kind = RemoveLiquidityKind.PROPORTIONAL;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onBeforeRemoveLiquidity.selector,
                router,
                params.pool,
                params.kind,
                params.maxBptAmountIn,
                minAmountsOutScaled18,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeRemoveLiquidityHookFailed.selector));
        hooksConfigLibMock.callBeforeRemoveLiquidityHook(
            minAmountsOutScaled18,
            router,
            params,
            poolData,
            IHooks(hooksContract)
        );
    }

    //#endregion

    //#region callAfterRemoveLiquidityHook tests
    function testCallAfterRemoveLiquidityHook() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidityHook();

        PoolConfigBits config;
        uint256[] memory values = _callAfterRemoveLiquidityHook(
            config,
            amountsOutScaled18,
            amountsOutRaw,
            bptAmountIn,
            hookAdjustedAmountsOutRaw,
            params,
            poolData
        );

        assertEq(values.length, amountsOutRaw.length, "values length mismatch");
        assertEq(values[0], amountsOutRaw[0], "amountsOutRaw[0] mismatch");
        assertEq(values[1], amountsOutRaw[1], "amountsOutRaw[1] mismatch");
    }

    function testCallAfterRemoveLiquidityHookWithHookAdjustedAmounts() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidityHook();

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
        uint256[] memory values = _callAfterRemoveLiquidityHook(
            config,
            amountsOutScaled18,
            amountsOutRaw,
            bptAmountIn,
            hookAdjustedAmountsOutRaw,
            params,
            poolData
        );

        assertEq(values.length, hookAdjustedAmountsOutRaw.length, "values length mismatch");
        assertEq(values[0], hookAdjustedAmountsOutRaw[0], "hookAdjustedAmountsOutRaw[0] mismatch");
        assertEq(values[1], hookAdjustedAmountsOutRaw[1], "hookAdjustedAmountsOutRaw[1] mismatch");
    }

    function testCallAfterRemoveLiquidityHookRevertIfHookAdjustedAmountsOutRawHaveDifferentLength() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidityHook();

        hookAdjustedAmountsOutRaw = new uint256[](3);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterRemoveLiquidityHookFailed.selector));
        _callAfterRemoveLiquidityHook(
            config,
            amountsOutScaled18,
            amountsOutRaw,
            bptAmountIn,
            hookAdjustedAmountsOutRaw,
            params,
            poolData
        );
    }

    function testCallAfterRemoveLiquidityHookRevertIfCallIsNotSuccess() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidityHook();

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onAfterRemoveLiquidity.selector,
                router,
                params.pool,
                params.kind,
                bptAmountIn,
                amountsOutScaled18,
                amountsOutRaw,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(false, hookAdjustedAmountsOutRaw)
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterRemoveLiquidityHookFailed.selector));

        PoolConfigBits config;
        hooksConfigLibMock.callAfterRemoveLiquidityHook(
            config,
            router,
            amountsOutScaled18,
            amountsOutRaw,
            bptAmountIn,
            params,
            poolData,
            IHooks(hooksContract)
        );
    }

    function testCallAfterRemoveLiquidityHookRevertIfHookAdjustedAmountsOutRawAboveMinAmountsOut() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidityHook();

        params.minAmountsOut = new uint256[](2);
        params.minAmountsOut[0] = hookAdjustedAmountsOutRaw[0] + 1;
        params.minAmountsOut[1] = hookAdjustedAmountsOutRaw[1] + 1;

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookAdjustedAmountOutBelowMin.selector,
                poolData.tokens[0],
                hookAdjustedAmountsOutRaw[0],
                params.minAmountsOut[0]
            )
        );
        _callAfterRemoveLiquidityHook(
            config,
            amountsOutScaled18,
            amountsOutRaw,
            bptAmountIn,
            hookAdjustedAmountsOutRaw,
            params,
            poolData
        );
    }

    function _getParamsForCallAfterRemoveLiquidityHook()
        internal
        view
        returns (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        )
    {
        amountsOutScaled18 = new uint256[](2);
        amountsOutRaw = new uint256[](2);
        amountsOutRaw[0] = 2e18;
        amountsOutRaw[1] = 3e18;

        bptAmountIn = 1e18;
        hookAdjustedAmountsOutRaw = new uint256[](2);
        hookAdjustedAmountsOutRaw[0] = 34e18;
        hookAdjustedAmountsOutRaw[1] = 45e18;

        params.pool = pool;
        params.kind = RemoveLiquidityKind.PROPORTIONAL;
        params.minAmountsOut = new uint256[](2);

        poolData.balancesLiveScaled18 = new uint256[](2);
        poolData.tokens = new IERC20[](2);
    }

    function _callAfterRemoveLiquidityHook(
        PoolConfigBits config,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256 bptAmountIn,
        uint256[] memory hookAdjustedAmountsOutRaw,
        RemoveLiquidityParams memory params,
        PoolData memory poolData
    ) internal returns (uint256[] memory values) {
        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(
                IHooks.onAfterRemoveLiquidity.selector,
                router,
                params.pool,
                params.kind,
                bptAmountIn,
                amountsOutScaled18,
                amountsOutRaw,
                poolData.balancesLiveScaled18,
                params.userData
            ),
            abi.encode(true, hookAdjustedAmountsOutRaw)
        );

        return
            hooksConfigLibMock.callAfterRemoveLiquidityHook(
                config,
                router,
                amountsOutScaled18,
                amountsOutRaw,
                bptAmountIn,
                params,
                poolData,
                IHooks(hooksContract)
            );
    }

    //#endregion

    //#region callBeforeInitializeHook tests
    function testCallBeforeInitializeHook() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(IHooks.onBeforeInitialize.selector, exactAmountsInScaled18, userData),
            abi.encode(true)
        );

        hooksConfigLibMock.callBeforeInitializeHook(exactAmountsInScaled18, userData, IHooks(hooksContract));
    }

    function testCallBeforeInitializeHookRevertIfCallIsNotSuccess() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(IHooks.onBeforeInitialize.selector, exactAmountsInScaled18, userData),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeInitializeHookFailed.selector));
        hooksConfigLibMock.callBeforeInitializeHook(exactAmountsInScaled18, userData, IHooks(hooksContract));
    }

    //#endregion

    //#region callAfterInitializeHook tests
    function testCallAfterInitializeHook() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        uint256 bptAmountOut = 1e18;
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(IHooks.onAfterInitialize.selector, exactAmountsInScaled18, bptAmountOut, userData),
            abi.encode(true)
        );

        hooksConfigLibMock.callAfterInitializeHook(
            exactAmountsInScaled18,
            bptAmountOut,
            userData,
            IHooks(hooksContract)
        );
    }

    function testCallAfterInitializeHookRevertIfCallIsNotSuccess() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        uint256 bptAmountOut = 1e18;
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeWithSelector(IHooks.onAfterInitialize.selector, exactAmountsInScaled18, bptAmountOut, userData),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterInitializeHookFailed.selector));
        hooksConfigLibMock.callAfterInitializeHook(
            exactAmountsInScaled18,
            bptAmountOut,
            userData,
            IHooks(hooksContract)
        );
    }
    //#endregion
}
