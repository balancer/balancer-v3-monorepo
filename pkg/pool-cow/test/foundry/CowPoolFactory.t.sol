// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";

import { CowPoolFactory } from "../../contracts/CowPoolFactory.sol";
import { BaseCowTest } from "./utils/BaseCowTest.sol";

contract CowPoolFactoryTest is BaseCowTest {
    // pool version returns correct value
    function testGetPoolVersion() public {
        assertEq(IPoolVersion(address(cowFactory)).getPoolVersion(), POOL_VERSION, "Pool version does not match");
    }

    // Trusted Router

    // get trusted router returns cowRouter
    function testGetTrustedRouter() public {
        assertEq(cowFactory.getTrustedCowRouter(), address(cowRouter), "Trusted Router is not CoW Router");
    }
    // setTrustedRouter is authenticated
    // setTrustedRouter sets the router to the given value

    // Create

    // create pool cannot receive poolCreator
    // Create pool has donations enabled and disabled unbalanced liquidity
    // Pool is created with correct arguments
    // Pool is registered with given arguments
}
