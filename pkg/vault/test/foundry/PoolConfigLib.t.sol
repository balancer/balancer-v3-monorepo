// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { PoolConfig, PoolConfigBits, PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";

contract PoolConfigLibTest is Test {
    // 16 flags + 2 * 24 bit fee + 24 bit token diffs + 2 * 32 bit timestamps = 152 total bits used.
    uint256 private constant CONFIG_MSB = 152;

    function testToAndFromConfigBits__Fuzz(uint256 rawConfigInt) public {
        rawConfigInt = bound(rawConfigInt, 0, uint256(1 << CONFIG_MSB) - 1);
        bytes32 rawConfig = bytes32(rawConfigInt);
        PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(rawConfig));
        bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

        assertEq(rawConfig, configBytes32);
    }

    function testUnusedConfigBits() public {
        bytes32 unusedBits = bytes32(uint256(type(uint256).max << (CONFIG_MSB + 1)));

        PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(unusedBits));
        bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

        assertEq(bytes32(0), configBytes32);
    }
}
