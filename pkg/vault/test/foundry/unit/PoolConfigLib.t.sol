// // SPDX-License-Identifier: GPL-3.0-or-later

// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";

// import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
// import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

// import { PoolConfig, PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
// import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

// contract PoolConfigLibTest is Test {
//     using PoolConfigLib for PoolConfig;
//     using PoolConfigLib for PoolConfigBits;
//     using WordCodec for bytes32;

//     uint256 private constant MAX_UINT24_VALUE = uint256(type(uint24).max);
//     uint256 private constant MAX_UINT32_VALUE = uint256(type(uint32).max);
//     uint256 constant TOKEN_DECIMAL_DIFFS_BITLENGTH = 24;
//     uint8 constant DECIMAL_DIFF_BITLENGTH = 5;
//     uint256 constant TIMESTAMP_BITLENGTH = 32;

//     mapping(uint256 => bool) usedBits;

//     // 7 flags + 3 * 24 bit fee + 24 bit token diffs + 32 bit timestamp = 135 total bits used.
//     uint256 private constant BITS_IN_USE = 135;

//     // #region PoolConfigBits
//     function testOffsets() public {
//         _checkBit(PoolConfigLib.POOL_REGISTERED_OFFSET);
//         _checkBit(PoolConfigLib.POOL_INITIALIZED_OFFSET);
//         _checkBit(PoolConfigLib.POOL_PAUSED_OFFSET);
//         _checkBit(PoolConfigLib.POOL_RECOVERY_MODE_OFFSET);
//         _checkBit(PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET);
//         _checkBit(PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET);
//         _checkBit(PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET);

//         _checkBits(PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH);
//         _checkBits(PoolConfigLib.AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET, FEE_BITLENGTH);
//         _checkBits(PoolConfigLib.AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET, FEE_BITLENGTH);
//         _checkBits(PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET, TOKEN_DECIMAL_DIFFS_BITLENGTH);
//         _checkBits(PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH);
//     }

//     function testIsPoolRegistered() public {
//         assertTrue(
//             PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET)).isPoolRegistered(),
//             "isPoolRegistered is false"
//         );
//     }

//     function testIsPoolInitialized() public {
//         assertTrue(
//             PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET)).isPoolInitialized(),
//             "isPoolInitialized is false"
//         );
//     }

//     function testIsPoolPaused() public {
//         assertTrue(
//             PoolConfigBits.wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET)).isPoolPaused(),
//             "isPoolPaused is false"
//         );
//     }

//     function testIsPoolInRecoveryMode() public {
//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET))
//                 .isPoolInRecoveryMode(),
//             "isPoolInRecoveryMode is false"
//         );
//     }

//     function testSupportsUnbalancedLiquidity() public {
//         // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
//         assertFalse(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET))
//                 .supportsUnbalancedLiquidity(),
//             "supportsUnbalancedLiquidity is true"
//         );
//     }

//     function testSupportsAddLiquidityCustom() public {
//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET))
//                 .supportsAddLiquidityCustom(),
//             "supportsAddLiquidityCustom is false"
//         );
//     }

//     function testSupportsRemoveLiquidityCustom() public {
//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET))
//                 .supportsRemoveLiquidityCustom(),
//             "supportsRemoveLiquidityCustom is false"
//         );
//     }

//     function testGetStaticSwapFeePercentage() public {
//         assertEq(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH))
//                 .getStaticSwapFeePercentage(),
//             MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
//             "staticSwapFeePercentage mismatch (testGetStaticSwapFeePercentage)"
//         );
//     }

//     function testGetAggregateProtocolSwapFeePercentage() public {
//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT24_VALUE,
//                         PoolConfigLib.AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
//                         FEE_BITLENGTH
//                     )
//                 )
//                 .getAggregateProtocolSwapFeePercentage(),
//             MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
//             "getAggregateProtocolSwapFeePercentage mismatch (testGetAggregateProtocolSwapFeePercentage)"
//         );
//     }

