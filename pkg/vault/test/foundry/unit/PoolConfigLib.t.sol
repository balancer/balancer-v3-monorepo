// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

contract PoolConfigLibTest is BaseBitsConfigTest {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    uint24 private constant MAX_UINT24_VALUE = type(uint24).max;
    uint32 private constant MAX_UINT32_VALUE = type(uint32).max;

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
        _checkBitsUsedOnce(PoolConfigLib.AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET, TOKEN_DECIMAL_DIFFS_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH);
    }

    function testZeroConfigBytes() public pure {
        PoolConfigBits configBits;

        assertFalse(configBits.isPoolRegistered(), "isPoolRegistered should be false");
        assertFalse(configBits.isPoolInitialized(), "isPoolInitialized should be false");
        assertFalse(configBits.isPoolPaused(), "isPoolPaused should be false");
        assertFalse(configBits.isPoolInRecoveryMode(), "isPoolInRecoveryMode should be false");
        assertTrue(configBits.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity should be true");
        assertFalse(configBits.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom should be false");
        assertFalse(configBits.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom should be false");
        assertEq(configBits.getStaticSwapFeePercentage(), 0, "staticSwapFeePercentage isn't zero");
        assertEq(configBits.getAggregateSwapFeePercentage(), 0, "aggregateSwapFeePercentage isn't zero");
        assertEq(configBits.getAggregateYieldFeePercentage(), 0, "aggregateYieldFeePercentage isn't zero");
        assertEq(configBits.getTokenDecimalDiffs(), 0, "tokenDecimalDiffs isn't zero");
        assertEq(configBits.getPauseWindowEndTime(), 0, "pauseWindowEndTime isn't zero");
    }

    function testIsPoolRegistered() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET)
        );
        assertTrue(config.isPoolRegistered(), "isPoolRegistered is false (getter)");
    }

    function testSetPoolRegistered() public pure {
        PoolConfigBits config;
        config = config.setPoolRegistered(true);
        assertTrue(config.isPoolRegistered(), "isPoolRegistered is false (setter)");
    }

    function testIsPoolInitialized() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET)
        );
        assertTrue(config.isPoolInitialized(), "isPoolInitialized is false (getter)");
    }

    function testSetPoolInitialized() public pure {
        PoolConfigBits config;
        config = config.setPoolInitialized(true);
        assertTrue(config.isPoolInitialized(), "isPoolInitialized is false (setter)");
    }

    function testIsPoolPaused() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET));
        assertTrue(config.isPoolPaused(), "isPoolPaused is false (getter)");
    }

    function testSetPoolPaused() public pure {
        PoolConfigBits config;
        config = config.setPoolPaused(true);
        assertTrue(config.isPoolPaused(), "isPoolPaused is false (setter)");
    }

    function testIsPoolInRecoveryMode() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET)
        );
        assertTrue(config.isPoolInRecoveryMode(), "isPoolInRecoveryMode is false (getter)");
    }

    function testSetPoolInRecoveryMode() public pure {
        PoolConfigBits config;
        config = config.setPoolInRecoveryMode(true);
        assertTrue(config.isPoolInRecoveryMode(), "isPoolInRecoveryMode is false (setter)");
    }

    // #endregion

    // #region Tests for liquidity operations
    function testSupportsUnbalancedLiquidity() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET)
        );
        // NOTE: assertFalse because the sense of supportsUnbalancedLiquidity is reversed
        assertFalse(config.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is true (getter)");
    }

    function testSetDisableUnbalancedLiquidity() public pure {
        PoolConfigBits config;
        config = config.setDisableUnbalancedLiquidity(true);
        // NOTE: assertFalse because the sense of supportsUnbalancedLiquidity is reversed
        assertFalse(config.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is true (setter)");
    }

    function testRequireUnbalancedLiquidityEnabled() public pure {
        PoolConfigBits config;

        // It's enabled by default
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireUnbalancedLiquidityRevertWhenIsDisabled() public {
        PoolConfigBits config;
        config = config.setDisableUnbalancedLiquidity(true);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        config.requireUnbalancedLiquidityEnabled();
    }

    function testSupportsAddLiquidityCustom() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET)
        );
        assertTrue(config.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is false (getter)");
    }

    function testSetAddLiquidityCustom() public pure {
        PoolConfigBits config;
        config = config.setAddLiquidityCustom(true);
        assertTrue(config.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is false (setter)");
    }

    function testRequireAddCustomLiquidityEnabled() public pure {
        PoolConfigBits config;
        config = config.setAddLiquidityCustom(true);

        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityRevertWhenIsDisabled() public {
        PoolConfigBits config;

        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        config.requireAddCustomLiquidityEnabled();
    }

    function testSupportsRemoveLiquidityCustom() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET)
        );
        assertTrue(config.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is false (getter)");
    }

    function testSetRemoveLiquidityCustom() public pure {
        PoolConfigBits config;
        config = config.setRemoveLiquidityCustom(true);
        assertTrue(config.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is false (setter)");
    }

    function testRequireRemoveCustomLiquidityEnabled() public pure {
        PoolConfigBits config;
        config = config.setRemoveLiquidityCustom(true);

        config.requireRemoveCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityRecoveryWhenDisabled() public {
        PoolConfigBits config;

        vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
        config.requireRemoveCustomLiquidityEnabled();
    }

    // #endregion

    // #region Tests for uint values
    function testGetAggregateSwapFeePercentage() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                MAX_UINT24_VALUE,
                PoolConfigLib.AGGREGATE_SWAP_FEE_OFFSET,
                FEE_BITLENGTH
            )
        );

        assertEq(
            config.getAggregateSwapFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateSwapFeePercentage mismatch (testGetAggregateSwapFeePercentage)"
        );
    }

    function testSetAggregateSwapFeePercentage() public pure {
        PoolConfigBits config;
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        config = config.setAggregateSwapFeePercentage(value);
        assertEq(
            config.getAggregateSwapFeePercentage(),
            value,
            "getAggregateSwapFeePercentage mismatch (testSetAggregateSwapFeePercentage)"
        );
    }

    function testGetAggregateYieldFeePercentage() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                MAX_UINT24_VALUE,
                PoolConfigLib.AGGREGATE_YIELD_FEE_OFFSET,
                FEE_BITLENGTH
            )
        );

        assertEq(
            config.getAggregateYieldFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateYieldFeePercentage mismatch (testGetAggregateYieldFeePercentage)"
        );
    }

    function testSetAggregateYieldFeePercentage() public pure {
        PoolConfigBits config;
        uint256 value = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        config = config.setAggregateYieldFeePercentage(value);
        assertEq(
            config.getAggregateYieldFeePercentage(),
            value,
            "getAggregateYieldFeePercentage mismatch (testSetAggregateYieldFeePercentage)"
        );
    }

    function testGetTokenDecimalDiffs() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                MAX_UINT24_VALUE,
                PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
                TOKEN_DECIMAL_DIFFS_BITLENGTH
            )
        );
        assertEq(
            config.getTokenDecimalDiffs(),
            MAX_UINT24_VALUE,
            "tokenDecimalDiffs mismatch (testGetTokenDecimalDiffs)"
        );
    }

    function testSetTokenDecimalDiffs() public pure {
        PoolConfigBits config;
        uint24 value = uint24(MAX_UINT24_VALUE);
        config = config.setTokenDecimalDiffs(value);
        assertEq(config.getTokenDecimalDiffs(), value, "tokenDecimalDiffs mismatch (testSetTokenDecimalDiffs)");
    }

    function testGetDecimalScalingFactors() public pure {
        PoolConfigBits config;
        uint256 valueOne = 5;
        uint256 valueTwo = 20;

        bytes32 value = bytes32(0);
        value = value.insertUint(valueOne, 0, DECIMAL_DIFF_BITLENGTH).insertUint(
            valueTwo,
            DECIMAL_DIFF_BITLENGTH,
            DECIMAL_DIFF_BITLENGTH
        );

        config = config.setTokenDecimalDiffs(uint24(uint256(value)));

        uint256[] memory scalingFactors = config.getDecimalScalingFactors(2);

        assertEq(scalingFactors[0], 1e23, "scalingFactors[0] mismatch");
        assertEq(scalingFactors[1], 1e38, "scalingFactors[1] mismatch");
    }

    function testGetPauseWindowEndTime() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                MAX_UINT32_VALUE,
                PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
                TIMESTAMP_BITLENGTH
            )
        );
        assertEq(
            config.getPauseWindowEndTime(),
            MAX_UINT32_VALUE,
            "pauseWindowEndTime mismatch (testGetPauseWindowEndTime)"
        );
    }

    function testSetPauseWindowEndTime() public pure {
        PoolConfigBits config;
        uint32 value = uint32(MAX_UINT32_VALUE);
        config = config.setPauseWindowEndTime(value);
        assertEq(config.getPauseWindowEndTime(), value, "pauseWindowEndTime mismatch (testSetPauseWindowEndTime)");
    }

    // #endregion

    function testToTokenDecimalDiffs() public pure {
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
}
