// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { FEE_BITLENGTH } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolConfigConst } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigConst.sol";

import { BaseBitsConfigTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseBitsConfigTest.sol";

contract PoolConfigConstTest is BaseBitsConfigTest {
    Bits[] bits;

    function testOffsets() public {
        bits.push(Bits(PoolConfigConst.POOL_REGISTERED_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.POOL_INITIALIZED_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.POOL_PAUSED_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.POOL_RECOVERY_MODE_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.ADD_LIQUIDITY_UNBALANCED_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.REMOVE_LIQUIDITY_UNBALANCED_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.ADD_LIQUIDITY_CUSTOM_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.REMOVE_LIQUIDITY_CUSTOM_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.DONATION_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.BEFORE_INITIALIZE_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_ADD_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_REMOVE_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.ENABLE_HOOK_ADJUSTED_AMOUNTS_SWAP_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.AFTER_INITIALIZE_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.DYNAMIC_SWAP_FEE_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.BEFORE_SWAP_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.AFTER_SWAP_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.BEFORE_ADD_LIQUIDITY_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.AFTER_ADD_LIQUIDITY_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.BEFORE_REMOVE_LIQUIDITY_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.AFTER_REMOVE_LIQUIDITY_OFFSET, 1));
        bits.push(Bits(PoolConfigConst.STATIC_SWAP_FEE_OFFSET, FEE_BITLENGTH));
        bits.push(Bits(PoolConfigConst.AGGREGATE_SWAP_FEE_OFFSET, FEE_BITLENGTH));
        bits.push(Bits(PoolConfigConst.AGGREGATE_YIELD_FEE_OFFSET, FEE_BITLENGTH));
        bits.push(Bits(PoolConfigConst.DECIMAL_SCALING_FACTORS_OFFSET, PoolConfigConst.TOKEN_DECIMAL_DIFFS_BITLENGTH));
        bits.push(Bits(PoolConfigConst.PAUSE_WINDOW_END_TIME_OFFSET, PoolConfigConst.TIMESTAMP_BITLENGTH));

        _checkBitsUsedOnce(bits);
    }

    function testRestConstants() public pure {
        assertEq(PoolConfigConst.TOKEN_DECIMAL_DIFFS_BITLENGTH, 40, "TOKEN_DECIMAL_DIFFS_BITLENGTH should be 40");
        assertEq(PoolConfigConst.DECIMAL_DIFF_BITLENGTH, 5, "DECIMAL_DIFF_BITLENGTH should be 5");
        assertEq(PoolConfigConst.TIMESTAMP_BITLENGTH, 32, "TIMESTAMP_BITLENGTH should be 32");
    }
}
