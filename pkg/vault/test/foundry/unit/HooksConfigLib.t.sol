// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigConst } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigConst.sol";
import { HooksConfigLib } from "@balancer-labs/v3-vault/contracts/lib/HooksConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

contract HooksConfigLibTest is Test {
    using WordCodec for bytes32;
    using HooksConfigLib for PoolConfigBits;

    address router = address(0x00);
    address hooksContract = address(0x1234567890123456789012345678901234567890);

    function testZeroConfigBytes() public pure {
        PoolConfigBits config;

        assertEq(config.enableHookAdjustedAmounts(), false, "enableHookAdjustedAmounts mismatch (zero config)");
        assertEq(config.shouldCallBeforeInitialize(), false, "shouldCallBeforeInitialize mismatch (zero config)");
        assertEq(config.shouldCallAfterInitialize(), false, "shouldCallAfterInitialize mismatch (zero config)");
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            false,
            "shouldCallComputeDynamicSwapFee mismatch (zero config)"
        );
        assertEq(config.shouldCallBeforeSwap(), false, "shouldCallBeforeSwap mismatch (zero config)");
        assertEq(config.shouldCallAfterSwap(), false, "shouldCallAfterSwap mismatch (zero config)");
        assertEq(config.shouldCallBeforeAddLiquidity(), false, "shouldCallBeforeAddLiquidity mismatch (zero config)");
        assertEq(config.shouldCallAfterAddLiquidity(), false, "shouldCallAfterAddLiquidity mismatch (zero config)");
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            false,
            "shouldCallBeforeRemoveLiquidity mismatch (zero config)"
        );
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            false,
            "shouldCallAfterRemoveLiquidity mismatch (zero config)"
        );
    }

    function testEnableHookAdjustedAmounts() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET)
        );
        assertTrue(config.enableHookAdjustedAmounts(), "enableHookAdjustedAmounts is false (getter)");
    }

    function testSetHookAdjustedAmounts() public pure {
        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
        assertTrue(config.enableHookAdjustedAmounts(), "enableHookAdjustedAmounts is false (setter)");
    }

    function testShouldCallBeforeInitialize() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (getter)");
    }

    function testSetShouldCallBeforeInitialize() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeInitialize(true);
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (setter)");
    }

    function testShouldCallAfterInitialize() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (getter)");
    }

    function testSetShouldCallAfterInitialize() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterInitialize(true);
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (setter)");
    }

    function testShouldCallComputeDynamicSwapFee() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.DYNAMIC_SWAP_FEE_OFFSET)
        );
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (getter)"
        );
    }

    function testSetShouldCallComputeDynamicSwapFee() public pure {
        PoolConfigBits config;
        config = config.setShouldCallComputeDynamicSwapFee(true);
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (setter)"
        );
    }

    function testShouldCallBeforeSwap() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_SWAP_OFFSET)
        );
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (getter)");
    }

    function testSetShouldCallBeforeSwap() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeSwap(true);
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (setter)");
    }

    function testShouldCallAfterSwap() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_SWAP_OFFSET));
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (getter)");
    }

    function testSetShouldCallAfterSwap() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterSwap(true);
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (setter)");
    }

    function testShouldCallBeforeAddLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (getter)");
    }

    function testSetShouldCallBeforeAddLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeAddLiquidity(true);
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (setter)");
    }

    function testShouldCallAfterAddLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (getter)");
    }

    function testSetShouldCallAfterAddLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterAddLiquidity(true);
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (setter)");
    }

    function testShouldCallBeforeRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.BEFORE_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallBeforeRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallBeforeRemoveLiquidity(true);
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (setter)"
        );
    }

    function testShouldCallAfterRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.AFTER_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallAfterRemoveLiquidity() public pure {
        PoolConfigBits config;
        config = config.setShouldCallAfterRemoveLiquidity(true);
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (setter)"
        );
    }

    function testToHooksConfig() public view {
        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
        config = config.setShouldCallBeforeInitialize(true);
        config = config.setShouldCallAfterInitialize(true);
        config = config.setShouldCallComputeDynamicSwapFee(true);
        config = config.setShouldCallBeforeSwap(true);
        config = config.setShouldCallAfterSwap(true);
        config = config.setShouldCallBeforeAddLiquidity(true);
        config = config.setShouldCallAfterAddLiquidity(true);
        config = config.setShouldCallBeforeRemoveLiquidity(true);
        config = config.setShouldCallAfterRemoveLiquidity(true);

        HooksConfig memory hooksConfig = config.toHooksConfig(IHooks(hooksContract));
        assertEq(hooksConfig.shouldCallBeforeInitialize, true, "shouldCallBeforeInitialize mismatch");
        assertEq(hooksConfig.shouldCallAfterInitialize, true, "shouldCallAfterInitialize mismatch");
        assertEq(hooksConfig.shouldCallComputeDynamicSwapFee, true, "shouldCallComputeDynamicSwapFee mismatch");

        assertEq(hooksConfig.shouldCallBeforeSwap, true, "shouldCallBeforeSwap mismatch");
        assertEq(hooksConfig.shouldCallAfterSwap, true, "shouldCallAfterSwap mismatch");
        assertEq(hooksConfig.shouldCallBeforeAddLiquidity, true, "shouldCallBeforeAddLiquidity mismatch");
        assertEq(hooksConfig.shouldCallAfterAddLiquidity, true, "shouldCallAfterAddLiquidity mismatch");
        assertEq(hooksConfig.shouldCallBeforeRemoveLiquidity, true, "shouldCallBeforeRemoveLiquidity mismatch");
        assertEq(hooksConfig.shouldCallAfterRemoveLiquidity, true, "shouldCallAfterRemoveLiquidity mismatch");
        assertEq(hooksConfig.hooksContract, hooksContract, "hooksContract mismatch");
    }

    function testCallAfterSwapHookExactIn() public {
        (
            uint256 amountCalculatedScaled18,
            uint256 amountCalculatedRaw,
            uint256 hookAdjustedAmountCalculatedRaw,
            SwapParams memory params,
            SwapState memory state,
            PoolData memory poolData
        ) = _getParamsForCallAfterSwapHookExactOut(SwapKind.EXACT_IN, 0);

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
        ) = _getParamsForCallAfterSwapHookExactOut(SwapKind.EXACT_OUT, type(uint256).max);

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
        ) = _getParamsForCallAfterSwapHookExactOut(SwapKind.EXACT_IN, 0);

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
        ) = _getParamsForCallAfterSwapHookExactOut(SwapKind.EXACT_OUT, type(uint256).max);

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

    // Private functions
    function _getParamsForCallAfterSwapHookExactOut(
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

        // Stack too deep
        PoolConfigBits config_ = config;
        return
            config_.callAfterSwapHook(
                amountCalculatedScaled18,
                amountCalculatedRaw,
                router,
                params,
                state,
                poolData,
                IHooks(hooksContract)
            );
    }
}
