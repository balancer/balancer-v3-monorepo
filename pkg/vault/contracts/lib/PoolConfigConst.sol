// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FEE_BITLENGTH } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @notice Helper functions to read and write the packed configuration flags stored in `_poolConfigBits`.
 * @dev Note that the entire configuration of each pool is stored in the `_poolConfigBits` mapping (one slot per pool).
 * This includes the data in the `PoolConfig` struct, plus the data in the `HookFlags` struct. The layout (i.e.,
 * offsets for each data field) is specified here.
 *
 * There are two libraries for interpreting these data. `HooksConfigLib` parses fields related to hooks, while
 * `PoolConfigLib` contains helpers related to the non-hook-related flags, along with aggregate fee percentages
 * and other data associated with pools.
 */
library PoolConfigConst {
    error InvalidSize(uint256 currentValue, uint256 expectedSize);

    // Bit offsets for main pool config settings
    uint8 public constant POOL_REGISTERED_OFFSET = 0;
    uint8 public constant POOL_INITIALIZED_OFFSET = POOL_REGISTERED_OFFSET + 1;
    uint8 public constant POOL_PAUSED_OFFSET = POOL_INITIALIZED_OFFSET + 1;
    uint8 public constant POOL_RECOVERY_MODE_OFFSET = POOL_PAUSED_OFFSET + 1;

    // Bit offsets for liquidity operations
    uint8 public constant UNBALANCED_LIQUIDITY_OFFSET = POOL_RECOVERY_MODE_OFFSET + 1;
    uint8 public constant ADD_LIQUIDITY_CUSTOM_OFFSET = UNBALANCED_LIQUIDITY_OFFSET + 1;
    uint8 public constant REMOVE_LIQUIDITY_CUSTOM_OFFSET = ADD_LIQUIDITY_CUSTOM_OFFSET + 1;
    uint8 public constant DONATION_OFFSET = REMOVE_LIQUIDITY_CUSTOM_OFFSET + 1;

    // Bit offsets for hooks config
    uint8 public constant BEFORE_INITIALIZE_OFFSET = DONATION_OFFSET + 1;
    uint8 public constant ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET = BEFORE_INITIALIZE_OFFSET + 1;
    uint8 public constant AFTER_INITIALIZE_OFFSET = ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET + 1;
    uint8 public constant DYNAMIC_SWAP_FEE_OFFSET = AFTER_INITIALIZE_OFFSET + 1;
    uint8 public constant BEFORE_SWAP_OFFSET = DYNAMIC_SWAP_FEE_OFFSET + 1;
    uint8 public constant AFTER_SWAP_OFFSET = BEFORE_SWAP_OFFSET + 1;
    uint8 public constant BEFORE_ADD_LIQUIDITY_OFFSET = AFTER_SWAP_OFFSET + 1;
    uint8 public constant AFTER_ADD_LIQUIDITY_OFFSET = BEFORE_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant BEFORE_REMOVE_LIQUIDITY_OFFSET = AFTER_ADD_LIQUIDITY_OFFSET + 1;
    uint8 public constant AFTER_REMOVE_LIQUIDITY_OFFSET = BEFORE_REMOVE_LIQUIDITY_OFFSET + 1;

    // Bit offsets for uint values
    uint8 public constant STATIC_SWAP_FEE_OFFSET = AFTER_REMOVE_LIQUIDITY_OFFSET + 1;
    uint256 public constant AGGREGATE_SWAP_FEE_OFFSET = STATIC_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant AGGREGATE_YIELD_FEE_OFFSET = AGGREGATE_SWAP_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant DECIMAL_SCALING_FACTORS_OFFSET = AGGREGATE_YIELD_FEE_OFFSET + FEE_BITLENGTH;
    uint256 public constant PAUSE_WINDOW_END_TIME_OFFSET =
        DECIMAL_SCALING_FACTORS_OFFSET + TOKEN_DECIMAL_DIFFS_BITLENGTH;

    // Uses a uint40 to pack the values: 8 tokens * 5 bits/token.
    // This maximum token count is also hard-coded in the Vault.
    uint8 public constant TOKEN_DECIMAL_DIFFS_BITLENGTH = 40;
    uint8 public constant DECIMAL_DIFF_BITLENGTH = 5;

    uint8 public constant TIMESTAMP_BITLENGTH = 32;
}
