// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Config type to store entire configuration of the pool
type HooksBits is bytes32;

using HooksLib for HooksBits global;

library HooksLib {
    using WordCodec for bytes32;

    // Bit offsets for pool config
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = 0;
    uint8 public constant BEFORE_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = BEFORE_SWAP_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_INITIALIZE_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_INITIALIZE_OFFSET = BEFORE_INITIALIZE_OFFSET + 1;
    uint8 public constant HOOKS_CONTRACT_OFFSET = AFTER_INITIALIZE_OFFSET + 1;

    function shouldCallComputeDynamicSwapFee(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(DYNAMIC_SWAP_FEE_OFFSET);
    }

    function shouldCallBeforeSwap(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(BEFORE_SWAP_OFFSET);
    }

    function shouldCallAfterSwap(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(AFTER_SWAP_OFFSET);
    }

    function shouldCallBeforeAddLiquidity(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterAddLiquidity(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(AFTER_ADD_LIQUIDITY_OFFSET);
    }

    function shouldCallBeforeRemoveLiquidity(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET);
    }

    function shouldCallAfterRemoveLiquidity(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET);
    }

    function shouldCallBeforeInitialize(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(BEFORE_INITIALIZE_OFFSET);
    }

    function shouldCallAfterInitialize(HooksBits config) internal pure returns (bool) {
        return HooksBits.unwrap(config).decodeBool(AFTER_INITIALIZE_OFFSET);
    }

    function getHooksContract(HooksBits config) internal pure returns (address) {
        return HooksBits.unwrap(config).decodeAddress(HOOKS_CONTRACT_OFFSET);
    }

    function fromHooksConfig(HooksConfig memory config) internal pure returns (HooksBits) {
        bytes32 configBits = bytes32(0);

        // Stack too deep.
        {
            configBits = configBits.insertBool(config.shouldCallBeforeSwap, BEFORE_SWAP_OFFSET).insertBool(
                config.shouldCallAfterSwap,
                AFTER_SWAP_OFFSET
            ).insertAddress(config.hooksContract, HOOKS_CONTRACT_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.shouldCallBeforeAddLiquidity, BEFORE_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.shouldCallAfterAddLiquidity, AFTER_ADD_LIQUIDITY_OFFSET)
                .insertBool(config.shouldCallBeforeRemoveLiquidity, BEFORE_REMOVE_LIQUIDITY_OFFSET)
                .insertBool(config.shouldCallAfterRemoveLiquidity, AFTER_REMOVE_LIQUIDITY_OFFSET);
        }

        {
            configBits = configBits
                .insertBool(config.shouldCallBeforeInitialize, BEFORE_INITIALIZE_OFFSET)
                .insertBool(config.shouldCallAfterInitialize, AFTER_INITIALIZE_OFFSET)
                .insertBool(config.shouldCallComputeDynamicSwapFee, DYNAMIC_SWAP_FEE_OFFSET);
        }

        return HooksBits.wrap(configBits);
    }

    function toHooksConfig(HooksBits config) internal pure returns (HooksConfig memory) {
        bytes32 rawConfig = HooksBits.unwrap(config);

        // Calling the functions (in addition to costing more gas), causes an obscure form of stack error (Yul errors).
        return
            HooksConfig({
                shouldCallBeforeInitialize: rawConfig.decodeBool(BEFORE_INITIALIZE_OFFSET),
                shouldCallAfterInitialize: rawConfig.decodeBool(AFTER_INITIALIZE_OFFSET),
                shouldCallBeforeAddLiquidity: rawConfig.decodeBool(BEFORE_ADD_LIQUIDITY_OFFSET),
                shouldCallAfterAddLiquidity: rawConfig.decodeBool(AFTER_ADD_LIQUIDITY_OFFSET),
                shouldCallBeforeRemoveLiquidity: rawConfig.decodeBool(BEFORE_REMOVE_LIQUIDITY_OFFSET),
                shouldCallAfterRemoveLiquidity: rawConfig.decodeBool(AFTER_REMOVE_LIQUIDITY_OFFSET),
                shouldCallComputeDynamicSwapFee: rawConfig.decodeBool(DYNAMIC_SWAP_FEE_OFFSET),
                shouldCallBeforeSwap: rawConfig.decodeBool(BEFORE_SWAP_OFFSET),
                shouldCallAfterSwap: rawConfig.decodeBool(AFTER_SWAP_OFFSET),
                hooksContract: rawConfig.decodeAddress(HOOKS_CONTRACT_OFFSET)
        });
    }
}
