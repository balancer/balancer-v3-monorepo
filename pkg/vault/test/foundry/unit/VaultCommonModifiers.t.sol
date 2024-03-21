pragma solidity ^0.8.4;

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonModifiersTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*******************************************************************************
                                      WithLocker
    *******************************************************************************/

    function testEmptyLockers() public {
        address[] memory lockers;
        vault.manualSetLockers(lockers);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.NoLocker.selector));
        vault.mockWithLocker();
    }

    function testLockersWithWrongAddress() public {
        address[] memory lockers = new address[](1);
        lockers[0] = address(alice);
        vault.manualSetLockers(lockers);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongLocker.selector, address(bob), address(alice)));
        vm.prank(bob);
        vault.mockWithLocker();
    }

    function testLockersWithRightAddressInWrongPosition() public {
        address[] memory lockers = new address[](2);
        lockers[0] = address(bob);
        lockers[1] = address(alice);
        vault.manualSetLockers(lockers);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongLocker.selector, address(bob), address(alice)));
        vm.prank(bob);
        vault.mockWithLocker();
    }

    function testLockersWithRightAddress() public {
        address[] memory lockers = new address[](2);
        lockers[0] = address(alice);
        lockers[1] = address(bob);
        vault.manualSetLockers(lockers);
        vm.prank(bob);
        vault.mockWithLocker();
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
        vault.mockWithInitializedPool(address(pool));
    }
}
