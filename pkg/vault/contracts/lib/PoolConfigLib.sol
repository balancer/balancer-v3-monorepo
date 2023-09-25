// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

// @notice Config type to store entire configuration of the pool
type PoolConfigBits is uint256;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    // Bit offsets for pool config
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant AFTER_SWAP_OFFSET = 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = 2;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = 3;

    // Bitwise flags for pool's config
    uint256 public constant POOL_REGISTERED_FLAG = 1 << POOL_REGISTERED_OFFSET;
    uint256 public constant AFTER_SWAP_FLAG = 1 << AFTER_SWAP_OFFSET;
    uint256 public constant AFTER_ADD_LIQUIDITY_FLAG = 1 << AFTER_ADD_LIQUIDITY_OFFSET;
    uint256 public constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << AFTER_REMOVE_LIQUIDITY_OFFSET;

    function addFlags(PoolConfigBits config, uint256 flags) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config) | flags);
    }

    function addRegistration(PoolConfigBits config) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config) | POOL_REGISTERED_FLAG);
    }

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config) & POOL_REGISTERED_FLAG != 0;
    }

    function shouldCallAfterSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config) & AFTER_SWAP_FLAG != 0;
    }

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config) & AFTER_ADD_LIQUIDITY_FLAG != 0;
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config) & AFTER_REMOVE_LIQUIDITY_FLAG != 0;
    }

    function fromPoolConfig(PoolConfig memory config) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                uint256((config.isRegisteredPool ? 1 : 0) << POOL_REGISTERED_OFFSET) |
                    uint256((config.shouldCallAfterSwap ? 1 : 0) << AFTER_SWAP_OFFSET) |
                    uint256((config.shouldCallAfterAddLiquidity ? 1 : 0) << AFTER_ADD_LIQUIDITY_OFFSET) |
                    uint256((config.shouldCallAfterRemoveLiquidity ? 1 : 0) << AFTER_REMOVE_LIQUIDITY_OFFSET)
            );
    }

    function toPoolConfig(PoolConfigBits config) internal pure returns (PoolConfig memory) {
        return
            PoolConfig({
                isRegisteredPool: config.isPoolRegistered(),
                shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity(),
                shouldCallAfterSwap: config.shouldCallAfterSwap()
            });
    }
}
