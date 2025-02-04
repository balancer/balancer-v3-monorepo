// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract LBPoolFactoryTest is BaseLBPTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    function testGetPoolVersion() public view {
        assertEq(lbPoolFactory.getPoolVersion(), poolVersion, "Pool version mismatch");
    }

    function testGetTrustedRouter() public view {
        assertEq(lbPoolFactory.getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testGetTrustedFactory() public view {
        assertEq(LBPool(pool).getTrustedFactory(), address(lbPoolFactory), "Wrong trusted factory");
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = lbPoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testCreatePool() public view {
        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");
    }

    function testAddingLiquidityNotAllowed() public {
        // Try to add liquidity to the pool
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        // Try to donate to the pool
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.donate(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testSetSwapFeeNoPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(pool, 2.5e16);
    }

    function testSetSwapFee() public {
        uint256 newSwapFee = 2.5e16; // 2.5%

        // Starts out at the default
        assertEq(vault.getStaticSwapFeePercentage(pool), swapFee);

        vm.prank(bob);
        vault.setStaticSwapFeePercentage(pool, newSwapFee);

        assertEq(vault.getStaticSwapFeePercentage(pool), newSwapFee);
    }
}