//     function testGetAggregateProtocolYieldFeePercentage() public {
//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT24_VALUE,
//                         PoolConfigLib.AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
//                         FEE_BITLENGTH
//                     )
//                 )
//                 .getAggregateProtocolYieldFeePercentage(),
//             MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
//             "getAggregateProtocolYieldFeePercentage mismatch (testGetAggregateProtocolYieldFeePercentage)"
//         );
//     }

//     function testGetTokenDecimalDiffs() public {
//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT24_VALUE,
//                         PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
//                         TOKEN_DECIMAL_DIFFS_BITLENGTH
//                     )
//                 )
//                 .getTokenDecimalDiffs(),
//             MAX_UINT24_VALUE,
//             "tokenDecimalDiffs mismatch (testGetTokenDecimalDiffs)"
//         );
//     }

//     function testGetPauseWindowEndTime() public {
//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT32_VALUE,
//                         PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
//                         TIMESTAMP_BITLENGTH
//                     )
//                 )
//                 .getPauseWindowEndTime(),
//             MAX_UINT32_VALUE,
//             "pauseWindowEndTime mismatch (testGetPauseWindowEndTime)"
//         );
//     }

//     function testGetPoolPausedState() public {
//         bytes32 configBits = bytes32(0);

//         bool isPaused;
//         uint256 pauseWithdrawEndTime;

//         (isPaused, pauseWithdrawEndTime) = PoolConfigBits.wrap(configBits).getPoolPausedState();
//         assertFalse(isPaused, "(empty bytes) isPaused mismatch");

//         (isPaused, pauseWithdrawEndTime) = PoolConfigBits
//             .wrap(configBits.insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET))
//             .getPoolPausedState();
//         assertTrue(isPaused, "(isPaused = true && pauseWithdrawEndTime == 0) isPaused mismatch");
//         assertEq(
//             pauseWithdrawEndTime,
//             0,
//             "(isPaused = true && pauseWithdrawEndTime == 0) pauseWithdrawEndTime mismatch"
//         );

//         (isPaused, pauseWithdrawEndTime) = PoolConfigBits
//             .wrap(
//                 configBits.insertUint(MAX_UINT32_VALUE, PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH)
//             )
//             .getPoolPausedState();
//         assertFalse(isPaused, "(isPaused = false && pauseWithdrawEndTime != 0) isPaused mismatch");
//         assertEq(
//             pauseWithdrawEndTime,
//             MAX_UINT32_VALUE,
//             "(isPaused = false && pauseWithdrawEndTime != 0) pauseWithdrawEndTime mismatch"
//         );

//         (isPaused, pauseWithdrawEndTime) = PoolConfigBits
//             .wrap(
//                 configBits.insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET).insertUint(
//                     MAX_UINT32_VALUE,
//                     PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
//                     TIMESTAMP_BITLENGTH
//                 )
//             )
//             .getPoolPausedState();
//         assertTrue(isPaused, "(isPaused = true && pauseWithdrawEndTime != 0) isPaused mismatch");
//         assertEq(
//             pauseWithdrawEndTime,
//             MAX_UINT32_VALUE,
//             "(isPaused = true && pauseWithdrawEndTime != 0) pauseWithdrawEndTime mismatch"
//         );
//     }

//     function testZeroConfigBytes() public {
//         PoolConfigBits configBits = PoolConfigBits.wrap(bytes32(0));

//         assertFalse(configBits.isPoolRegistered(), "isPoolRegistered is true");
//         assertFalse(configBits.isPoolInitialized(), "isPoolInitialized is true");
//         assertFalse(configBits.isPoolPaused(), "isPoolPaused is true");
//         assertFalse(configBits.isPoolInRecoveryMode(), "isPoolInRecoveryMode is true");

//         // NOTE: assertFalse is here because supportsUnbalancedLiquidity reverse value
//         assertTrue(configBits.supportsUnbalancedLiquidity(), "supportsUnbalancedLiquidity is false");

