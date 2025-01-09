// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import {
    IBalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-interfaces/contracts/vault/IBalancerContractRegistry.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { BalancerContractRegistry } from "../../contracts/BalancerContractRegistry.sol";

contract BalancerContractRegistryTest is BaseVaultTest {
    address private constant ANY_ADDRESS = 0x388C818CA8B9251b393131C08a736A67ccB19297;
    address private constant SECOND_ADDRESS = 0x26c212f06675a0149909030D15dc46DAEE9A1f8a;
    address private constant ZERO_ADDRESS = address(0);
    string private constant DEFAULT_NAME = "Contract name";
    string private constant DEFAULT_ALIAS = "Alias name";

    BalancerContractRegistry private registry;

    function setUp() public override {
        BaseVaultTest.setUp();

        registry = new BalancerContractRegistry(vault);

        // Grant permissions.
        authorizer.grantRole(registry.getActionId(BalancerContractRegistry.registerBalancerContract.selector), admin);
        authorizer.grantRole(registry.getActionId(BalancerContractRegistry.deregisterBalancerContract.selector), admin);
        authorizer.grantRole(registry.getActionId(BalancerContractRegistry.deprecateBalancerContract.selector), admin);
        authorizer.grantRole(
            registry.getActionId(BalancerContractRegistry.addOrUpdateBalancerContractAlias.selector),
            admin
        );
    }

    function testGetVault() public view {
        assertEq(address(registry.getVault()), address(vault), "Wrong Vault address");
    }

    function testRegisterWithoutPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
    }

    function testRegisterWithBadAddress() public {
        vm.prank(admin);

        vm.expectRevert(IBalancerContractRegistry.ZeroContractAddress.selector);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ZERO_ADDRESS);
    }

    function testRegisterWithBadName() public {
        vm.prank(admin);

        vm.expectRevert(IBalancerContractRegistry.InvalidContractName.selector);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, "", ANY_ADDRESS);
    }

    function testDuplicateRegistration() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        // Try to register the same address under a different name (must use aliases for this).
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerContractRegistry.AddressAlreadyRegistered.selector,
                ContractType.POOL_FACTORY,
                ANY_ADDRESS
            )
        );
        registry.registerBalancerContract(ContractType.POOL_FACTORY, "Different Name", ANY_ADDRESS);
        vm.stopPrank();
    }

    function testRegistrationUsingAliasName() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
        registry.addOrUpdateBalancerContractAlias(DEFAULT_ALIAS, ANY_ADDRESS);

        // Try to register a new address with a contract name that is already used as an alias.
        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerContractRegistry.ContractAlreadyRegistered.selector,
                ContractType.POOL_FACTORY,
                DEFAULT_ALIAS
            )
        );
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_ALIAS, SECOND_ADDRESS);
        vm.stopPrank();
    }

    function testValidRegistration() public {
        vm.prank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        // Should return the registered contract as active.
        assertTrue(
            registry.isActiveBalancerContract(ContractType.POOL_FACTORY, ANY_ADDRESS),
            "ANY_ADDRESS is not active"
        );
        // Zero address should not be active.
        assertFalse(
            registry.isActiveBalancerContract(ContractType.POOL_FACTORY, ZERO_ADDRESS),
            "ZERO_ADDRESS is active"
        );
        // Random address should not be active.
        assertFalse(
            registry.isActiveBalancerContract(ContractType.POOL_FACTORY, SECOND_ADDRESS),
            "SECOND_ADDRESS is active"
        );
        // Only active with the correct type.
        assertFalse(
            registry.isActiveBalancerContract(ContractType.ROUTER, ANY_ADDRESS),
            "Address is active as a Router"
        );
    }

    function testContractGetters() public {
        vm.prank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong contract address");
        assertTrue(active, "Contract not active");

        IBalancerContractRegistry.ContractInfo memory info = registry.getBalancerContractInfo(ANY_ADDRESS);
        assertEq(uint8(info.contractType), uint8(ContractType.POOL_FACTORY), "Wrong contract type");
        assertTrue(info.isRegistered, "Contract not registered");
        assertTrue(info.isActive, "Contract not active");

        // Random address will have no data.
        info = registry.getBalancerContractInfo(SECOND_ADDRESS);
        // 0 will be "Other".
        assertEq(uint8(info.contractType), uint8(ContractType.OTHER), "Wrong contract type");
        assertFalse(info.isRegistered, "Contract registered");
        assertFalse(info.isActive, "Contract active");
    }

    function testBufferRegistration() public {
        vm.prank(admin);
        registry.registerBalancerContract(ContractType.ERC4626, DEFAULT_NAME, ANY_ADDRESS);

        // Should return the registered contract as active.
        assertTrue(registry.isActiveBalancerContract(ContractType.ERC4626, ANY_ADDRESS), "ANY_ADDRESS is not a Buffer");
        assertFalse(registry.isActiveBalancerContract(ContractType.ROUTER, ANY_ADDRESS), "ANY_ADDRESS is a Router");
    }

    function testValidRegistrationEmitsEvent() public {
        vm.expectEmit();
        emit IBalancerContractRegistry.BalancerContractRegistered(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        vm.prank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
    }

    function testDeregisterNonExistentContract() public {
        vm.prank(admin);

        vm.expectRevert(IBalancerContractRegistry.ContractNotRegistered.selector);
        registry.deregisterBalancerContract(DEFAULT_NAME);
    }

    function testValidDeregistration() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.ROUTER, DEFAULT_NAME, ANY_ADDRESS);
        assertTrue(registry.isActiveBalancerContract(ContractType.ROUTER, ANY_ADDRESS), "ANY_ADDRESS is not active");

        registry.deregisterBalancerContract(DEFAULT_NAME);
        vm.stopPrank();

        assertFalse(registry.isActiveBalancerContract(ContractType.ROUTER, ANY_ADDRESS), "ANY_ADDRESS is still active");

        IBalancerContractRegistry.ContractInfo memory info = registry.getBalancerContractInfo(ANY_ADDRESS);
        assertFalse(info.isRegistered, "Contract is still registered");
    }

    function testDeregistrationEmitsEvent() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.ROUTER, DEFAULT_NAME, ANY_ADDRESS);
        assertTrue(registry.isActiveBalancerContract(ContractType.ROUTER, ANY_ADDRESS), "ANY_ADDRESS is not active");

        vm.expectEmit();
        emit IBalancerContractRegistry.BalancerContractDeregistered(ContractType.ROUTER, DEFAULT_NAME, ANY_ADDRESS);

        registry.deregisterBalancerContract(DEFAULT_NAME);
        vm.stopPrank();
    }

    function testDeprecateNonExistentContract() public {
        vm.prank(admin);

        vm.expectRevert(IBalancerContractRegistry.ContractNotRegistered.selector);
        registry.deprecateBalancerContract(ZERO_ADDRESS);
    }

    function testDoubleDeprecation() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        registry.deprecateBalancerContract(ANY_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(IBalancerContractRegistry.ContractAlreadyDeprecated.selector, ANY_ADDRESS)
        );
        registry.deprecateBalancerContract(ANY_ADDRESS);

        vm.stopPrank();
    }

    function testValidDeprecation() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong active contract address");
        assertTrue(active, "Contract is not active");

        registry.deprecateBalancerContract(ANY_ADDRESS);
        vm.stopPrank();

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong deprecated contract address");
        assertFalse(active, "Deprecated contract is active");
    }

    function testDeprecationEmitsEvent() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        vm.expectEmit();
        emit IBalancerContractRegistry.BalancerContractDeprecated(ANY_ADDRESS);

        registry.deprecateBalancerContract(ANY_ADDRESS);
        vm.stopPrank();
    }

    function testDeprecationWithAliases() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
        registry.addOrUpdateBalancerContractAlias(DEFAULT_ALIAS, ANY_ADDRESS);

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong default address");
        assertTrue(active, "Default contract is not active");

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_ALIAS);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong WeightedPool address");
        assertTrue(active, "Canonical contract is not active");

        registry.deprecateBalancerContract(ANY_ADDRESS);
        vm.stopPrank();

        // Deprecate the address, and all aliases show as inactive.
        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong deprecated default address");
        assertFalse(active, "Deprecated default contract is active");

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_ALIAS);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong deprecated WeightedPool address");
        assertFalse(active, "Deprecated canonical contract is active");
    }

    function testInvalidAliasName() public {
        vm.expectRevert(IBalancerContractRegistry.InvalidContractName.selector);
        vm.prank(admin);
        registry.addOrUpdateBalancerContractAlias("", ANY_ADDRESS);
    }

    function testInvalidAliasAddress() public {
        vm.expectRevert(IBalancerContractRegistry.ZeroContractAddress.selector);
        vm.prank(admin);
        registry.addOrUpdateBalancerContractAlias(DEFAULT_ALIAS, ZERO_ADDRESS);
    }

    function testAliasForUnregistered() public {
        vm.expectRevert(IBalancerContractRegistry.ContractNotRegistered.selector);
        vm.prank(admin);
        registry.addOrUpdateBalancerContractAlias(DEFAULT_ALIAS, ANY_ADDRESS);
    }

    function testAliasNameCollision() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        vm.expectRevert(
            abi.encodeWithSelector(
                IBalancerContractRegistry.ContractAlreadyRegistered.selector,
                ContractType.POOL_FACTORY,
                DEFAULT_NAME
            )
        );
        registry.addOrUpdateBalancerContractAlias(DEFAULT_NAME, ANY_ADDRESS);
        vm.stopPrank();
    }

    function testValidAlias() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
        registry.addOrUpdateBalancerContractAlias(DEFAULT_ALIAS, ANY_ADDRESS);

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong default address");
        assertTrue(active, "Default contract is not active");

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_ALIAS);
        assertEq(contractAddress, ANY_ADDRESS, "Wrong alias address");
        assertTrue(active, "Alias is not active");
    }
}
