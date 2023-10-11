// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolConfig, PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

// @notice Config type to store entire configuration of the pool
type PoolConfigBits is bytes32;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    using WordCodec for bytes32;

    /// [  250 bit |    1 bit     |    1 bit  |   1 bit    |     1 bit   |    1 bit    |    1 bit   ]
    /// [ not used | after remove | after add | after swap | dynamic fee | initialized | registered ]
    /// |MSB                                                                                     LSB|

    // Bit offsets for pool config
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = 1;
    uint8 public constant DYNAMIC_SWAP_FEE = 2;
    // takes 20 bits to represent values up to 1'000'000 which should be enough for the swap fee
    uint8 public constant STATIC_SWAP_FEE_SIZE = 20;
    uint8 public constant STATIC_SWAP_FEE = 2 + STATIC_SWAP_FEE_SIZE;
    uint8 public constant AFTER_SWAP_OFFSET = 3 + STATIC_SWAP_FEE_SIZE;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = 4 + STATIC_SWAP_FEE_SIZE;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = 5 + STATIC_SWAP_FEE_SIZE;

    // Bitwise flags for pool's config
    uint256 public constant POOL_REGISTERED_FLAG = 1 << POOL_REGISTERED_OFFSET;
    uint256 public constant POOL_INITIALIZED_FLAG = 1 << POOL_INITIALIZED_OFFSET;
    uint256 public constant DYNAMIC_SWAP_FEE_FLAG = 1 << DYNAMIC_SWAP_FEE;
    uint256 public constant STATIC_SWAP_FEE_FLAG = 1 << STATIC_SWAP_FEE;
    uint256 public constant AFTER_SWAP_FLAG = 1 << AFTER_SWAP_OFFSET;
    uint256 public constant AFTER_ADD_LIQUIDITY_FLAG = 1 << AFTER_ADD_LIQUIDITY_OFFSET;
    uint256 public constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << AFTER_REMOVE_LIQUIDITY_OFFSET;

    function addRegistration(PoolConfigBits config) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, POOL_REGISTERED_OFFSET));
    }

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function hasDynamicSwapFee(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(DYNAMIC_SWAP_FEE_FLAG);
    }

    function getStaticSwapFee(PoolConfigBits config) internal pure returns (uint256) {
        return PoolConfigBits.unwrap(config).decodeUint(STATIC_SWAP_FEE_FLAG, STATIC_SWAP_FEE_SIZE);
    }

    function shouldCallAfterSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_SWAP_OFFSET);
    }

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_ADD_LIQUIDITY_FLAG);
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_REMOVE_LIQUIDITY_FLAG);
    }

    function fromPoolConfig(PoolConfig memory config) internal pure returns (PoolConfigBits) {
        return
            PoolConfigBits.wrap(
                bytes32(0)
                    .insertBool(config.isRegisteredPool, POOL_REGISTERED_OFFSET)
                    .insertBool(config.isInitializedPool, POOL_INITIALIZED_OFFSET)
                    .insertBool(config.hooks.shouldCallAfterSwap, AFTER_SWAP_OFFSET)
                    .insertBool(config.hooks.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET)
                    .insertBool(config.hooks.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET)
            );
    }

    function toPoolConfig(PoolConfigBits config) internal pure returns (PoolConfig memory) {
        return
            PoolConfig({
                isRegisteredPool: config.isPoolRegistered(),
                isInitializedPool: config.isPoolInitialized(),
                hasDynamicSwapFee: config.hasDynamicSwapFee(),
                hooks: PoolHooks({
                    shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                    shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity(),
                    shouldCallAfterSwap: config.shouldCallAfterSwap()
                })
            });
    }
}
