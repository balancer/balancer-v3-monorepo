// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;
import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {
    PoolConfigBits,
    FEE_BITLENGTH,
    MAX_FEE_PERCENTAGE,
    FEE_SCALING_FACTOR
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigConst } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigConst.sol";
import { PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

contract PoolConfigLibTest is Test {
    using WordCodec for bytes32;
    using PoolConfigLib for PoolConfigBits;

    uint256 private constant _MAX_UINT32_VALUE = type(uint32).max;
    uint256 private constant _MAX_UINT24_VALUE = type(uint24).max;
    uint256 private constant _MAX_UINT40_VALUE = type(uint40).max;
    uint256 private constant _ARBITRARY_FEE_PCT = 3.14e16;

    function testZeroConfigBytes() public pure {
        PoolConfigBits config;

        assertEq(config.isPoolRegistered(), false, "isPoolRegistered mismatch (zero config)");
        assertEq(config.isPoolInitialized(), false, "isPoolInitialized mismatch (zero config)");
        assertEq(config.isPoolPaused(), false, "isPoolPaused mismatch (zero config)");
        assertEq(config.isPoolInRecoveryMode(), false, "isPoolInRecoveryMode mismatch (zero config)");
        assertEq(config.supportsUnbalancedLiquidity(), true, "supportsUnbalancedLiquidity mismatch (zero config)");
        assertEq(config.supportsAddLiquidityCustom(), false, "supportsAddLiquidityCustom mismatch (zero config)");
        assertEq(config.supportsRemoveLiquidityCustom(), false, "supportsRemoveLiquidityCustom mismatch (zero config)");
        assertEq(config.getStaticSwapFeePercentage(), 0, "getStaticSwapFeePercentage mismatch (zero config)");
        assertEq(config.getAggregateSwapFeePercentage(), 0, "getAggregateSwapFeePercentage mismatch (zero config)");
        assertEq(config.getAggregateYieldFeePercentage(), 0, "getAggregateYieldFeePercentage mismatch (zero config)");
        assertEq(config.getTokenDecimalDiffs(), 0, "getTokenDecimalDiffs mismatch (zero config)");
        assertEq(config.getPauseWindowEndTime(), 0, "getPauseWindowEndTime mismatch (zero config)");
    }

    // #region Tests for main pool config settings

    function testIsPoolRegistered() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.POOL_REGISTERED_OFFSET)
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
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.POOL_INITIALIZED_OFFSET)
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
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.POOL_PAUSED_OFFSET)
        );
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
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.POOL_RECOVERY_MODE_OFFSET)
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
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.UNBALANCED_LIQUIDITY_OFFSET)
        );
        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertFalse(config.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is true (getter)");
    }

    function testSetDisableUnbalancedLiquidity() public pure {
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

    function testSupportsAddLiquidityCustom() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.ADD_LIQUIDITY_CUSTOM_OFFSET)
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

    function testRequireAddCustomLiquidityRevertIfIsDisabled() public {
        PoolConfigBits config;

        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        config.requireAddCustomLiquidityEnabled();
    }

    function testSupportsRemoveLiquidityCustom() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertBool(true, PoolConfigConst.REMOVE_LIQUIDITY_CUSTOM_OFFSET)
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

    function testRequireRemoveCustomLiquidityReveryIfIsDisabled() public {
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
                _MAX_UINT24_VALUE,
                PoolConfigConst.AGGREGATE_SWAP_FEE_OFFSET,
                FEE_BITLENGTH
            )
        );

        assertEq(
            config.getAggregateSwapFeePercentage(),
            _MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateSwapFeePercentage mismatch (testGetAggregateSwapFeePercentage)"
        );
    }

    function testSetAggregateSwapFeePercentage() public pure {
        PoolConfigBits config;
        config = config.setAggregateSwapFeePercentage(_ARBITRARY_FEE_PCT);
        assertEq(
            config.getAggregateSwapFeePercentage(),
            _ARBITRARY_FEE_PCT,
            "getAggregateSwapFeePercentage mismatch (testSetAggregateSwapFeePercentage)"
        );
    }

    function testSetAggregateSwapFeePercentageAboveMax() public {
        PoolConfigBits config;
        vm.expectRevert(abi.encodeWithSelector(PoolConfigLib.InvalidPercentage.selector, MAX_FEE_PERCENTAGE + 1));
        config.setAggregateSwapFeePercentage(MAX_FEE_PERCENTAGE + 1);
    }

    function testGetAggregateYieldFeePercentage() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT24_VALUE,
                PoolConfigConst.AGGREGATE_YIELD_FEE_OFFSET,
                FEE_BITLENGTH
            )
        );

        assertEq(
            config.getAggregateYieldFeePercentage(),
            _MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getAggregateYieldFeePercentage mismatch (testGetAggregateYieldFeePercentage)"
        );
    }

    function testSetAggregateYieldFeePercentage() public pure {
        PoolConfigBits config;
        config = config.setAggregateYieldFeePercentage(_ARBITRARY_FEE_PCT);
        assertEq(
            config.getAggregateYieldFeePercentage(),
            _ARBITRARY_FEE_PCT,
            "getAggregateYieldFeePercentage mismatch (testSetAggregateYieldFeePercentage)"
        );
    }

    function testSetAggregateYieldFeePercentageAboveMax() public {
        PoolConfigBits config;
        vm.expectRevert(abi.encodeWithSelector(PoolConfigLib.InvalidPercentage.selector, MAX_FEE_PERCENTAGE + 1));
        config.setAggregateYieldFeePercentage(MAX_FEE_PERCENTAGE + 1);
    }

    function testGetStaticSwapFeePercentage() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT24_VALUE,
                PoolConfigConst.STATIC_SWAP_FEE_OFFSET,
                FEE_BITLENGTH
            )
        );

        assertEq(
            config.getStaticSwapFeePercentage(),
            _MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "getStaticSwapFeePercentage mismatch (testGetStaticSwapFeePercentage)"
        );
    }

    function testSetStaticSwapFeePercentage() public pure {
        PoolConfigBits config;
        config = config.setStaticSwapFeePercentage(_ARBITRARY_FEE_PCT);
        assertEq(
            config.getStaticSwapFeePercentage(),
            _ARBITRARY_FEE_PCT,
            "getStaticSwapFeePercentage mismatch (testSetStaticSwapFeePercentage)"
        );
    }

    function testSetStaticSwapFeePercentageAboveMax() public {
        PoolConfigBits config;
        vm.expectRevert(abi.encodeWithSelector(PoolConfigLib.InvalidPercentage.selector, MAX_FEE_PERCENTAGE + 1));
        config.setStaticSwapFeePercentage(MAX_FEE_PERCENTAGE + 1);
    }

    function testGetTokenDecimalDiffs() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT40_VALUE,
                PoolConfigConst.DECIMAL_SCALING_FACTORS_OFFSET,
                PoolConfigConst.TOKEN_DECIMAL_DIFFS_BITLENGTH
            )
        );
        assertEq(
            config.getTokenDecimalDiffs(),
            _MAX_UINT40_VALUE,
            "tokenDecimalDiffs mismatch (testGetTokenDecimalDiffs)"
        );
    }

    function testSetTokenDecimalDiffs() public pure {
        PoolConfigBits config;
        uint40 value = uint40(_MAX_UINT40_VALUE);
        config = config.setTokenDecimalDiffs(value);
        assertEq(config.getTokenDecimalDiffs(), value, "tokenDecimalDiffs mismatch (testSetTokenDecimalDiffs)");
    }

    function testGetDecimalScalingFactors() public pure {
        PoolConfigBits config;
        uint256 valueOne = 5;
        uint256 valueTwo = 20;

        bytes32 value = bytes32(0);
        value = value.insertUint(valueOne, 0, PoolConfigConst.DECIMAL_DIFF_BITLENGTH).insertUint(
            valueTwo,
            PoolConfigConst.DECIMAL_DIFF_BITLENGTH,
            PoolConfigConst.DECIMAL_DIFF_BITLENGTH
        );

        config = config.setTokenDecimalDiffs(uint40(uint256(value)));

        uint256[] memory scalingFactors = config.getDecimalScalingFactors(2);

        assertEq(scalingFactors[0], 1e23, "scalingFactors[0] mismatch");
        assertEq(scalingFactors[1], 1e38, "scalingFactors[1] mismatch");
    }

    function testGetPauseWindowEndTime() public pure {
        PoolConfigBits config;
        config = PoolConfigBits.wrap(
            PoolConfigBits.unwrap(config).insertUint(
                _MAX_UINT32_VALUE,
                PoolConfigConst.PAUSE_WINDOW_END_TIME_OFFSET,
                PoolConfigConst.TIMESTAMP_BITLENGTH
            )
        );
        assertEq(
            config.getPauseWindowEndTime(),
            _MAX_UINT32_VALUE,
            "pauseWindowEndTime mismatch (testGetPauseWindowEndTime)"
        );
    }

    function testSetPauseWindowEndTime() public pure {
        PoolConfigBits config;
        uint32 value = uint32(_MAX_UINT32_VALUE);
        config = config.setPauseWindowEndTime(value);
        assertEq(config.getPauseWindowEndTime(), value, "pauseWindowEndTime mismatch (testSetPauseWindowEndTime)");
    }

    // #endregion

    function testToTokenDecimalDiffs() public pure {
        uint8[] memory tokenDecimalDiffs = new uint8[](2);
        tokenDecimalDiffs[0] = 1;
        tokenDecimalDiffs[1] = 2;

        uint256 value = uint256(
            bytes32(0).insertUint(tokenDecimalDiffs[0], 0, PoolConfigConst.DECIMAL_DIFF_BITLENGTH).insertUint(
                tokenDecimalDiffs[1],
                PoolConfigConst.DECIMAL_DIFF_BITLENGTH,
                PoolConfigConst.DECIMAL_DIFF_BITLENGTH
            )
        );

        assertEq(
            PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs),
            value,
            "tokenDecimalDiffs mismatch (testToTokenDecimalDiffs)"
        );
    }
}
