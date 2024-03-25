pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonModifiersTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*******************************************************************************
                                      WithUnlocker
    *******************************************************************************/

    function testEmptyUnlockers() public {
        address[] memory unlockers;
        vault.manualSetUnlockers(unlockers);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.NoUnlocker.selector));
        vault.mockWithUnlocker();
    }

    function testUnlockersWithWrongAddress() public {
        address[] memory unlockers = new address[](1);
        unlockers[0] = address(alice);
        vault.manualSetUnlockers(unlockers);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnlocker.selector, address(bob), address(alice)));
        vault.mockWithUnlocker();
    }

    function testUnlockersWithRightAddressInWrongPosition() public {
        address[] memory unlockers = new address[](2);
        unlockers[0] = address(bob);
        unlockers[1] = address(alice);
        vault.manualSetUnlockers(unlockers);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongUnlocker.selector, address(bob), address(alice)));
        vault.mockWithUnlocker();
    }

    function testUnlockersWithRightAddress() public {
        address[] memory unlockers = new address[](2);
        unlockers[0] = address(alice);
        unlockers[1] = address(bob);
        vault.manualSetUnlockers(unlockers);

        // If function does not revert, test passes
        vm.prank(bob);
        vault.mockWithUnlocker();
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
