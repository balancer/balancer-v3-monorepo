// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IMevRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IMevRouter.sol";
import { IMevTaxCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IMevTaxCollector.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract MevRouterTest is BaseVaultTest {
    function setUp() public override {
        super.setUp();

        authorizer.grantRole(mevRouter.getActionId(IMevRouter.disableMevTax.selector), admin);
        authorizer.grantRole(mevRouter.getActionId(IMevRouter.enableMevTax.selector), admin);
        authorizer.grantRole(mevRouter.getActionId(IMevRouter.setMevTaxCollector.selector), admin);
    }

    function testDisableMevTax() public {
        assertTrue(mevRouter.isMevTaxEnabled(), "Mev Tax is not enabled");
        vm.prank(admin);
        mevRouter.disableMevTax();
        assertFalse(mevRouter.isMevTaxEnabled(), "Mev Tax is not disabled");
    }

    function testMultipleDisableMevTax() public {
        assertTrue(mevRouter.isMevTaxEnabled(), "Mev Tax is not enabled");
        vm.prank(admin);
        mevRouter.disableMevTax();
        assertFalse(mevRouter.isMevTaxEnabled(), "Mev Tax is not disabled");
        vm.prank(admin);
        mevRouter.disableMevTax();
        assertFalse(mevRouter.isMevTaxEnabled(), "Mev Tax is not disabled");
    }

    function testDisableMevTaxIsAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        mevRouter.disableMevTax();
    }

    function testEnableMevTax() public {
        vm.prank(admin);
        mevRouter.disableMevTax();
        assertFalse(mevRouter.isMevTaxEnabled(), "Mev Tax is not disabled");
        vm.prank(admin);
        mevRouter.enableMevTax();
        assertTrue(mevRouter.isMevTaxEnabled(), "Mev Tax is not enabled");
    }

    function testMultipleEnableMevTax() public {
        vm.prank(admin);
        mevRouter.disableMevTax();
        assertFalse(mevRouter.isMevTaxEnabled(), "Mev Tax is not disabled");
        vm.prank(admin);
        mevRouter.enableMevTax();
        assertTrue(mevRouter.isMevTaxEnabled(), "Mev Tax is not enabled");
        vm.prank(admin);
        mevRouter.enableMevTax();
        assertTrue(mevRouter.isMevTaxEnabled(), "Mev Tax is not enabled");
    }

    function testEnableMevTaxIsAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        mevRouter.enableMevTax();
    }

    function testSetMevTaxCollector() public {
        address firstCollector = address(mevRouter.getMevTaxCollector());
        assertNotEq(firstCollector, address(0), "MevTaxCollector is not set");

        address newMevTaxCollector = address(1);
        assertNotEq(firstCollector, newMevTaxCollector, "MevTaxCollector and NewMevTaxCollector matches");

        vm.prank(admin);
        mevRouter.setMevTaxCollector(IMevTaxCollector(newMevTaxCollector));
        assertEq(address(mevRouter.getMevTaxCollector()), newMevTaxCollector, "MevTaxCollector did not change");
    }

    function testSetMevTaxCollectorIsAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        mevRouter.setMevTaxCollector(IMevTaxCollector(address(1)));
    }
}
