// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonModifiersTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*******************************************************************************
                                    onlyWhenUnlocked
    *******************************************************************************/

    function testLock() public {
        vault.manualSetIsUnlocked(false);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.mockIsUnlocked();
    }

    function testUnlock() public {
        vault.manualSetIsUnlocked(true);

        // If function does not revert, test passes
        vault.mockIsUnlocked();
    }

    /*******************************************************************************
                                 WithInitializedPool
    *******************************************************************************/

    function testUninitializedPool() public {
        vault.manualSetInitializedPool(pool, false);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, pool));
        vault.mockWithInitializedPool(pool);
    }

    function testInitializedPool() public {
        vault.manualSetInitializedPool(pool, true);
        // If function does not revert, test passes
        vault.mockWithInitializedPool(pool);
    }
}
