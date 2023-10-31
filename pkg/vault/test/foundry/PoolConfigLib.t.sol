// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { PoolConfig, PoolConfigBits, PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";

contract VaultLiquidityTest is Test {

    uint256 private constant CONFIG_MSB = 14;

    function testToAndFromConfigBits(uint256 rawConfigInt) public {
        rawConfigInt = bound(rawConfigInt, 0, uint256(1 << CONFIG_MSB));
        bytes32 rawConfig = bytes32(rawConfigInt);
        PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(rawConfig));
        bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

        assertEq(rawConfig, configBytes32);
    }

    function testUnusedConfigBits() public {
        bytes32 rawConfig = bytes32(uint256(1 << (CONFIG_MSB + 1)));

        PoolConfig memory config = PoolConfigLib.toPoolConfig(PoolConfigBits.wrap(rawConfig));
        bytes32 configBytes32 = PoolConfigBits.unwrap(PoolConfigLib.fromPoolConfig(config));

        assertEq(bytes32(0), configBytes32);
    }
}