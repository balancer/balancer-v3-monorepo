// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {
    IBalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { BalancerContractRegistry } from "../../contracts/BalancerContractRegistry.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

contract BalancerContractRegistryTest is BaseVaultTest {
    address private constant ANY_ADDRESS = 0x388C818CA8B9251b393131C08a736A67ccB19297;
    address private constant SECOND_ADDRESS = 0x26c212f06675a0149909030D15dc46DAEE9A1f8a;
    address private constant ZERO_ADDRESS = address(0);
    string private constant DEFAULT_NAME = "Contract";

    BalancerContractRegistry private registry;

    function setUp() public override {
        BaseVaultTest.setUp();

        registry = new BalancerContractRegistry(vault);

        // Grant permissions.
        authorizer.grantRole(registry.getActionId(BalancerContractRegistry.registerBalancerContract.selector), admin);
        authorizer.grantRole(registry.getActionId(BalancerContractRegistry.deprecateBalancerContract.selector), admin);
        authorizer.grantRole(registry.getActionId(BalancerContractRegistry.replaceBalancerContract.selector), admin);
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

    function testValidRegistration() public {
        vm.prank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        // Should return the registered contract as active.
        assertTrue(registry.isActiveBalancerContract(ContractType.POOL_FACTORY, ANY_ADDRESS));
        // Zero address should not be active.
        assertFalse(registry.isActiveBalancerContract(ContractType.POOL_FACTORY, ZERO_ADDRESS));
        // Random address should not be active.
        assertFalse(registry.isActiveBalancerContract(ContractType.POOL_FACTORY, SECOND_ADDRESS));
        // Only active with the correct type.
        assertFalse(registry.isActiveBalancerContract(ContractType.ROUTER, ANY_ADDRESS));

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS);
        assertTrue(active);
    }

    function testValidRegistrationEmitsEvent() public {
        vm.prank(admin);

        vm.expectEmit();
        emit IBalancerContractRegistry.BalancerContractRegistered(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
    }

    function testDeprecateNonExistentContract() public {
        vm.prank(admin);

        vm.expectRevert(IBalancerContractRegistry.ContractNotRegistered.selector);
        registry.deprecateBalancerContract(ZERO_ADDRESS);
    }

    function testValidDeprecation() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS);
        assertTrue(active);

        registry.deprecateBalancerContract(ANY_ADDRESS);
        vm.stopPrank();

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS);
        assertFalse(active);
    }

    function testDeprecationEmitsEvent() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        vm.expectEmit();
        emit IBalancerContractRegistry.BalancerContractDeprecated(ANY_ADDRESS);

        registry.deprecateBalancerContract(ANY_ADDRESS);
        vm.stopPrank();
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

    function testDeprecationOfOverloadedNames() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, "WeightedPool", ANY_ADDRESS);

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS);
        assertTrue(active);

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, "WeightedPool");
        assertEq(contractAddress, ANY_ADDRESS);
        assertTrue(active);

        registry.deprecateBalancerContract(ANY_ADDRESS);
        vm.stopPrank();

        // Deprecate the address, and all aliases show as inactive.
        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, ANY_ADDRESS);
        assertFalse(active);

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, "WeightedPool");
        assertEq(contractAddress, ANY_ADDRESS);
        assertFalse(active);
    }

    function testReplacementWithInvalidContract() public {
        vm.prank(admin);

        vm.expectRevert(IBalancerContractRegistry.ZeroContractAddress.selector);
        registry.replaceBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ZERO_ADDRESS);
    }

    function testReplacementOfInvalidContract() public {
        vm.prank(admin);

        vm.expectRevert(IBalancerContractRegistry.ContractNotRegistered.selector);
        registry.replaceBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);
    }

    function testValidSimpleReplacement() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        registry.deprecateBalancerContract(ANY_ADDRESS);
        registry.replaceBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, SECOND_ADDRESS);
        vm.stopPrank();

        (address contractAddress, bool active) = registry.getBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME);
        assertEq(contractAddress, SECOND_ADDRESS);
        assertTrue(active);

        assertTrue(registry.isActiveBalancerContract(ContractType.POOL_FACTORY, SECOND_ADDRESS));
        assertFalse(registry.isActiveBalancerContract(ContractType.POOL_FACTORY, ANY_ADDRESS));
    }

    function testReplacementEmitsEvent() public {
        vm.startPrank(admin);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, ANY_ADDRESS);

        vm.expectEmit();
        emit IBalancerContractRegistry.BalancerContractReplaced(
            ContractType.POOL_FACTORY,
            DEFAULT_NAME,
            ANY_ADDRESS,
            SECOND_ADDRESS
        );

        registry.replaceBalancerContract(ContractType.POOL_FACTORY, DEFAULT_NAME, SECOND_ADDRESS);
        vm.stopPrank();
    }

    function testComplexReplacement() public {
        vm.startPrank(admin);
        // Register addr1 as both a named version and generic factory.
        registry.registerBalancerContract(ContractType.POOL_FACTORY, "20241205-v3-weighted-pool", ANY_ADDRESS);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, "WeightedPool", ANY_ADDRESS);

        registry.deprecateBalancerContract(ANY_ADDRESS);
        registry.registerBalancerContract(ContractType.POOL_FACTORY, "20250107-v3-weighted-pool-v2", SECOND_ADDRESS);
        registry.replaceBalancerContract(ContractType.POOL_FACTORY, "WeightedPool", SECOND_ADDRESS);
        vm.stopPrank();

        (address contractAddress, bool active) = registry.getBalancerContract(
            ContractType.POOL_FACTORY,
            "20241205-v3-weighted-pool"
        );
        assertEq(contractAddress, ANY_ADDRESS);
        assertFalse(active);

        (contractAddress, active) = registry.getBalancerContract(
            ContractType.POOL_FACTORY,
            "20250107-v3-weighted-pool-v2"
        );
        assertEq(contractAddress, SECOND_ADDRESS);
        assertTrue(active);

        (contractAddress, active) = registry.getBalancerContract(ContractType.POOL_FACTORY, "WeightedPool");
        assertEq(contractAddress, SECOND_ADDRESS);
        assertTrue(active);
    }
}
