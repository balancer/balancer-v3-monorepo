// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolPauseConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

// @notice Config type to store the pause-related timestamps for each pool.
type PoolPauseConfigBits is bytes32;

using PoolPauseConfigLib for PoolPauseConfigBits global;

library PoolPauseConfigLib {
    using WordCodec for bytes32;

    // [ 191 bits | 1 bit  |    32 bits   |    32 bits    ]
    // [  unused  | paused | pause window | buffer period ]
    // [ MSB                                          LSB ]

    // Bit offsets for pool pause config
    uint8 public constant TIMESTAMP_BITLENGTH = 32;

    uint8 public constant BUFFER_PERIOD_OFFSET = 0;
    uint8 public constant PAUSE_WINDOW_OFFSET = BUFFER_PERIOD_OFFSET + TIMESTAMP_BITLENGTH;
    uint8 public constant POOL_PAUSED_OFFSET = PAUSE_WINDOW_OFFSET + TIMESTAMP_BITLENGTH;

    function isPoolPaused(PoolPauseConfigBits config) internal pure returns (bool) {
        return PoolPauseConfigBits.unwrap(config).decodeBool(POOL_PAUSED_OFFSET);
    }

    function getPauseWindowEndTime(PoolPauseConfigBits config) internal pure returns (uint256) {
        return PoolPauseConfigBits.unwrap(config).decodeUint(PAUSE_WINDOW_OFFSET, TIMESTAMP_BITLENGTH);
    }

    function getBufferPeriodEndTime(PoolPauseConfigBits config) internal pure returns (uint256) {
        return PoolPauseConfigBits.unwrap(config).decodeUint(BUFFER_PERIOD_OFFSET, TIMESTAMP_BITLENGTH);
    }

    function fromPoolPauseConfig(PoolPauseConfig memory config) internal pure returns (PoolPauseConfigBits) {
        return
            PoolPauseConfigBits.wrap(
                bytes32(0)
                    .insertBool(config.isPoolPaused, POOL_PAUSED_OFFSET)
                    .insertUint(config.pauseWindowEndTime, PAUSE_WINDOW_OFFSET, TIMESTAMP_BITLENGTH)
                    .insertUint(config.bufferPeriodEndTime, BUFFER_PERIOD_OFFSET, TIMESTAMP_BITLENGTH)
            );
    }

    function toPoolPauseConfig(PoolPauseConfigBits config) internal pure returns (PoolPauseConfig memory) {
        return
            PoolPauseConfig({
                isPoolPaused: config.isPoolPaused(),
                pauseWindowEndTime: config.getPauseWindowEndTime(),
                bufferPeriodEndTime: config.getBufferPeriodEndTime()
            });
    }
}
