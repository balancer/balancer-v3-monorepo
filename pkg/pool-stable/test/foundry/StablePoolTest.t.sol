// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

contract StablePoolTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testItWorks() public {
        assertTrue(true);
    }
}
