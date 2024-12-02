// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ActionIdsTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public override {
        BaseVaultTest.setUp();
    }

    function testActionIds() public {
        address pool1 = factoryMock.createPool("a", "a");
        address pool2 = factoryMock.createPool("b", "b");
        bytes4 selector = bytes4(keccak256(bytes("transfer(address,uint256)")));

        assertEq(
            IAuthentication(pool1).getActionId(selector),
            IAuthentication(pool2).getActionId(selector),
            "Action IDs do not match"
        );
    }
}
