// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract LBPoolTest is BaseLBPTest {
    using ArrayHelpers for *;

    function testGetTrustedFactory() public view {
        assertEq(LBPool(pool).getTrustedFactory(), address(lbPoolFactory), "Wrong trusted factory");
    }

    function testAddingLiquidityNotAllowed() public {
        // Try to add liquidity to the pool.
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        // Try to donate to the pool.
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.donate(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }
}
