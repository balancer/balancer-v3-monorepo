// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import { PoolConfig, PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import {
    FEE_SCALING_FACTOR,
    FEE_BITLENGTH,
    PoolHooks,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

contract PoolConfigLibTest is Test {
    using PoolConfigLib for PoolConfig;
    using PoolConfigLib for PoolConfigBits;
    using WordCodec for bytes32;

    uint256 private constant MAX_UINT24_VALUE = uint256(type(uint24).max);
    uint256 private constant MAX_UINT32_VALUE = uint256(type(uint32).max);
    uint256 constant TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint8 constant DECIMAL_DIFF_BITLENGTH = 5;
    uint256 constant TIMESTAMP_BITLENGTH = 32;

    mapping(uint256 => bool) usedBits;

    // 16 flags + 24 bit fee + 24 bit token diffs + 32 bit timestamp = 96 total bits used.
    uint256 private constant CONFIG_MSB = 96;

    // #region PoolConfigBits
    function testOffsets() public {
        _checkBit(PoolConfigLib.POOL_REGISTERED_OFFSET);
        _checkBit(PoolConfigLib.POOL_INITIALIZED_OFFSET);
        _checkBit(PoolConfigLib.POOL_PAUSED_OFFSET);
        _checkBit(PoolConfigLib.DYNAMIC_SWAP_FEE_OFFSET);
        _checkBit(PoolConfigLib.BEFORE_SWAP_OFFSET);
        _checkBit(PoolConfigLib.AFTER_SWAP_OFFSET);
        _checkBit(PoolConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET);
        _checkBit(PoolConfigLib.AFTER_ADD_LIQUIDITY_OFFSET);
        _checkBit(PoolConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET);
        _checkBit(PoolConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET);
        _checkBit(PoolConfigLib.BEFORE_INITIALIZE_OFFSET);
        _checkBit(PoolConfigLib.AFTER_INITIALIZE_OFFSET);
        _checkBit(PoolConfigLib.POOL_RECOVERY_MODE_OFFSET);
        _checkBit(PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET);
        _checkBit(PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET);
        _checkBit(PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET);

        _checkBits(PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBits(PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET, TOKEN_DECIMAL_DIFFS_BITLENGTH);
        _checkBits(PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH);
    }

    function testIsPoolRegistered() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET)).isPoolRegistered(),
            "isPoolRegistered is false"
        );
    }

    function testIsPoolInitialized() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET)).isPoolInitialized(),
            "isPoolInitialized is false"
        );
    }

    function testIsPoolPaused() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET)).isPoolPaused(),
            "isPoolPaused is false"
        );
    }

    function testHasDynamicSwapFee() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.DYNAMIC_SWAP_FEE_OFFSET)).hasDynamicSwapFee(),
            "hasDynamicSwapFee is false"
        );
    }

    function testShouldCallBeforeSwap() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_SWAP_OFFSET)).shouldCallBeforeSwap(),
            "shouldCallBeforeSwap is false"
        );
    }

    function testShouldCallAfterSwap() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_SWAP_OFFSET)).shouldCallAfterSwap(),
            "shouldCallAfterSwap is false"
        );
    }

    function testShouldCallBeforeAddLiquidity() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET))
                .shouldCallBeforeAddLiquidity(),
            "shouldCallBeforeAddLiquidity is false"
        );
    }

    function testShouldCallAfterAddLiquidity() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_ADD_LIQUIDITY_OFFSET))
                .shouldCallAfterAddLiquidity(),
            "shouldCallAfterAddLiquidity is false"
        );
    }

    function testShouldCallBeforeRemoveLiquidity() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET))
                .shouldCallBeforeRemoveLiquidity(),
            "shouldCallBeforeRemoveLiquidity is false"
        );
    }

    function testShouldCallAfterRemoveLiquidity() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET))
                .shouldCallAfterRemoveLiquidity(),
            "shouldCallAfterRemoveLiquidity is false"
        );
    }

    function testShouldCallBeforeInitialize() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_INITIALIZE_OFFSET))
                .shouldCallBeforeInitialize(),
            "shouldCallBeforeInitialize is false"
        );
    }

    function testShouldCallAfterInitialize() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_INITIALIZE_OFFSET))
                .shouldCallAfterInitialize(),
            "shouldCallAfterInitialize is false"
        );
    }

    function testIsPoolInRecoveryMode() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET))
                .isPoolInRecoveryMode(),
            "isPoolInRecoveryMode is false"
        );
    }

    function testSupportsUnbalancedLiquidity() public {
        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertFalse(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET))
                .supportsUnbalancedLiquidity(),
            "supportsUnbalancedLiquidity is true"
        );
    }

    function testSupportsAddLiquidityCustom() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET))
                .supportsAddLiquidityCustom(),
            "supportsAddLiquidityCustom is false"
        );
    }

    function testSupportsRemoveLiquidityCustom() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET))
                .supportsRemoveLiquidityCustom(),
            "supportsRemoveLiquidityCustom is false"
        );
    }

    function testGetStaticSwapFeePercentage() public {
        assertEq(
            PoolConfigBits
                .wrap(bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH))
                .getStaticSwapFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "staticSwapFeePercentage mismatch"
        );
    }

    function testGetTokenDecimalDiffs() public {
        assertEq(
            PoolConfigBits
                .wrap(
                    bytes32(0).insertUint(
                        MAX_UINT24_VALUE,
                        PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
                        TOKEN_DECIMAL_DIFFS_BITLENGTH
                    )
                )
                .getTokenDecimalDiffs(),
            MAX_UINT24_VALUE,
            "tokenDecimalDiffs mismatch"
        );
    }

    function testGetPauseWindowEndTime() public {
        assertEq(
            PoolConfigBits
                .wrap(
                    bytes32(0).insertUint(
                        MAX_UINT32_VALUE,
                        PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
                        TIMESTAMP_BITLENGTH
                    )
                )
                .getPauseWindowEndTime(),
            MAX_UINT32_VALUE,
            "pauseWindowEndTime mismatch"
        );
    }

    function testGetPoolPausedState() public {
        bytes32 configBits = bytes32(0);

        bool isPaused;
        uint256 pauseWithdrawEndTime;

        (isPaused, pauseWithdrawEndTime) = PoolConfigBits.wrap(configBits).getPoolPausedState();
        assertFalse(isPaused, "(empty bytes) isPaused mismatch");

        (isPaused, pauseWithdrawEndTime) = PoolConfigBits
            .wrap(configBits.insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET))
            .getPoolPausedState();
        assertTrue(isPaused, "(isPaused = true && pauseWithdrawEndTime == 0) isPaused mismatch");
        assertEq(
            pauseWithdrawEndTime,
            0,
            "(isPaused = true && pauseWithdrawEndTime == 0) pauseWithdrawEndTime mismatch"
        );

        (isPaused, pauseWithdrawEndTime) = PoolConfigBits
            .wrap(
                configBits.insertUint(MAX_UINT32_VALUE, PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH)
            )
            .getPoolPausedState();
        assertFalse(isPaused, "(isPaused = false && pauseWithdrawEndTime != 0) isPaused mismatch");
        assertEq(
            pauseWithdrawEndTime,
            MAX_UINT32_VALUE,
            "(isPaused = false && pauseWithdrawEndTime != 0) pauseWithdrawEndTime mismatch"
        );

        (isPaused, pauseWithdrawEndTime) = PoolConfigBits
            .wrap(
                configBits.insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET).insertUint(
                    MAX_UINT32_VALUE,
                    PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
                    TIMESTAMP_BITLENGTH
                )
            )
            .getPoolPausedState();
        assertTrue(isPaused, "(isPaused = true && pauseWithdrawEndTime != 0) isPaused mismatch");
        assertEq(
            pauseWithdrawEndTime,
            MAX_UINT32_VALUE,
            "(isPaused = true && pauseWithdrawEndTime != 0) pauseWithdrawEndTime mismatch"
        );
    }

    function testZeroConfigBytes() public {
        PoolConfigBits configBits = PoolConfigBits.wrap(bytes32(0));

        assertFalse(configBits.isPoolRegistered(), "isPoolRegistered is true");
        assertFalse(configBits.isPoolInitialized(), "isPoolInitialized is true");
        assertFalse(configBits.isPoolPaused(), "isPoolPaused is true");
        assertFalse(configBits.hasDynamicSwapFee(), "hasDynamicSwapFee is true");
        assertFalse(configBits.shouldCallBeforeSwap(), "shouldCallBeforeSwap is true");
        assertFalse(configBits.shouldCallAfterSwap(), "shouldCallAfterSwap is true");
        assertFalse(configBits.shouldCallBeforeAddLiquidity(), "shouldCallBeforeAddLiquidity is true");
        assertFalse(configBits.shouldCallAfterAddLiquidity(), "shouldCallAfterAddLiquidity is true");
        assertFalse(configBits.shouldCallBeforeRemoveLiquidity(), "shouldCallBeforeRemoveLiquidity is true");
        assertFalse(configBits.shouldCallAfterRemoveLiquidity(), "shouldCallAfterRemoveLiquidity is true");
        assertFalse(configBits.shouldCallBeforeInitialize(), "shouldCallBeforeInitialize is true");
        assertFalse(configBits.shouldCallAfterInitialize(), "shouldCallAfterInitialize is true");
        assertFalse(configBits.isPoolInRecoveryMode(), "isPoolInRecoveryMode is true");

        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertTrue(configBits.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is false");

        assertFalse(configBits.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is true");
        assertFalse(configBits.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is true");
        assertEq(configBits.getStaticSwapFeePercentage(), 0, "staticSwapFeePercentage isn't zero");
        assertEq(configBits.getTokenDecimalDiffs(), 0, "tokenDecimalDiffs isn't zero");
        assertEq(configBits.getPauseWindowEndTime(), 0, "pauseWindowEndTime isn't zero");
    }

    // #endregion

    // #region PoolConfig
    function testToPoolConfig() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET))
                .toPoolConfig()
                .isPoolRegistered,
            "isPoolRegistered mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET))
                .toPoolConfig()
                .isPoolInitialized,
            "isPoolInitialized mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET))
                .toPoolConfig()
                .isPoolPaused,
            "isPoolPaused mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET))
                .toPoolConfig()
                .isPoolInRecoveryMode,
            "isPoolInRecoveryMode mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.DYNAMIC_SWAP_FEE_OFFSET))
                .toPoolConfig()
                .hasDynamicSwapFee,
            "hasDynamicSwapFee mismatch"
        );

        assertEq(
            PoolConfigBits
                .wrap(bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH))
                .toPoolConfig()
                .staticSwapFeePercentage,
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "staticSwapFeePercentage mismatch"
        );

        assertEq(
            PoolConfigBits
                .wrap(
                    bytes32(0).insertUint(
                        MAX_UINT24_VALUE,
                        PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
                        TOKEN_DECIMAL_DIFFS_BITLENGTH
                    )
                )
                .toPoolConfig()
                .tokenDecimalDiffs,
            MAX_UINT24_VALUE,
            "tokenDecimalDiffs mismatch"
        );

        assertEq(
            PoolConfigBits
                .wrap(
                    bytes32(0).insertUint(
                        MAX_UINT32_VALUE,
                        PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
                        TIMESTAMP_BITLENGTH
                    )
                )
                .toPoolConfig()
                .pauseWindowEndTime,
            MAX_UINT32_VALUE,
            "pauseWindowEndTime mismatch"
        );

        // check .hooks
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_INITIALIZE_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallBeforeInitialize,
            "shouldCallBeforeInitialize mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_INITIALIZE_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallAfterInitialize,
            "shouldCallAfterInitialize mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallBeforeAddLiquidity,
            "shouldCallBeforeAddLiquidity mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_ADD_LIQUIDITY_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallAfterAddLiquidity,
            "shouldCallAfterAddLiquidity mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallBeforeRemoveLiquidity,
            "shouldCallBeforeRemoveLiquidity mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallAfterRemoveLiquidity,
            "shouldCallAfterRemoveLiquidity mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.BEFORE_SWAP_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallBeforeSwap,
            "shouldCallBeforeSwap mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.AFTER_SWAP_OFFSET))
                .toPoolConfig()
                .hooks
                .shouldCallAfterSwap,
            "shouldCallAfterSwap mismatch"
        );

        // check .liquidityManagement
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET))
                .toPoolConfig()
                .liquidityManagement
                .disableUnbalancedLiquidity,
            "disableUnbalancedLiquidity mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET))
                .toPoolConfig()
                .liquidityManagement
                .enableAddLiquidityCustom,
            "enableAddLiquidityCustom mismatch"
        );

        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET))
                .toPoolConfig()
                .liquidityManagement
                .enableRemoveLiquidityCustom,
            "enableRemoveLiquidityCustom mismatch"
        );
    }

    function testFromPoolConfig() public {
        PoolConfig memory config;
        config.isPoolRegistered = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET),
            "isPoolRegistered mismatch"
        );

        config = _createEmptyConfig();
        config.isPoolInitialized = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET),
            "isPoolInitialized mismatch"
        );

        config = _createEmptyConfig();
        config.isPoolPaused = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET),
            "isPoolPaused mismatch"
        );

        config = _createEmptyConfig();
        config.isPoolInRecoveryMode = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET),
            "isPoolInRecoveryMode mismatch"
        );

        config = _createEmptyConfig();
        config.hasDynamicSwapFee = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.DYNAMIC_SWAP_FEE_OFFSET),
            "hasDynamicSwapFee mismatch"
        );

        config = _createEmptyConfig();
        config.staticSwapFeePercentage = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH),
            "staticSwapFeePercentage mismatch"
        );

        config = _createEmptyConfig();
        config.tokenDecimalDiffs = MAX_UINT24_VALUE;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertUint(
                MAX_UINT24_VALUE,
                PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
                TOKEN_DECIMAL_DIFFS_BITLENGTH
            ),
            "tokenDecimalDiffs mismatch"
        );

        config = _createEmptyConfig();
        config.pauseWindowEndTime = MAX_UINT32_VALUE;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertUint(MAX_UINT32_VALUE, PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH),
            "pauseWindowEndTime mismatch"
        );

        // check .hooks
        config = _createEmptyConfig();
        config.hooks.shouldCallBeforeInitialize = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.BEFORE_INITIALIZE_OFFSET),
            "shouldCallBeforeInitialize mismatch"
        );

        config = _createEmptyConfig();
        config.hooks.shouldCallAfterInitialize = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.AFTER_INITIALIZE_OFFSET),
            "shouldCallAfterInitialize mismatch"
        );

        config = _createEmptyConfig();
        config.hooks.shouldCallBeforeAddLiquidity = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.BEFORE_ADD_LIQUIDITY_OFFSET),
            "shouldCallBeforeAddLiquidity mismatch"
        );

        config = _createEmptyConfig();
        config.hooks.shouldCallAfterAddLiquidity = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.AFTER_ADD_LIQUIDITY_OFFSET),
            "shouldCallAfterAddLiquidity mismatch"
        );

        config = _createEmptyConfig();
        config.hooks.shouldCallBeforeRemoveLiquidity = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.BEFORE_REMOVE_LIQUIDITY_OFFSET),
            "shouldCallBeforeRemoveLiquidity mismatch"
        );

        config = _createEmptyConfig();
        config.hooks.shouldCallAfterRemoveLiquidity = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.AFTER_REMOVE_LIQUIDITY_OFFSET),
            "shouldCallAfterRemoveLiquidity mismatch"
        );

        config = _createEmptyConfig();
        config.hooks.shouldCallBeforeSwap = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.BEFORE_SWAP_OFFSET),
            "shouldCallBeforeSwap mismatch"
        );

        config = _createEmptyConfig();
        config.hooks.shouldCallAfterSwap = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.AFTER_SWAP_OFFSET),
            "shouldCallAfterSwap mismatch"
        );

        // check .liquidityManagement
        config = _createEmptyConfig();
        config.liquidityManagement.disableUnbalancedLiquidity = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET),
            "disableUnbalancedLiquidity mismatch"
        );

        config = _createEmptyConfig();
        config.liquidityManagement.enableAddLiquidityCustom = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET),
            "enableAddLiquidityCustom mismatch"
        );

        config = _createEmptyConfig();
        config.liquidityManagement.enableRemoveLiquidityCustom = true;
        assertEq(
            PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
            bytes32(0).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET),
            "enableRemoveLiquidityCustom mismatch"
        );
    }

    function testToPoolConfigWithZeroBytes() public {
        PoolConfig memory zeroPoolConfig;

        assertEq(
            keccak256(abi.encode(PoolConfigBits.wrap(bytes32(0)).toPoolConfig())),
            keccak256(abi.encode(zeroPoolConfig)),
            "poolConfig isn't zeroPoolConfig"
        );
    }

    function testRequireUnbalancedLiquidityEnabled() public pure {
        PoolConfig memory config;

        // It's enabled by default
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireUnbalancedLiquidityEnabledIfIsDisabled() public {
        PoolConfig memory config;
        config.liquidityManagement.disableUnbalancedLiquidity = true;

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        config.requireUnbalancedLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityEnabled() public pure {
        PoolConfig memory config;
        config.liquidityManagement.enableAddLiquidityCustom = true;

        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireAddCustomLiquidityEnabledIfIsDisabled() public {
        PoolConfig memory config;

        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        config.requireAddCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityEnabled() public pure {
        PoolConfig memory config;
        config.liquidityManagement.enableRemoveLiquidityCustom = true;

        config.requireRemoveCustomLiquidityEnabled();
    }

    function testRequireRemoveCustomLiquidityEnabledIfIsDisabled() public {
        PoolConfig memory config;

        vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
        config.requireRemoveCustomLiquidityEnabled();
    }

    function testToAndFromConfigBits__Fuzz(uint256 rawConfigInt) public {
        rawConfigInt = bound(rawConfigInt, 0, uint256(1 << CONFIG_MSB) - 1);
        bytes32 rawConfig = bytes32(rawConfigInt);
        PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(rawConfig));
        bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

        assertEq(rawConfig, configBytes32);
    }

    function testUnusedConfigBits() public {
        bytes32 unusedBits = bytes32(uint256(type(uint256).max << (CONFIG_MSB + 1)));

        PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(unusedBits));
        bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

        assertEq(bytes32(0), configBytes32);
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

        assertEq(PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs), value, "tokenDecimalDiffs mismatch");
    }

    function testGetDecimalScalingFactors() public {
        PoolConfig memory config;
        uint256 valueOne = 5;
        uint256 valueTwo = 20;

        config.tokenDecimalDiffs = uint256(
            bytes32(0).insertUint(valueOne, 0, DECIMAL_DIFF_BITLENGTH).insertUint(
                valueTwo,
                DECIMAL_DIFF_BITLENGTH,
                DECIMAL_DIFF_BITLENGTH
            )
        );

        uint256[] memory scalingFactors = config.getDecimalScalingFactors(2);

        assertEq(scalingFactors[0], 1e23, "scalingFactors[0] mismatch");
        assertEq(scalingFactors[1], 1e38, "scalingFactors[1] mismatch");
    }

    // #endregion

    // #region private
    function _createEmptyConfig() private pure returns (PoolConfig memory) {}

    function _checkBits(uint256 startBit, uint256 size) private {
        uint endBit = startBit + size;
        for (uint256 i = startBit; i < endBit; i++) {
            _checkBit(i);
        }
    }

    function _checkBit(uint256 bitNumber) private {
        assertEq(usedBits[bitNumber], false, "Bit already used");
        usedBits[bitNumber] = true;
    }
    // #endregion
}
