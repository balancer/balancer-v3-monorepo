// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

contract PoolConfigLibTest is BaseBitsConfigTest {
    using PoolConfigLib for PoolConfig;
    using PoolConfigLib for PoolConfigBits;
    using WordCodec for bytes32;

    uint256 private constant MAX_UINT24_VALUE = uint256(type(uint24).max);
    uint256 private constant MAX_UINT32_VALUE = uint256(type(uint32).max);
    uint256 constant TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 constant DECIMAL_DIFF_BITLENGTH = 5;
    uint256 constant TIMESTAMP_BITLENGTH = 32;

    function testOffsets() public {
        _checkBitsUsedOnce(PoolConfigLib.POOL_REGISTERED_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.POOL_INITIALIZED_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.POOL_PAUSED_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.POOL_RECOVERY_MODE_OFFSET);

        _checkBitsUsedOnce(PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET);
        _checkBitsUsedOnce(PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET);

        _checkBitsUsedOnce(PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET, TOKEN_DECIMAL_DIFFS_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH);
    }

    function testZeroConfigBytes() public {
        PoolConfigBits memory configBits;

        assertFalse(configBits.isPoolRegistered(), "isPoolRegistered should be false");
        assertFalse(configBits.isPoolInitialized(), "isPoolInitialized should be false");
        assertFalse(configBits.isPoolPaused(), "isPoolPaused should be false");
        assertFalse(configBits.isPoolInRecoveryMode(), "isPoolInRecoveryMode should be false");

        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertTrue(configBits.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity should be true");

        assertFalse(configBits.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom should be false");
        assertFalse(configBits.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom should be false");
        assertEq(configBits.getStaticSwapFeePercentage(), 0, "staticSwapFeePercentage isn't zero");
        assertEq(
            configBits.getAggregateProtocolSwapFeePercentage(),
            0,
            "aggregateProtocolSwapFeePercentage isn't zero"
        );
        assertEq(
            configBits.getAggregateProtocolYieldFeePercentage(),
            0,
            "aggregateProtocolYieldFeePercentage isn't zero"
        );
        assertEq(configBits.getTokenDecimalDiffs(), 0, "tokenDecimalDiffs isn't zero");
        assertEq(configBits.getPauseWindowEndTime(), 0, "pauseWindowEndTime isn't zero");
    }

    function testToTokenDecimalDiffs() public {
        uint8[] memory tokenDecimalDiffs = new uint8[](2);
        tokenDecimalDiffs[0] = 1;
        tokenDecimalDiffs[1] = 2;

        uint256 value = uint256(
            bytes32(0).insertUint(tokenDecimalDiffs[0], 0, DECIMAL_DIFF_BITLENGTH).insertUint(
                tokenDecimalDiffs[1],
                DECIMAL_DIFF_BITLENGTH,
                DECIMAL_DIFF_BITLENGTH
            )
        );

        assertEq(
            PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs),
            value,
            "tokenDecimalDiffs mismatch (testToTokenDecimalDiffs)"
        );
    }

    function testGetDecimalScalingFactors() public {
        PoolConfigBits memory config;
        uint256 valueOne = 5;
        uint256 valueTwo = 20;

        bytes32 value = bytes32(0);
        value = value.insertUint(valueOne, 0, DECIMAL_DIFF_BITLENGTH).insertUint(
            valueTwo,
            DECIMAL_DIFF_BITLENGTH,
            DECIMAL_DIFF_BITLENGTH
        );

        config.setTokenDecimalDiffs(uint256(value));

        uint256[] memory scalingFactors = config.getDecimalScalingFactors(2);

        assertEq(scalingFactors[0], 1e23, "scalingFactors[0] mismatch");
        assertEq(scalingFactors[1], 1e38, "scalingFactors[1] mismatch");
    }

    // #region tests for getters and setters
    function testIsPoolRegistered() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET);
        assertTrue(configBits.isPoolRegistered(), "isPoolRegistered is false");
    }

    function testSetPoolRegistered() public {
        PoolConfigBits memory configBits;
        configBits.setPoolRegistered(true);
        assertTrue(configBits.isPoolRegistered(), "isPoolRegistered is false");
    }

    function testIsPoolInitialized() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET);
        assertTrue(configBits.isPoolInitialized(), "isPoolInitialized is false");
    }

    function testSetPoolInitialized() public {
        PoolConfigBits memory configBits;
        configBits.setPoolInitialized(true);
        assertTrue(configBits.isPoolInitialized(), "isPoolInitialized is false");
    }

    function testIsPoolInRecoveryMode() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET);
        assertTrue(configBits.isPoolInRecoveryMode(), "isPoolInRecoveryMode is false");
    }

    function testSetPoolInRecoveryMode() public {
        PoolConfigBits memory configBits;
        configBits.setPoolInRecoveryMode(true);
        assertTrue(configBits.isPoolInRecoveryMode(), "isPoolInRecoveryMode is false");
    }

    function testIsPoolPaused() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET);
        assertTrue(configBits.isPoolPaused(), "isPoolPaused is false");
    }

    function testSetPoolPaused() public {
        PoolConfigBits memory configBits;
        configBits.setPoolPaused(true);
        assertTrue(configBits.isPoolPaused(), "isPoolPaused is false");
    }

    function testGetStaticSwapFeePercentage() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertUint(
            MAX_UINT24_VALUE,
            PoolConfigLib.STATIC_SWAP_FEE_OFFSET,
            FEE_BITLENGTH
        );
        assertEq(
            configBits.getStaticSwapFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "staticSwapFeePercentage mismatch (testGetStaticSwapFeePercentage)"
        );
    }

    function testSetStaticSwapFeePercentage() public {
        PoolConfigBits memory configBits;
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        configBits.setStaticSwapFeePercentage(value);
        assertEq(
            configBits.getStaticSwapFeePercentage(),
            value,
            "staticSwapFeePercentage mismatch (testSetStaticSwapFeePercentage)"
        );
    }

    function testGetAggregateProtocolSwapFeePercentage() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertUint(
            MAX_UINT24_VALUE,
            PoolConfigLib.AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
            FEE_BITLENGTH
        );
        assertEq(
            configBits.getAggregateProtocolSwapFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateProtocolSwapFeePercentage mismatch (testGetAggregateProtocolSwapFeePercentage)"
        );
    }

    function testSetAggregateProtocolSwapFeePercentage() public {
        PoolConfigBits memory configBits;
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        configBits.setAggregateProtocolSwapFeePercentage(value);
        assertEq(
            configBits.getAggregateProtocolSwapFeePercentage(),
            value,
            "getAggregateProtocolSwapFeePercentage mismatch (testSetAggregateProtocolSwapFeePercentage)"
        );
    }

    function testGetAggregateProtocolYieldFeePercentage() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertUint(
            MAX_UINT24_VALUE,
            PoolConfigLib.AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
            FEE_BITLENGTH
        );
        assertEq(
            configBits.getAggregateProtocolYieldFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateProtocolYieldFeePercentage mismatch (testGetAggregateProtocolYieldFeePercentage)"
        );
    }

    function testSetAggregateProtocolYieldFeePercentage() public {
        PoolConfigBits memory configBits;
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        configBits.setAggregateProtocolYieldFeePercentage(value);
        assertEq(
            configBits.getAggregateProtocolYieldFeePercentage(),
            value,
            "getAggregateProtocolYieldFeePercentage mismatch (testSetAggregateProtocolYieldFeePercentage)"
        );
    }

    function testGetTokenDecimalDiffs() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertUint(
            MAX_UINT24_VALUE,
            PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
            TOKEN_DECIMAL_DIFFS_BITLENGTH
        );
        assertEq(
            configBits.getTokenDecimalDiffs(),
            MAX_UINT24_VALUE,
            "tokenDecimalDiffs mismatch (testGetTokenDecimalDiffs)"
        );
    }

    function testSetTokenDecimalDiffs() public {
        PoolConfigBits memory configBits;
        uint256 value = MAX_UINT24_VALUE;
        configBits.setTokenDecimalDiffs(value);
        assertEq(configBits.getTokenDecimalDiffs(), value, "tokenDecimalDiffs mismatch (testSetTokenDecimalDiffs)");
    }

    function testGetPauseWindowEndTime() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertUint(
            MAX_UINT32_VALUE,
            PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
            TIMESTAMP_BITLENGTH
        );
        assertEq(
            configBits.getPauseWindowEndTime(),
            MAX_UINT32_VALUE,
            "pauseWindowEndTime mismatch (testGetPauseWindowEndTime)"
        );
    }

    function testSetPauseWindowEndTime() public {
        PoolConfigBits memory configBits;
        uint256 value = MAX_UINT32_VALUE;
        configBits.setPauseWindowEndTime(value);
        assertEq(configBits.getPauseWindowEndTime(), value, "pauseWindowEndTime mismatch (testSetPauseWindowEndTime)");
    }

    function testSupportsUnbalancedLiquidity() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET);
        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertFalse(configBits.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is true");
    }

    function testSetDisableUnbalancedLiquidity() public {
        PoolConfigBits memory configBits;
        configBits.setDisableUnbalancedLiquidity(true);
        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertFalse(configBits.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is true");
    }

    function testSupportsAddLiquidityCustom() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET);
        assertTrue(configBits.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is false");
    }

    function testSetAddLiquidityCustom() public {
        PoolConfigBits memory configBits;
        configBits.setAddLiquidityCustom(true);
        assertTrue(configBits.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is false");
    }

    function testSupportsRemoveLiquidityCustom() public {
        PoolConfigBits memory configBits;
        configBits.bits = configBits.bits.insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        assertTrue(configBits.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is false");
    }

    function testSetRemoveLiquidityCustom() public {
        PoolConfigBits memory configBits;
        configBits.setRemoveLiquidityCustom(true);
        assertTrue(configBits.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is false");
    }

    // #endregion

    // #region tests for require functions
    function testRequireUnbalancedLiquidityEnabled() public pure {
        PoolConfigBits memory config;

        // It's enabled by default
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireUnbalancedLiquidityEnabledIfIsDisabled() public {
        PoolConfigBits memory config;
        config.setDisableUnbalancedLiquidity(true);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityEnabled() public pure {
        PoolConfigBits memory config;
        config.setAddLiquidityCustom(true);

        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityEnabledIfIsDisabled() public {
        PoolConfigBits memory config;

        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityEnabled() public pure {
        PoolConfigBits memory config;
        config.setRemoveLiquidityCustom(true);

        config.requireRemoveCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityEnabledIfIsDisabled() public {
        PoolConfigBits memory config;

        vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
        config.requireRemoveCustomLiquidityEnabled();
    }
    // #endregion
}
