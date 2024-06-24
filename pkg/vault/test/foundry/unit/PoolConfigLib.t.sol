// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

contract PoolConfigLibTest is BaseBitsConfigTest {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    // Uses a uint24 (3 bytes): least significant 20 bits to store the values, and a 4-bit pad.
    // This maximum token count is also hard-coded in the Vault.
    uint8 private constant _TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 private constant _DECIMAL_DIFF_BITLENGTH = 5;

    uint8 private constant _TIMESTAMP_BITLENGTH = 32;

    uint256 private constant _MAX_UINT32_VALUE = type(uint32).max;
    uint256 private constant _MAX_UINT24_VALUE = type(uint24).max;

    function testOffsets() public {
        _checkBitsUsedOnce(PoolConfigLib.POOL_REGISTERED_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.POOL_INITIALIZED_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.POOL_PAUSED_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.POOL_RECOVERY_MODE_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.BEFORE_INITIALIZE_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.AFTER_INITIALIZE_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.DYNAMIC_SWAP_FEE_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.BEFORE_SWAP_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.AFTER_SWAP_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.AFTER_ADD_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET, _TOKEN_DECIMAL_DIFFS_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, _TIMESTAMP_BITLENGTH);
    }

    function testZeroConfigBytes() public {
        PoolConfigBits config;

        assertEq(config.enableHookAdjustedAmounts(), false, "enableHookAdjustedAmounts mismatch (zero config)");
        assertEq(config.isPoolRegistered(), false, "isPoolRegistered mismatch (zero config)");
        assertEq(config.isPoolInitialized(), false, "isPoolInitialized mismatch (zero config)");
        assertEq(config.isPoolPaused(), false, "isPoolPaused mismatch (zero config)");
        assertEq(config.isPoolInRecoveryMode(), false, "isPoolInRecoveryMode mismatch (zero config)");
        assertEq(config.supportsUnbalancedLiquidity(), true, "supportsUnbalancedLiquidity mismatch (zero config)");
        assertEq(config.supportsAddLiquidityCustom(), false, "supportsAddLiquidityCustom mismatch (zero config)");
        assertEq(config.supportsRemoveLiquidityCustom(), false, "supportsRemoveLiquidityCustom mismatch (zero config)");
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
        assertEq(config.getStaticSwapFeePercentage(), 0, "getStaticSwapFeePercentage mismatch (zero config)");
        assertEq(config.getAggregateSwapFeePercentage(), 0, "getAggregateSwapFeePercentage mismatch (zero config)");
        assertEq(config.getAggregateYieldFeePercentage(), 0, "getAggregateYieldFeePercentage mismatch (zero config)");
        assertEq(config.getTokenDecimalDiffs(), 0, "getTokenDecimalDiffs mismatch (zero config)");
        assertEq(config.getPauseWindowEndTime(), 0, "getPauseWindowEndTime mismatch (zero config)");
    }

    // #region Tests for main pool config settings
    function testEnableHookAdjustedAmounts() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET)
        );
        assertTrue(config.enableHookAdjustedAmounts(), "enableHookAdjustedAmounts is false (getter)");
    }

    function testSetHookAdjustedAmounts() public {
        PoolConfigBits config;
        config = config.setHookAdjustedAmounts(true);
        assertTrue(config.enableHookAdjustedAmounts(), "enableHookAdjustedAmounts is false (setter)");
    }

    function testIsPoolRegistered() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET)
        );
        assertTrue(config.isPoolRegistered(), "isPoolRegistered is false (getter)");
    }

    function testSetPoolRegistered() public {
        PoolConfigBits config;
        config = config.setPoolRegistered(true);
        assertTrue(config.isPoolRegistered(), "isPoolRegistered is false (setter)");
    }

    function testIsPoolInitialized() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET)
        );
        assertTrue(config.isPoolInitialized(), "isPoolInitialized is false (getter)");
    }

    function testSetPoolInitialized() public {
        PoolConfigBits config;
        config = config.setPoolInitialized(true);
        assertTrue(config.isPoolInitialized(), "isPoolInitialized is false (setter)");
    }

    function testIsPoolPaused() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET));
        assertTrue(config.isPoolPaused(), "isPoolPaused is false (getter)");
    }

    function testSetPoolPaused() public {
        PoolConfigBits config;
        config = config.setPoolPaused(true);
        assertTrue(config.isPoolPaused(), "isPoolPaused is false (setter)");
    }

    function testIsPoolInRecoveryMode() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET)
        );
        assertTrue(config.isPoolInRecoveryMode(), "isPoolInRecoveryMode is false (getter)");
    }

    function testSetPoolInRecoveryMode() public {
        PoolConfigBits config;
        config = config.setPoolInRecoveryMode(true);
        assertTrue(config.isPoolInRecoveryMode(), "isPoolInRecoveryMode is false (setter)");
    }

    // #endregion

    // #region Tests for liquidity operations
    function testSupportsUnbalancedLiquidity() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET)
        );
        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertFalse(config.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is true (getter)");
    }

    function testSetDisableUnbalancedLiquidity() public {
        PoolConfigBits config;
        config = config.setDisableUnbalancedLiquidity(true);
        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertFalse(config.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is true (setter)");
    }

    function testRequireUnbalancedLiquidityEnabled() public pure {
        PoolConfigBits config;

        // It's enabled by default
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireUnbalancedLiquidityRevertIfIsDisabled() public {
        PoolConfigBits config;
        config = config.setDisableUnbalancedLiquidity(true);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        config.requireUnbalancedLiquidityEnabled();
    }

    function testSupportsAddLiquidityCustom() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET)
        );
        assertTrue(config.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is false (getter)");
    }

    function testSetAddLiquidityCustom() public {
        PoolConfigBits config;
        config = config.setAddLiquidityCustom(true);
        assertTrue(config.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is false (setter)");
    }

    function testRequireAddCustomLiquidityEnabled() public pure {
        PoolConfigBits config;
        config = config.setAddLiquidityCustom(true);

        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityRevertIfIsDisabled() public {
        PoolConfigBits config;

        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        config.requireAddCustomLiquidityEnabled();
    }

    function testSupportsRemoveLiquidityCustom() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET)
        );
        assertTrue(config.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is false (getter)");
    }

    function testSetRemoveLiquidityCustom() public {
        PoolConfigBits config;
        config = config.setRemoveLiquidityCustom(true);
        assertTrue(config.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is false (setter)");
    }

    function testRequireRemoveCustomLiquidityEnabled() public pure {
        PoolConfigBits config;
        config = config.setRemoveLiquidityCustom(true);

        config.requireRemoveCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityReveryIfIsDisabled() public {
        PoolConfigBits config;

        vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
        config.requireRemoveCustomLiquidityEnabled();
    }

    // #endregion

    // #region Tests for hooks config
    function testShouldCallBeforeInitialize() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.BEFORE_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (getter)");
    }

    function testSetShouldCallBeforeInitialize() public {
        PoolConfigBits config;
        config = config = config.setShouldCallBeforeInitialize(true);
        assertEq(config.shouldCallBeforeInitialize(), true, "shouldCallBeforeInitialize should be true (setter)");
    }

    function testShouldCallAfterInitialize() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.AFTER_INITIALIZE_OFFSET)
        );
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (getter)");
    }

    function testSetShouldCallAfterInitialize() public {
        PoolConfigBits config;
        config = config.setShouldCallAfterInitialize(true);
        assertEq(config.shouldCallAfterInitialize(), true, "shouldCallAfterInitialize should be true (setter)");
    }

    function testShouldCallComputeDynamicSwapFee() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.DYNAMIC_SWAP_FEE_OFFSET)
        );
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (getter)"
        );
    }

    function testSetShouldCallComputeDynamicSwapFee() public {
        PoolConfigBits config;
        config = config.setShouldCallComputeDynamicSwapFee(true);
        assertEq(
            config.shouldCallComputeDynamicSwapFee(),
            true,
            "shouldCallComputeDynamicSwapFee should be true (setter)"
        );
    }

    function testShouldCallBeforeSwap() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.BEFORE_SWAP_OFFSET));
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (getter)");
    }

    function testSetShouldCallBeforeSwap() public {
        PoolConfigBits config;
        config = config.setShouldCallBeforeSwap(true);
        assertEq(config.shouldCallBeforeSwap(), true, "shouldCallBeforeSwap should be true (setter)");
    }

    function testShouldCallAfterSwap() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.AFTER_SWAP_OFFSET));
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (getter)");
    }

    function testSetShouldCallAfterSwap() public {
        PoolConfigBits config;
        config = config.setShouldCallAfterSwap(true);
        assertEq(config.shouldCallAfterSwap(), true, "shouldCallAfterSwap should be true (setter)");
    }

    function testShouldCallBeforeAddLiquidity() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (getter)");
    }

    function testSetShouldCallBeforeAddLiquidity() public {
        PoolConfigBits config;
        config = config.setShouldCallBeforeAddLiquidity(true);
        assertEq(config.shouldCallBeforeAddLiquidity(), true, "shouldCallBeforeAddLiquidity should be true (setter)");
    }

    function testShouldCallAfterAddLiquidity() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.AFTER_ADD_LIQUIDITY_OFFSET)
        );
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (getter)");
    }

    function testSetShouldCallAfterAddLiquidity() public {
        PoolConfigBits config;
        config = config.setShouldCallAfterAddLiquidity(true);
        assertEq(config.shouldCallAfterAddLiquidity(), true, "shouldCallAfterAddLiquidity should be true (setter)");
    }

    function testShouldCallBeforeRemoveLiquidity() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallBeforeRemoveLiquidity() public {
        PoolConfigBits config;
        config = config.setShouldCallBeforeRemoveLiquidity(true);
        assertEq(
            config.shouldCallBeforeRemoveLiquidity(),
            true,
            "shouldCallBeforeRemoveLiquidity should be true (setter)"
        );
    }

    function testShouldCallAfterRemoveLiquidity() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET)
        );
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (getter)"
        );
    }

    function testSetShouldCallAfterRemoveLiquidity() public {
        PoolConfigBits config;
        config = config.setShouldCallAfterRemoveLiquidity(true);
        assertEq(
            config.shouldCallAfterRemoveLiquidity(),
            true,
            "shouldCallAfterRemoveLiquidity should be true (setter)"
        );
    }

    function testToHooksConfig() public {
        address hooksContract = address(0x1234567890123456789012345678901234567890);

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

    // #region

    // #region Tests for uint values

    function testGetAggregateSwapFeePercentage() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT24_VALUE,
                PoolConfigLib.AGGREGATE_SWAP_FEE_OFFSET,
                FEE_BITLENGTH
            )
        );

        assertEq(
            config.getAggregateSwapFeePercentage(),
            _MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateSwapFeePercentage mismatch (testGetAggregateSwapFeePercentage)"
        );
    }

    function testSetAggregateSwapFeePercentage() public {
        PoolConfigBits config;
        uint256 value = _MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        config = config.setAggregateSwapFeePercentage(value);
        assertEq(
            config.getAggregateSwapFeePercentage(),
            value,
            "getAggregateSwapFeePercentage mismatch (testSetAggregateSwapFeePercentage)"
        );
    }

    function testGetAggregateYieldFeePercentage() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT24_VALUE,
                PoolConfigLib.AGGREGATE_YIELD_FEE_OFFSET,
                FEE_BITLENGTH
            )
        );

        assertEq(
            config.getAggregateYieldFeePercentage(),
            _MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateYieldFeePercentage mismatch (testGetAggregateYieldFeePercentage)"
        );
    }

    function testSetAggregateYieldFeePercentage() public {
        PoolConfigBits config;
        uint256 value = _MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        config = config.setAggregateYieldFeePercentage(value);
        assertEq(
            config.getAggregateYieldFeePercentage(),
            value,
            "getAggregateYieldFeePercentage mismatch (testSetAggregateYieldFeePercentage)"
        );
    }

    function testGetTokenDecimalDiffs() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT24_VALUE,
                PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
                _TOKEN_DECIMAL_DIFFS_BITLENGTH
            )
        );
        assertEq(
            config.getTokenDecimalDiffs(),
            _MAX_UINT24_VALUE,
            "tokenDecimalDiffs mismatch (testGetTokenDecimalDiffs)"
        );
    }

    function testSetTokenDecimalDiffs() public {
        PoolConfigBits config;
        uint24 value = uint24(_MAX_UINT24_VALUE);
        config = config.setTokenDecimalDiffs(value);
        assertEq(config.getTokenDecimalDiffs(), value, "tokenDecimalDiffs mismatch (testSetTokenDecimalDiffs)");
    }

    function testGetDecimalScalingFactors() public {
        PoolConfigBits config;
        uint256 valueOne = 5;
        uint256 valueTwo = 20;

        bytes32 value = bytes32(0);
        value = value.insertUint(valueOne, 0, _DECIMAL_DIFF_BITLENGTH).insertUint(
            valueTwo,
            _DECIMAL_DIFF_BITLENGTH,
            _DECIMAL_DIFF_BITLENGTH
        );

        config = config.setTokenDecimalDiffs(uint24(uint256(value)));

        uint256[] memory scalingFactors = config.getDecimalScalingFactors(2);

        assertEq(scalingFactors[0], 1e23, "scalingFactors[0] mismatch");
        assertEq(scalingFactors[1], 1e38, "scalingFactors[1] mismatch");
    }

    function testGetPauseWindowEndTime() public {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT32_VALUE,
                PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
                _TIMESTAMP_BITLENGTH
            )
        );
        assertEq(
            config.getPauseWindowEndTime(),
            _MAX_UINT32_VALUE,
            "pauseWindowEndTime mismatch (testGetPauseWindowEndTime)"
        );
    }

    function testSetPauseWindowEndTime() public {
        PoolConfigBits config;
        uint32 value = uint32(_MAX_UINT32_VALUE);
        config = config.setPauseWindowEndTime(value);
        assertEq(config.getPauseWindowEndTime(), value, "pauseWindowEndTime mismatch (testSetPauseWindowEndTime)");
    }

    // #endregion

    function testToTokenDecimalDiffs() public {
        uint8[] memory tokenDecimalDiffs = new uint8[](2);
        tokenDecimalDiffs[0] = 1;
        tokenDecimalDiffs[1] = 2;

        uint256 value = uint256(
            bytes32(0).insertUint(tokenDecimalDiffs[0], 0, _DECIMAL_DIFF_BITLENGTH).insertUint(
                tokenDecimalDiffs[1],
                _DECIMAL_DIFF_BITLENGTH,
                _DECIMAL_DIFF_BITLENGTH
            )
        );

        assertEq(
            PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs),
            value,
            "tokenDecimalDiffs mismatch (testToTokenDecimalDiffs)"
        );
    }

    // #endregion
}