//         assertFalse(configBits.supportsAddLiquidityCustom(), "supportsAddLiquidityCustom is true");
//         assertFalse(configBits.supportsRemoveLiquidityCustom(), "supportsRemoveLiquidityCustom is true");
//         assertEq(configBits.getStaticSwapFeePercentage(), 0, "staticSwapFeePercentage isn't zero");
//         assertEq(
//             configBits.getAggregateProtocolSwapFeePercentage(),
//             0,
//             "aggregateProtocolSwapFeePercentage isn't zero"
//         );
//         assertEq(
//             configBits.getAggregateProtocolYieldFeePercentage(),
//             0,
//             "aggregateProtocolYieldFeePercentage isn't zero"
//         );
//         assertEq(configBits.getTokenDecimalDiffs(), 0, "tokenDecimalDiffs isn't zero");
//         assertEq(configBits.getPauseWindowEndTime(), 0, "pauseWindowEndTime isn't zero");
//     }

//     // #endregion

//     // #region PoolConfig
//     function testToPoolConfig() public {
//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET))
//                 .toPoolConfig()
//                 .isPoolRegistered,
//             "isPoolRegistered mismatch (testToPoolConfig)"
//         );

//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET))
//                 .toPoolConfig()
//                 .isPoolInitialized,
//             "isPoolInitialized mismatch (testToPoolConfig)"
//         );

//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET))
//                 .toPoolConfig()
//                 .isPoolPaused,
//             "isPoolPaused mismatch (testToPoolConfig)"
//         );

//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET))
//                 .toPoolConfig()
//                 .isPoolInRecoveryMode,
//             "isPoolInRecoveryMode mismatch (testToPoolConfig)"
//         );

//         assertEq(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH))
//                 .toPoolConfig()
//                 .staticSwapFeePercentage,
//             MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
//             "staticSwapFeePercentage mismatch (testToPoolConfig)"
//         );

//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT24_VALUE,
//                         PoolConfigLib.AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET,
//                         FEE_BITLENGTH
//                     )
//                 )
//                 .toPoolConfig()
//                 .aggregateProtocolSwapFeePercentage,
//             MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
//             "aggregateProtocolSwapFeePercentage mismatch (testToPoolConfig)"
//         );

//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT24_VALUE,
//                         PoolConfigLib.AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET,
//                         FEE_BITLENGTH
//                     )
//                 )
//                 .toPoolConfig()
//                 .aggregateProtocolYieldFeePercentage,
//             MAX_UINT24_VALUE * FEE_SCALING_FACTOR,
//             "aggregateProtocolYieldFeePercentage mismatch (testToPoolConfig)"
//         );

//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT24_VALUE,
//                         PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
//                         TOKEN_DECIMAL_DIFFS_BITLENGTH
//                     )
//                 )
//                 .toPoolConfig()
//                 .tokenDecimalDiffs,
//             MAX_UINT24_VALUE,
//             "tokenDecimalDiffs mismatch (testToPoolConfig)"
//         );

//         assertEq(
//             PoolConfigBits
//                 .wrap(
//                     bytes32(0).insertUint(
//                         MAX_UINT32_VALUE,
//                         PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET,
//                         TIMESTAMP_BITLENGTH
//                     )
//                 )
//                 .toPoolConfig()
//                 .pauseWindowEndTime,
//             MAX_UINT32_VALUE,
//             "pauseWindowEndTime mismatch (testToPoolConfig)"
//         );

//         // check .liquidityManagement
//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET))
//                 .toPoolConfig()
//                 .liquidityManagement
//                 .disableUnbalancedLiquidity,
//             "disableUnbalancedLiquidity mismatch (testToPoolConfig)"
//         );

//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET))
//                 .toPoolConfig()
//                 .liquidityManagement
//                 .enableAddLiquidityCustom,
//             "enableAddLiquidityCustom mismatch (testToPoolConfig)"
//         );

