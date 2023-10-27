// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

// solhint-disable-next-line max-line-length
import { PoolConfig, PoolCallbacks, LiquidityManagement, LiquidityManagementDefaults } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";

// @notice Config type to store entire configuration of the pool
type PoolConfigBits is bytes32;

using PoolConfigLib for PoolConfigBits global;

library PoolConfigLib {
    using WordCodec for bytes32;

    // [  249 bit |    1 bit     |     1 bit     |   1 bit   |   1 bit    |    1 bit   |    1 bit    |    1 bit   ]
    // [ not used | after remove | before remove | after add | before add | after swap | initialized | registered ]
    // |MSB                                                                                                    LSB|

    // Bit offsets for pool config
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = 1;
    uint8 public constant AFTER_SWAP_OFFSET = 2;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = 3;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = 4;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = 5;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = 6;

    // Supported API bit offsets
    uint8 public constant ADD_LIQUIDITY_PROPORTIONAL_OFFSET = 7;
    uint8 public constant ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET = 8;
    uint8 public constant ADD_LIQUIDITY_UNBALANCED_OFFSET = 9;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = 10;
    uint8 public constant REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET = 11;
    uint8 public constant REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET = 12;
    uint8 public constant REMOVE_LIQUIDITY_UNBALANCED_OFFSET = 13;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = 14;

    // Bitwise flags for pool's config
    uint256 public constant POOL_REGISTERED_FLAG = 1 << POOL_REGISTERED_OFFSET;
    uint256 public constant POOL_INITIALIZED_FLAG = 1 << POOL_INITIALIZED_OFFSET;
    uint256 public constant AFTER_SWAP_FLAG = 1 << AFTER_SWAP_OFFSET;
    uint256 public constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << BEFORE_ADD_LIQUIDITY_OFFSET;
    uint256 public constant AFTER_ADD_LIQUIDITY_FLAG = 1 << AFTER_ADD_LIQUIDITY_OFFSET;
    uint256 public constant BEFORE_REMOVE_LIQUIDITY_FLAG = 1 << BEFORE_REMOVE_LIQUIDITY_OFFSET;
    uint256 public constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << AFTER_REMOVE_LIQUIDITY_OFFSET;

    // Bitwise flags for supported API
    uint256 public constant ADD_LIQUIDITY_PROPORTIONAL_FLAG = 1 << ADD_LIQUIDITY_PROPORTIONAL_OFFSET;
    uint256 public constant ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_FLAG =
        1 << ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET;
    uint256 public constant ADD_LIQUIDITY_UNBALANCED_FLAG = 1 << ADD_LIQUIDITY_UNBALANCED_OFFSET;
    uint256 public constant ADD_LIQUIDITY_CUSTOM_FLAG = 1 << ADD_LIQUIDITY_CUSTOM_OFFSET;
    uint256 public constant REMOVE_LIQUIDITY_PROPORTIONAL_FLAG = 1 << REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET;
    uint256 public constant REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_FLAG =
        1 << REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET;
    uint256 public constant REMOVE_LIQUIDITY_UNBALANCED_FLAG = 1 << REMOVE_LIQUIDITY_UNBALANCED_OFFSET;
    uint256 public constant REMOVE_LIQUIDITY_CUSTOM_FLAG = 1 << REMOVE_LIQUIDITY_CUSTOM_OFFSET;

    function addRegistration(PoolConfigBits config) internal pure returns (PoolConfigBits) {
        return PoolConfigBits.wrap(PoolConfigBits.unwrap(config).insertBool(true, POOL_REGISTERED_OFFSET));
    }

    function isPoolRegistered(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_REGISTERED_OFFSET);
    }

    function isPoolInitialized(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(POOL_INITIALIZED_OFFSET);
    }

    function shouldCallAfterSwap(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_SWAP_OFFSET);
    }

    function shouldCallBeforeAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_ADD_LIQUIDITY_FLAG);
    }

    function shouldCallAfterAddLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_ADD_LIQUIDITY_FLAG);
    }

    function shouldCallBeforeRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(BEFORE_REMOVE_LIQUIDITY_FLAG);
    }

    function shouldCallAfterRemoveLiquidity(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(AFTER_REMOVE_LIQUIDITY_FLAG);
    }

    function supportsAddLiquidityProportional(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_PROPORTIONAL_FLAG);
    }

    function supportsAddLiquiditySingleTokenExactOut(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_FLAG);
    }

    function supportsAddLiquidityUnbalanced(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_UNBALANCED_FLAG);
    }

    function supportsAddLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(ADD_LIQUIDITY_CUSTOM_FLAG);
    }

    function supportsRemoveLiquidityProportional(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_PROPORTIONAL_FLAG);
    }

    function supportsRemoveLiquiditySingleTokenExactIn(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_FLAG);
    }

    function supportsRemoveLiquidityUnbalanced(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_UNBALANCED_FLAG);
    }

    function supportsRemoveLiquidityCustom(PoolConfigBits config) internal pure returns (bool) {
        return PoolConfigBits.unwrap(config).decodeBool(REMOVE_LIQUIDITY_CUSTOM_FLAG);
    }

    function fromPoolConfig(PoolConfig memory config) internal pure returns (PoolConfigBits) {
        bytes32 configBits = bytes32(0);

        // Stack too deep.
        {
            configBits = configBits.insertBool(config.isRegisteredPool, POOL_REGISTERED_OFFSET);
            configBits = configBits.insertBool(config.isInitializedPool, POOL_INITIALIZED_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.callbacks.shouldCallAfterSwap, AFTER_SWAP_OFFSET)
                .insertBool(config.callbacks.shouldCallBeforeAddLiquidity, BEFORE_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.callbacks.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.callbacks.shouldCallBeforeRemoveLiquidity, BEFORE_REMOVE_LIQUIDITY_OFFSET)
                .insertBool(config.callbacks.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(
                    config.liquidityManagement.supportsAddLiquiditySingleTokenExactOut,
                    ADD_LIQUIDITY_SINGLE_TOKEN_EXACT_OUT_OFFSET
                )
                .insertBool(config.liquidityManagement.supportsAddLiquidityUnbalanced, ADD_LIQUIDITY_UNBALANCED_OFFSET)
                .insertBool(config.liquidityManagement.supportsAddLiquidityCustom, ADD_LIQUIDITY_CUSTOM_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(
                    config.liquidityManagement.supportsRemoveLiquiditySingleTokenExactIn,
                    REMOVE_LIQUIDITY_SINGLE_TOKEN_EXACT_IN_OFFSET
                )
                .insertBool(
                    config.liquidityManagement.supportsRemoveLiquidityUnbalanced,
                    REMOVE_LIQUIDITY_UNBALANCED_OFFSET
                )
                .insertBool(config.liquidityManagement.supportsRemoveLiquidityCustom, REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        }

        return
            PoolConfigBits.wrap(
                configBits
                    .insertBool(
                        config.liquidityManagementDefaults.supportsAddLiquidityProportional,
                        ADD_LIQUIDITY_PROPORTIONAL_OFFSET
                    )
                    .insertBool(
                        config.liquidityManagementDefaults.supportsRemoveLiquidityProportional,
                        REMOVE_LIQUIDITY_PROPORTIONAL_OFFSET
                    )
            );
    }

    function toPoolConfig(PoolConfigBits config) internal pure returns (PoolConfig memory) {
        return
            PoolConfig({
                isRegisteredPool: config.isPoolRegistered(),
                isInitializedPool: config.isPoolInitialized(),
                callbacks: PoolCallbacks({
                    shouldCallBeforeAddLiquidity: config.shouldCallBeforeAddLiquidity(),
                    shouldCallAfterAddLiquidity: config.shouldCallAfterAddLiquidity(),
                    shouldCallBeforeRemoveLiquidity: config.shouldCallBeforeRemoveLiquidity(),
                    shouldCallAfterRemoveLiquidity: config.shouldCallAfterRemoveLiquidity(),
                    shouldCallAfterSwap: config.shouldCallAfterSwap()
                }),
                liquidityManagement: LiquidityManagement({
                    supportsAddLiquiditySingleTokenExactOut: config.supportsAddLiquiditySingleTokenExactOut(),
                    supportsAddLiquidityUnbalanced: config.supportsAddLiquidityUnbalanced(),
                    supportsAddLiquidityCustom: config.supportsAddLiquidityCustom(),
                    supportsRemoveLiquiditySingleTokenExactIn: config.supportsRemoveLiquiditySingleTokenExactIn(),
                    supportsRemoveLiquidityUnbalanced: config.supportsRemoveLiquidityUnbalanced(),
                    supportsRemoveLiquidityCustom: config.supportsRemoveLiquidityCustom()
                }),
                liquidityManagementDefaults: LiquidityManagementDefaults({
                    supportsAddLiquidityProportional: config.supportsAddLiquidityProportional(),
                    supportsRemoveLiquidityProportional: config.supportsRemoveLiquidityProportional()
                })
            });
    }
}
