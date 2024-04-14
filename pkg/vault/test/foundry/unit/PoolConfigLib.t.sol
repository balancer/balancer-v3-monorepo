// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import { PoolConfig, PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

contract PoolConfigLibTest is Test {
    using PoolConfigLib for PoolConfigBits;
    using WordCodec for bytes32;

    uint256 private constant MAX_UINT24_VALUE = uint256(type(uint24).max);
    uint256 private constant MAX_UINT32_VALUE = uint256(type(uint32).max);
    uint256 constant FEE_SCALING_FACTOR = 1e11;
    uint256 constant FEE_BITLENGTH = 24;
    uint256 constant TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
    uint256 constant TIMESTAMP_BITLENGTH = 32;

    // 16 flags + 2 * 24 bit fee + 24 bit token diffs + 32 bit timestamp = 120 total bits used.
    uint256 private constant CONFIG_MSB = 120;

    // NOTE: we double use here offsets because we need to receive failed test if we change one of offsets in original code
    // #region slots
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = POOL_REGISTERED_OFFSET + 1;
    uint8 public constant POOL_PAUSED_OFFSET = POOL_INITIALIZED_OFFSET + 1;
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = POOL_PAUSED_OFFSET + 1;
    uint8 public constant BEFORE_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = BEFORE_SWAP_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_INITIALIZE_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_INITIALIZE_OFFSET = BEFORE_INITIALIZE_OFFSET + 1;
    uint8 public constant POOL_RECOVERY_MODE_OFFSET = AFTER_INITIALIZE_OFFSET + 1;

    // Supported liquidity API bit offsets
    uint8 public constant UNBALANCED_LIQUIDITY_OFFSET = POOL_RECOVERY_MODE_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = UNBALANCED_LIQUIDITY_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = ADD_LIQUIDITY_CUSTOM_OFFSET + 1;

    uint8 public constant STATIC_SWAP_FEE_OFFSET = REMOVE_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint256 public constant POOL_DEV_FEE_OFFSET = STATIC_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant DECIMAL_SCALING_FACTORS_OFFSET = POOL_DEV_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant PAUSE_WINDOW_END_TIME_OFFSET =
        DECIMAL_SCALING_FACTORS_OFFSET + TOKEN_DECIMAL_DIFFS_BITLENGTH;
    // #endregion

    // #region PoolConfigBits
    function testIsPoolRegistered() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, POOL_REGISTERED_OFFSET)).isPoolRegistered(),
            "isPoolRegistered is false"
        );
    }

    function testIsPoolInitialized() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, POOL_INITIALIZED_OFFSET)).isPoolInitialized(),
            "isPoolInitialized is false"
        );
    }

    function testIsPoolPaused() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, POOL_PAUSED_OFFSET)).isPoolPaused(),
            "isPoolPaused is false"
        );
    }

    function testHasDynamicSwapFee() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, DYNAMIC_SWAP_FEE_OFFSET)).hasDynamicSwapFee(),
            "hasDynamicSwapFee is false"
        );
    }

    function testShouldCallBeforeSwap() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, BEFORE_SWAP_OFFSET)).shouldCallBeforeSwap(),
            "shouldCallBeforeSwap is false"
        );
    }

    function testShouldCallAfterSwap() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, AFTER_SWAP_OFFSET)).shouldCallAfterSwap(),
            "shouldCallAfterSwap is false"
        );
    }

    function testShouldCallBeforeAddLiquidity() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, BEFORE_ADD_LIQUIDITY_OFFSET))
                .shouldCallBeforeAddLiquidity(),
            "shouldCallBeforeAddLiquidity is false"
        );
    }

    function testShouldCallAfterAddLiquidity() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, AFTER_ADD_LIQUIDITY_OFFSET)).shouldCallAfterAddLiquidity(),
            "shouldCallAfterAddLiquidity is false"
        );
    }

    function testShouldCallBeforeRemoveLiquidity() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, BEFORE_REMOVE_LIQUIDITY_OFFSET))
                .shouldCallBeforeRemoveLiquidity(),
            "shouldCallBeforeRemoveLiquidity is false"
        );
    }

    function testShouldCallAfterRemoveLiquidity() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, AFTER_REMOVE_LIQUIDITY_OFFSET))
                .shouldCallAfterRemoveLiquidity(),
            "shouldCallAfterRemoveLiquidity is false"
        );
    }

    function testShouldCallBeforeInitialize() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, BEFORE_INITIALIZE_OFFSET)).shouldCallBeforeInitialize(),
            "shouldCallBeforeInitialize is false"
        );
    }

    function testShouldCallAfterInitialize() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, AFTER_INITIALIZE_OFFSET)).shouldCallAfterInitialize(),
            "shouldCallAfterInitialize is false"
        );
    }

    function testIsPoolInRecoveryMode() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, POOL_RECOVERY_MODE_OFFSET)).isPoolInRecoveryMode(),
            "isPoolInRecoveryMode is false"
        );
    }

    function testSupportsUnbalancedLiquidity() public {
        // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
        assertFalse(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, UNBALANCED_LIQUIDITY_OFFSET)).supportsUnbalancedLiquidity(),
            "supportsUnbalancedLiquidity is true"
        );
    }

    function testSupportsAddLiquidityCustom() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, ADD_LIQUIDITY_CUSTOM_OFFSET)).supportsAddLiquidityCustom(),
            "supportsAddLiquidityCustom is false"
        );
    }

    function testSupportsRemoveLiquidityCustom() public {
        assertTrue(
            PoolConfigBits
                .wrap(bytes32(0).insertBool(true, REMOVE_LIQUIDITY_CUSTOM_OFFSET))
                .supportsRemoveLiquidityCustom(),
            "supportsRemoveLiquidityCustom is false"
        );
    }

    function testGetStaticSwapFeePercentage() public {
        assertEq(
            PoolConfigBits
                .wrap(bytes32(0).insertUint(MAX_UINT24_VALUE, STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH))
                .getStaticSwapFeePercentage(),
            MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
            "staticSwapFeePercentage mismatch"
        );
    }

    function testGetPoolCreatorFeePercentage() public {
        assertEq(
            PoolConfigBits
                .wrap(bytes32(0).insertUint(MAX_UINT24_VALUE, POOL_DEV_FEE_OFFSET, FEE_BITLENGTH))
                .getPoolCreatorFeePercentage(),
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
                        DECIMAL_SCALING_FACTORS_OFFSET,
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
                .wrap(bytes32(0).insertUint(MAX_UINT32_VALUE, PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH))
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
            .wrap(configBits.insertBool(true, POOL_PAUSED_OFFSET))
            .getPoolPausedState();
        assertTrue(isPaused, "(isPaused = true && pauseWithdrawEndTime == 0) isPaused mismatch");
        assertEq(
            pauseWithdrawEndTime,
            0,
            "(isPaused = true && pauseWithdrawEndTime == 0) pauseWithdrawEndTime mismatch"
        );

        (isPaused, pauseWithdrawEndTime) = PoolConfigBits
            .wrap(configBits.insertUint(MAX_UINT32_VALUE, PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH))
            .getPoolPausedState();
        assertFalse(isPaused, "(isPaused = false && pauseWithdrawEndTime != 0) isPaused mismatch");
        assertEq(
            pauseWithdrawEndTime,
            MAX_UINT32_VALUE,
            "(isPaused = false && pauseWithdrawEndTime != 0) pauseWithdrawEndTime mismatch"
        );

        (isPaused, pauseWithdrawEndTime) = PoolConfigBits
            .wrap(
                configBits.insertBool(true, POOL_PAUSED_OFFSET).insertUint(
                    MAX_UINT32_VALUE,
                    PAUSE_WINDOW_END_TIME_OFFSET,
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
        assertEq(configBits.getPoolCreatorFeePercentage(), 0, "staticSwapFeePercentage isn't zero");
        assertEq(configBits.getTokenDecimalDiffs(), 0, "tokenDecimalDiffs isn't zero");
        assertEq(configBits.getPauseWindowEndTime(), 0, "pauseWindowEndTime isn't zero");
    }

    // #endregion

    // #region PoolConfig
    function testToPoolConfig() public {
        assertTrue(
            PoolConfigBits.wrap(bytes32(0).insertBool(true, POOL_REGISTERED_OFFSET)).toPoolConfig().isPoolRegistered,
            "isPoolRegistered mismatch"
        );

        //TODO
    }

    function testToPoolConfigWithZeroBytes() public {
        PoolConfig memory zeroPoolConfig;

        assertEq(
            keccak256(abi.encode(PoolConfigBits.wrap(bytes32(0)).toPoolConfig())),
            keccak256(abi.encode(zeroPoolConfig)),
            "poolConfig isn't zeroPoolConfig"
        );
    }

    
    // #endregion

    //requireUnbalancedLiquidityEnabled
    // requireAddCustomLiquidityEnabled
    // requireRemoveCustomLiquidityEnabled
    // fromPoolConfig

    // toTokenDecimalDiffs
    // getDecimalScalingFactors
    // toPoolConfig

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
}
