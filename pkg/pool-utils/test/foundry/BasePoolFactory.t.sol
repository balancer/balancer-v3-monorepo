// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { BasePoolFactoryMock } from "../../contracts/test/BasePoolFactoryMock.sol";

contract BasePoolFactoryTest is BaseVaultTest {
    BasePoolFactoryMock internal testFactory;

    function setUp() public override {
        BaseVaultTest.setUp();

        testFactory = new BasePoolFactoryMock(IVault(address(vault)), 365 days, type(PoolMock).creationCode);
    }

    function testConstructor() public {
        bytes memory creationCode = type(PoolMock).creationCode;
        uint32 pauseWindowDuration = 365 days;

        BasePoolFactoryMock newFactory = new BasePoolFactoryMock(
            IVault(address(vault)),
            pauseWindowDuration,
            creationCode
        );

        assertEq(newFactory.getPauseWindowDuration(), pauseWindowDuration, "pauseWindowDuration is wrong");
        assertEq(newFactory.getCreationCode(), creationCode, "creationCode is wrong");
        assertEq(address(newFactory.getVault()), address(vault), "Vault is wrong");
    }

    function testDisableNoAuthentication() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        testFactory.disable();
    }

    function testDisable() public {
        authorizer.grantRole(testFactory.getActionId(IBasePoolFactory.disable.selector), admin);

        assertFalse(testFactory.isDisabled(), "Factory is disabled");

        vm.prank(admin);
        testFactory.disable();

        assertTrue(testFactory.isDisabled(), "Factory is enabled");
    }

    function testEnsureEnabled() public {
        authorizer.grantRole(testFactory.getActionId(IBasePoolFactory.disable.selector), admin);

        assertFalse(testFactory.isDisabled(), "Factory is disabled");
        // Should pass, since factory is enabled.
        testFactory.manualEnsureEnabled();

        vm.prank(admin);
        testFactory.disable();

        // Should revert, since factory is disabled.
        vm.expectRevert(IBasePoolFactory.Disabled.selector);
        testFactory.manualEnsureEnabled();
    }

    // _registerPoolWithFactory
    // isPoolFromFactory
    // _registerPoolWithVault

    // _create
    // getDeploymentAddress

    // getDefaultPoolHooksContract()
    // getDefaultLiquidityManagement()
}
