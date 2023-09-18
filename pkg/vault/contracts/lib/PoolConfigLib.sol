// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolConfig, PoolRegistrationConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

// @notice Config type to store entire configuration of the pool
type PoolConfigBits is bytes32;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    using WordCodec for bytes32;

    // Bit offsets for each flag
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_PAUSED_OFFSET = 1;
    uint8 public constant AFTER_SWAP_OFFSET = 2;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = 3;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = 4;
    uint8 public constant PAUSE_WINDOW_DURATION_OFFSET = 5;
    // Assuming that the max pause window is 3 years == 1095 days == 94,608,000 seconds,
    // we allow for 27 bits of storage, which will support up to 134,217,727 seconds
    uint8 public constant PAUSE_WINDOW_DURATION_LENGTH = 27;
    uint8 public constant BUFFER_PERIOD_DURATION_OFFSET = 32;
    // Assuming that the max pause window is 1 year == 365 days == 31,536,000 seconds,
    // we allow for 26 bits of storage, which will support up to 67,108,863 seconds
    uint8 public constant BUFFER_PERIOD_DURATION_LENGTH = 26;

    function addRegistration(PoolConfigBits config) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, POOL_REGISTERED_OFFSET));
    }

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function addPoolPaused(PoolConfigBits config) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, POOL_PAUSED_OFFSET));
    }

    function addPoolUnpaused(PoolConfigBits config) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(false, POOL_PAUSED_OFFSET));
    }

    function isPoolPaused(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_PAUSED_OFFSET);
    }

    function pauseWindowEndTime(PoolConfigBits config, uint256 registerTimestamp) internal pure returns (uint256) {
        return registerTimestamp + PoolConfigBits.unwrap(config).decodeUint(
            PAUSE_WINDOW_DURATION_OFFSET,
            PAUSE_WINDOW_DURATION_LENGTH
        );
    }

    function bufferPeriodEndTime(PoolConfigBits config, uint256 registerTimestamp) internal pure returns (uint256) {
        return config.pauseWindowEndTime(registerTimestamp) + PoolConfigBits.unwrap(config).decodeUint(
            BUFFER_PERIOD_DURATION_OFFSET,
            BUFFER_PERIOD_DURATION_LENGTH
        );
    }

    function shouldCallAfterSwap(PoolConfigBits config) internal pure returns (bool) {
        return WordCodec.decodeBool(PoolConfigBits.unwrap(config), AFTER_SWAP_OFFSET);
    }

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return WordCodec.decodeBool(PoolConfigBits.unwrap(config), AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return WordCodec.decodeBool(PoolConfigBits.unwrap(config), AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function fromPoolRegistrationConfig(PoolRegistrationConfig memory config) internal pure returns (PoolConfigBits) {
        bytes32 newConfig = bytes32(0);

        newConfig = newConfig.insertBool(false, POOL_REGISTERED_OFFSET);
        newConfig = newConfig.insertBool(false, POOL_PAUSED_OFFSET);
        newConfig = newConfig.insertBool(config.shouldCallAfterSwap, AFTER_SWAP_OFFSET);
        newConfig = newConfig.insertBool(config.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET);
        newConfig = newConfig.insertBool(config.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET);
        newConfig = newConfig.insertUint(config.pauseWindowDuration, PAUSE_WINDOW_DURATION_OFFSET, PAUSE_WINDOW_DURATION_LENGTH);
        newConfig = newConfig.insertUint(config.bufferPeriodDuration, BUFFER_PERIOD_DURATION_OFFSET, BUFFER_PERIOD_DURATION_LENGTH);
    
        return PoolConfigBits.wrap(newConfig);
    }

    function toPoolConfig(PoolConfigBits config, uint256 registerTimestamp) internal pure returns (PoolConfig memory) {
        return
            PoolConfig({
                isRegistered: config.isPoolRegistered(),
                isPaused: config.isPoolPaused(),
                pauseWindowEndTime: config.pauseWindowEndTime(registerTimestamp),
                bufferPeriodEndTime: config.bufferPeriodEndTime(registerTimestamp),
                shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity(),
                shouldCallAfterSwap: config.shouldCallAfterSwap()
            });
    }
}
