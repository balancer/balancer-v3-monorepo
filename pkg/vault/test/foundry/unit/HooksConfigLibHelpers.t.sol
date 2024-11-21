// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { HooksConfigLibMock } from "@balancer-labs/v3-vault/contracts/test/HooksConfigLibMock.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { PoolConfigConst } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigConst.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { HooksConfigLib } from "@balancer-labs/v3-vault/contracts/lib/HooksConfigLib.sol";

import { VaultContractsDeployer } from "../utils/VaultContractsDeployer.sol";

contract HooksConfigLibHelpersTest is VaultContractsDeployer {
    using WordCodec for bytes32;
    using HooksConfigLib for PoolConfigBits;

    address router = address(0x00);
    address pool = address(0x11);
    address hooksContract = address(0x1234567890123456789012345678901234567890);
    HooksConfigLibMock hooksConfigLibMock;

    function setUp() public {
        hooksConfigLibMock = deployHooksConfigLibMock();
    }

    // callComputeDynamicSwapFeeHook
    function testCallComputeDynamicSwapFee() public {
        uint256 swapFeePercentage = MAX_FEE_PERCENTAGE;
        PoolSwapParams memory swapParams;

        uint256 staticSwapFeePercentage = swapFeePercentage;
        vm.mockCall(
            hooksContract,
            abi.encodeCall(IHooks.onComputeDynamicSwapFeePercentage, (swapParams, pool, staticSwapFeePercentage)),
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

    function testCallComputeDynamicSwapFeeAboveMax() public {
        PoolSwapParams memory swapParams;

        vm.mockCall(
            hooksContract,
            abi.encodeCall(IHooks.onComputeDynamicSwapFeePercentage, (swapParams, pool, MAX_FEE_PERCENTAGE)),
            abi.encode(true, MAX_FEE_PERCENTAGE + 1)
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PercentageAboveMax.selector));
        hooksConfigLibMock.callComputeDynamicSwapFeeHook(swapParams, pool, MAX_FEE_PERCENTAGE, IHooks(hooksContract));
    }

    function testCallComputeDynamicSwapFeeRevertIfCallIsNotSuccess() public {
        uint256 swapFeePercentage = MAX_FEE_PERCENTAGE;

        PoolSwapParams memory swapParams;
        uint256 staticSwapFeePercentage = swapFeePercentage - 1;
        vm.mockCall(
            hooksContract,
            abi.encodeCall(IHooks.onComputeDynamicSwapFeePercentage, (swapParams, pool, staticSwapFeePercentage)),
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

    // callBeforeSwapHook tests
    function testCallBeforeSwap() public {
        PoolSwapParams memory swapParams;
        vm.mockCall(hooksContract, abi.encodeCall(IHooks.onBeforeSwap, (swapParams, pool)), abi.encode(true));

        hooksConfigLibMock.callBeforeSwapHook(swapParams, pool, IHooks(hooksContract));
    }

    function testCallBeforeSwapRevertIfCallIsNotSuccess() public {
        PoolSwapParams memory swapParams;
        vm.mockCall(hooksContract, abi.encodeCall(IHooks.onBeforeSwap, (swapParams, pool)), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeSwapHookFailed.selector));

        hooksConfigLibMock.callBeforeSwapHook(swapParams, pool, IHooks(hooksContract));
    }

    // callAfterSwapHook tests
    function testCallAfterSwapExactIn() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwap(SwapKind.EXACT_IN, 0);

        PoolConfigBits config;
        uint256 value = _callAfterSwap(
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

    function testCallAfterSwapExactOut() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwap(SwapKind.EXACT_OUT, type(uint256).max);

        PoolConfigBits config;
        uint256 value = _callAfterSwap(
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

    function testCallAfterSwapExactInWithAdjustedAmounts() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwap(SwapKind.EXACT_IN, 0);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        uint256 value = _callAfterSwap(
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

    function testCallAfterSwapExactOutWithAdjustedAmounts() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwap(SwapKind.EXACT_OUT, type(uint256).max);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        uint256 value = _callAfterSwap(
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

    function testCallAfterSwapExactInRevertAdjustedSwapLimit() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwap(SwapKind.EXACT_IN, type(uint256).max);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        _callAfterSwapAndExpectRevert(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );
    }

    function testCallAfterSwapExactOutRevertAdjustedSwapLimit() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwap(SwapKind.EXACT_OUT, 0);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        _callAfterSwapAndExpectRevert(
            config,
            amountCalculatedScaled18,
            amountCalculatedRaw,
            hookAdjustedAmountCalculatedRaw,
            params,
            state,
            poolData
        );
    }

    function testCallAfterSwapRevertIfCallIsNotSuccess() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwap(SwapKind.EXACT_OUT, 0);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onAfterSwap,
                AfterSwapParams({
                    kind: params.kind,
                    tokenIn: params.tokenIn,
                    tokenOut: params.tokenOut,
                    amountInScaled18: amountCalculatedScaled18,
                    amountOutScaled18: state.amountGivenScaled18,
                    tokenInBalanceScaled18: poolData.balancesLiveScaled18[state.indexIn],
                    tokenOutBalanceScaled18: poolData.balancesLiveScaled18[state.indexOut],
                    amountCalculatedScaled18: amountCalculatedScaled18,
                    amountCalculatedRaw: amountCalculatedRaw,
                    router: router,
                    pool: params.pool,
                    userData: params.userData
                })
            ),
            abi.encode(false, hookAdjustedAmountCalculatedRaw)
        );

        PoolConfigBits config;
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterSwapHookFailed.selector));
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

    function _getParamsForCallAfterSwap(
        SwapKind kind,
        uint256 limitRaw
    )
        internal
        pure
        returns (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            VaultSwapParams memory params,
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

    function _callAfterSwap(
        PoolConfigBits config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        uint256 hookAdjustedAmountCalculatedRaw,
        VaultSwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal returns (uint256 value) {
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onAfterSwap,
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

    function _callAfterSwapAndExpectRevert(
        PoolConfigBits config,
        uint256 amountCalculatedScaled18,
        uint256 amountCalculatedRaw,
        uint256 hookAdjustedAmountCalculatedRaw,
        VaultSwapParams memory params,
        SwapState memory state,
        PoolData memory poolData
    ) internal {
        (uint256 amountInScaled18, uint256 amountOutScaled18) = params.kind == SwapKind.EXACT_IN
            ? (state.amountGivenScaled18, amountCalculatedScaled18)
            : (amountCalculatedScaled18, state.amountGivenScaled18);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onAfterSwap,
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

    // callBeforeAddLiquidityHook tests
    function testCallBeforeAddLiquidity() public {
        uint256[] memory maxAmountsInScaled18 = new uint256[](2);

        AddLiquidityParams memory params;
        params.pool = pool;
        params.kind = AddLiquidityKind.PROPORTIONAL;
        params.minBptAmountOut = 1e18;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onBeforeAddLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    maxAmountsInScaled18,
                    params.minBptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    function testCallBeforeAddLiquidityRevertIfCallIsNotSuccess() public {
        uint256[] memory maxAmountsInScaled18 = new uint256[](2);

        AddLiquidityParams memory params;
        params.pool = pool;
        params.kind = AddLiquidityKind.PROPORTIONAL;
        params.minBptAmountOut = 1e18;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onBeforeAddLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    maxAmountsInScaled18,
                    params.minBptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    // callAfterAddLiquidityHook tests
    function testCallAfterAddLiquidity() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidity();

        PoolConfigBits config;
        uint256[] memory values = _callAfterAddLiquidity(
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

    function testCallAfterAddLiquidityWithAdjustedAmounts() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidity();

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
        uint256[] memory values = _callAfterAddLiquidity(
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

    function testCallAfterAddLiquidityRevertIfAdjustedAmountsInRawHaveDifferentLength() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidity();

        hookAdjustedAmountsInRaw = new uint256[](3);

        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.AfterAddLiquidityHookFailed.selector));
        _callAfterAddLiquidity(
            config,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            hookAdjustedAmountsInRaw,
            params,
            poolData
        );
    }

    function testCallAfterAddLiquidityRevertIfCallIsNotSuccess() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidity();

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onAfterAddLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    amountsInScaled18,
                    amountsInRaw,
                    bptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    function testCallAfterAddLiquidityRevertIfAdjustedAmountsInRawAboveMaxAmountsIn() public {
        (
            uint256[] memory amountsInScaled18,
            uint256[] memory amountsInRaw,
            uint256 bptAmountOut,
            uint256[] memory hookAdjustedAmountsInRaw,
            AddLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterAddLiquidity();

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
        _callAfterAddLiquidity(
            config,
            amountsInScaled18,
            amountsInRaw,
            bptAmountOut,
            hookAdjustedAmountsInRaw,
            params,
            poolData
        );
    }

    function _getParamsForCallAfterAddLiquidity()
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

    function _callAfterAddLiquidity(
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
            abi.encodeCall(
                IHooks.onAfterAddLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    amountsInScaled18,
                    amountsInRaw,
                    bptAmountOut,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    // callBeforeRemoveLiquidityHook tests
    function callBeforeRemoveLiquidity() public {
        uint256[] memory minAmountsOutScaled18 = new uint256[](2);

        RemoveLiquidityParams memory params;
        params.pool = pool;
        params.maxBptAmountIn = 1e18;
        params.kind = RemoveLiquidityKind.PROPORTIONAL;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onBeforeRemoveLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    params.maxBptAmountIn,
                    minAmountsOutScaled18,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    function callBeforeRemoveLiquidityRevertIfCallIsNotSuccess() public {
        uint256[] memory minAmountsOutScaled18 = new uint256[](2);

        RemoveLiquidityParams memory params;
        params.pool = pool;
        params.maxBptAmountIn = 1e18;
        params.kind = RemoveLiquidityKind.PROPORTIONAL;

        PoolData memory poolData;
        poolData.balancesLiveScaled18 = new uint256[](2);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onBeforeRemoveLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    params.maxBptAmountIn,
                    minAmountsOutScaled18,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    // callAfterRemoveLiquidityHook tests.
    function testCallAfterRemoveLiquidity() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidity();

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

    function testCallAfterRemoveLiquidityWithAdjustedAmounts() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidity();

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

    function testCallAfterRemoveLiquidityRevertIfAdjustedAmountsOutRawHaveDifferentLength() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidity();

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

    function testCallAfterRemoveLiquidityRevertIfCallIsNotSuccess() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidity();

        vm.mockCall(
            hooksContract,
            abi.encodeCall(
                IHooks.onAfterRemoveLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    bptAmountIn,
                    amountsOutScaled18,
                    amountsOutRaw,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    function testCallAfterRemoveLiquidityRevertIfAdjustedAmountsOutRawAboveMinAmountsOut() public {
        (
            uint256[] memory amountsOutScaled18,
            uint256[] memory amountsOutRaw,
            uint256 bptAmountIn,
            uint256[] memory hookAdjustedAmountsOutRaw,
            RemoveLiquidityParams memory params,
            PoolData memory poolData
        ) = _getParamsForCallAfterRemoveLiquidity();

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

    function _getParamsForCallAfterRemoveLiquidity()
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
            abi.encodeCall(
                IHooks.onAfterRemoveLiquidity,
                (
                    router,
                    params.pool,
                    params.kind,
                    bptAmountIn,
                    amountsOutScaled18,
                    amountsOutRaw,
                    poolData.balancesLiveScaled18,
                    params.userData
                )
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

    // callBeforeInitializeHook tests.
    function testCallBeforeInitialize() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(IHooks.onBeforeInitialize, (exactAmountsInScaled18, userData)),
            abi.encode(true)
        );

        hooksConfigLibMock.callBeforeInitializeHook(exactAmountsInScaled18, userData, IHooks(hooksContract));
    }

    function testCallBeforeInitializeRevertIfCallIsNotSuccess() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(IHooks.onBeforeInitialize, (exactAmountsInScaled18, userData)),
            abi.encode(false)
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.BeforeInitializeHookFailed.selector));
        hooksConfigLibMock.callBeforeInitializeHook(exactAmountsInScaled18, userData, IHooks(hooksContract));
    }

    // callAfterInitializeHook tests.
    function testCallAfterInitialize() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        uint256 bptAmountOut = 1e18;
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(IHooks.onAfterInitialize, (exactAmountsInScaled18, bptAmountOut, userData)),
            abi.encode(true)
        );

        hooksConfigLibMock.callAfterInitializeHook(
            exactAmountsInScaled18,
            bptAmountOut,
            userData,
            IHooks(hooksContract)
        );
    }

    function testCallAfterInitializeRevertIfCallIsNotSuccess() public {
        uint256[] memory exactAmountsInScaled18 = new uint256[](2);
        uint256 bptAmountOut = 1e18;
        bytes memory userData = new bytes(0);

        vm.mockCall(
            hooksContract,
            abi.encodeCall(IHooks.onAfterInitialize, (exactAmountsInScaled18, bptAmountOut, userData)),
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
}
