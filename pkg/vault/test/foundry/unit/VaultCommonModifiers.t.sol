pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonModifiersTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*******************************************************************************
                                      withOpenTab
    *******************************************************************************/

    function testClosedTab() public {
        vault.manualSetOpenTab(false);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.TabIsNotOpen.selector));
        vault.mockWithOpenTab();
    }

    function testOpenTab() public {
        vault.manualSetOpenTab(true);

        // If function does not revert, test passes
        vault.mockWithOpenTab();
    }

    /*******************************************************************************
                                 WithInitializedPool
    *******************************************************************************/

    function testUninitializedPool() public {
        vault.manualSetInitializedPool(address(pool), false);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, address(pool)));
        vault.mockWithInitializedPool(address(pool));
    }

    function testInitializedPool() public {
        vault.manualSetInitializedPool(address(pool), true);
        // If function does not revert, test passes
        vault.mockWithInitializedPool(address(pool));
    }
}