//         assertTrue(
//             PoolConfigBits
//                 .wrap(bytes32(0).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET))
//                 .toPoolConfig()
//                 .liquidityManagement
//                 .enableRemoveLiquidityCustom,
//             "enableRemoveLiquidityCustom mismatch (testToPoolConfig)"
//         );
//     }

//     function testFromPoolConfig() public {
//         PoolConfig memory config;
//         config.isPoolRegistered = true;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertBool(true, PoolConfigLib.POOL_REGISTERED_OFFSET),
//             "isPoolRegistered mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.isPoolInitialized = true;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertBool(true, PoolConfigLib.POOL_INITIALIZED_OFFSET),
//             "isPoolInitialized mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.isPoolPaused = true;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertBool(true, PoolConfigLib.POOL_PAUSED_OFFSET),
//             "isPoolPaused mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.isPoolInRecoveryMode = true;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertBool(true, PoolConfigLib.POOL_RECOVERY_MODE_OFFSET),
//             "isPoolInRecoveryMode mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.staticSwapFeePercentage = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH),
//             "staticSwapFeePercentage mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.aggregateProtocolSwapFeePercentage = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.AGGREGATE_PROTOCOL_SWAP_FEE_OFFSET, FEE_BITLENGTH),
//             "aggregateProtocolSwapFeePercentage mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.aggregateProtocolYieldFeePercentage = MAX_UINT24_VALUE * FEE_SCALING_FACTOR;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertUint(MAX_UINT24_VALUE, PoolConfigLib.AGGREGATE_PROTOCOL_YIELD_FEE_OFFSET, FEE_BITLENGTH),
//             "aggregateProtocolYieldFeePercentage mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.tokenDecimalDiffs = MAX_UINT24_VALUE;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertUint(
//                 MAX_UINT24_VALUE,
//                 PoolConfigLib.DECIMAL_SCALING_FACTORS_OFFSET,
//                 TOKEN_DECIMAL_DIFFS_BITLENGTH
//             ),
//             "tokenDecimalDiffs mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.pauseWindowEndTime = MAX_UINT32_VALUE;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertUint(MAX_UINT32_VALUE, PoolConfigLib.PAUSE_WINDOW_END_TIME_OFFSET, TIMESTAMP_BITLENGTH),
//             "pauseWindowEndTime mismatch (testFromPoolConfig)"
//         );

//         // check .liquidityManagement
//         config = _createEmptyConfig();
//         config.liquidityManagement.disableUnbalancedLiquidity = true;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertBool(true, PoolConfigLib.UNBALANCED_LIQUIDITY_OFFSET),
//             "disableUnbalancedLiquidity mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.liquidityManagement.enableAddLiquidityCustom = true;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertBool(true, PoolConfigLib.ADD_LIQUIDITY_CUSTOM_OFFSET),
//             "enableAddLiquidityCustom mismatch (testFromPoolConfig)"
//         );

//         config = _createEmptyConfig();
//         config.liquidityManagement.enableRemoveLiquidityCustom = true;
//         assertEq(
//             PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config)),
//             bytes32(0).insertBool(true, PoolConfigLib.REMOVE_LIQUIDITY_CUSTOM_OFFSET),
//             "enableRemoveLiquidityCustom mismatch (testFromPoolConfig)"
//         );
//     }

//     function testToPoolConfigWithZeroBytes() public {
//         PoolConfig memory zeroPoolConfig;

//         assertEq(
//             keccak256(abi.encode(PoolConfigBits.wrap(bytes32(0)).toPoolConfig())),
//             keccak256(abi.encode(zeroPoolConfig)),
//             "poolConfig isn't zeroPoolConfig"
//         );
//     }

//     function testRequireUnbalancedLiquidityEnabled() public pure {
//         PoolConfig memory config;

