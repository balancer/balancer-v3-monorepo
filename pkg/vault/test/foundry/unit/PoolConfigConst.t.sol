// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FEE_BITLENGTH } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolConfigConst } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigConst.sol";

import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

contract PoolConfigConstTest is BaseBitsConfigTest {
    function testOffsets() public {
        _checkBitsUsedOnce(PoolConfigConst.POOL_REGISTERED_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.POOL_INITIALIZED_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.POOL_PAUSED_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.POOL_RECOVERY_MODE_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.UNBALANCED_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.ADD_LIQUIDITY_CUSTOM_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.REMOVE_LIQUIDITY_CUSTOM_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.DONATION_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.BEFORE_INITIALIZE_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.AFTER_INITIALIZE_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.DYNAMIC_SWAP_FEE_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.BEFORE_SWAP_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.AFTER_SWAP_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.BEFORE_ADD_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.AFTER_ADD_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.BEFORE_REMOVE_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.AFTER_REMOVE_LIQUIDITY_OFFSET);
        _checkBitsUsedOnce(PoolConfigConst.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigConst.AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(PoolConfigConst.AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH);
        _checkBitsUsedOnce(
            PoolConfigConst.DECIMAL_SCALING_FACTORS_OFFSET,
            PoolConfigConst.TOKEN_DECIMAL_DIFFS_BITLENGTH
        );
        _checkBitsUsedOnce(PoolConfigConst.PAUSE_WINDOW_END_TIME_OFFSET, PoolConfigConst.TIMESTAMP_BITLENGTH);
    }
}
