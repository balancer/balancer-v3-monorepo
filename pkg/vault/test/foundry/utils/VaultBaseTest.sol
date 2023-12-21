// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { BaseTest } from "solidity-utils/test/foundry/utils/BaseTest.t.sol";

abstract contract VaultBaseTest is BaseTest {
    function setUp() public virtual override {
        BaseTest.setUp();
    }
}