//         // It's enabled by default
//         config.requireUnbalancedLiquidityEnabled();
//     }

//     function testRequireUnbalancedLiquidityEnabledIfIsDisabled() public {
//         PoolConfig memory config;
//         config.liquidityManagement.disableUnbalancedLiquidity = true;

//         vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
//         config.requireUnbalancedLiquidityEnabled();
//     }

//     function testRequireAddCustomLiquidityEnabled() public pure {
//         PoolConfig memory config;
//         config.liquidityManagement.enableAddLiquidityCustom = true;

//         config.requireAddCustomLiquidityEnabled();
//     }

//     function testRequireAddCustomLiquidityEnabledIfIsDisabled() public {
//         PoolConfig memory config;

//         vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
//         config.requireAddCustomLiquidityEnabled();
//     }

//     function testRequireRemoveCustomLiquidityEnabled() public pure {
//         PoolConfig memory config;
//         config.liquidityManagement.enableRemoveLiquidityCustom = true;

//         config.requireRemoveCustomLiquidityEnabled();
//     }

//     function testRequireRemoveCustomLiquidityEnabledIfIsDisabled() public {
//         PoolConfig memory config;

//         vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
//         config.requireRemoveCustomLiquidityEnabled();
//     }

//     function testToAndFromConfigBits__Fuzz(uint256 rawConfigInt) public {
//         rawConfigInt = bound(rawConfigInt, 0, uint256(1 << BITS_IN_USE) - 1);
//         bytes32 rawConfig = bytes32(rawConfigInt);
//         PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(rawConfig));
//         bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

//         assertEq(rawConfig, configBytes32);
//     }

//     function testUnusedConfigBits() public {
//         bytes32 unusedBits = bytes32(uint256(type(uint256).max << (BITS_IN_USE)));

//         PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(unusedBits));
//         bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

//         assertEq(bytes32(0), configBytes32);
//     }

//     function testToTokenDecimalDiffs() public {
//         uint8[] memory tokenDecimalDiffs = new uint8[](2);
//         tokenDecimalDiffs[0] = 1;
//         tokenDecimalDiffs[1] = 2;

//         uint256 value = uint256(
//             bytes32(0).insertUint(tokenDecimalDiffs[0], 0, DECIMAL_DIFF_BITLENGTH).insertUint(
//                 tokenDecimalDiffs[1],
//                 DECIMAL_DIFF_BITLENGTH,
//                 DECIMAL_DIFF_BITLENGTH
//             )
//         );

//         assertEq(
//             PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs),
//             value,
//             "tokenDecimalDiffs mismatch (testToTokenDecimalDiffs)"
//         );
//     }

//     function testGetDecimalScalingFactors() public {
//         PoolConfig memory config;
//         uint256 valueOne = 5;
//         uint256 valueTwo = 20;

//         config.tokenDecimalDiffs = uint256(
//             bytes32(0).insertUint(valueOne, 0, DECIMAL_DIFF_BITLENGTH).insertUint(
//                 valueTwo,
//                 DECIMAL_DIFF_BITLENGTH,
//                 DECIMAL_DIFF_BITLENGTH
//             )
//         );

//         uint256[] memory scalingFactors = config.getDecimalScalingFactors(2);

//         assertEq(scalingFactors[0], 1e23, "scalingFactors[0] mismatch");
//         assertEq(scalingFactors[1], 1e38, "scalingFactors[1] mismatch");
//     }

//     // #endregion

//     // #region private
//     function _createEmptyConfig() private pure returns (PoolConfig memory) {}

//     function _checkBits(uint256 startBit, uint256 size) private {
//         uint256 endBit = startBit + size;
//         for (uint256 i = startBit; i < endBit; i++) {
//             _checkBit(i);
//         }
//     }

//     function _checkBit(uint256 bitNumber) private {
//         assertEq(usedBits[bitNumber], false, "Bit already used");
//         usedBits[bitNumber] = true;
//     }
//     // #endregion
// }
