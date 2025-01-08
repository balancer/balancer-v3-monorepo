// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { MevHook } from "../../contracts/MevHook.sol";

contract MevHookTest is BaseVaultTest {
    IMevHook private _mevHook;

    function setUp() public override {
        super.setUp();

        authorizer.grantRole(IAuthentication(address(_mevHook)).getActionId(IMevHook.disableMevTax.selector), admin);
        authorizer.grantRole(IAuthentication(address(_mevHook)).getActionId(IMevHook.enableMevTax.selector), admin);
        authorizer.grantRole(
            IAuthentication(address(_mevHook)).getActionId(IMevHook.setMevTaxMultiplier.selector),
            admin
        );
    }

    function createHook() internal override returns (address) {
        address mevHook = address(new MevHook(IVault(address(vault))));
        _mevHook = IMevHook(mevHook);
        vm.label(mevHook, "Mev Hook");
        return mevHook;
    }

    /********************************************************
                       isMevTaxEnabled()
    ********************************************************/
    function testIsMevTaxEnabledStartingState() public {
        assertFalse(_mevHook.isMevTaxEnabled(), "Mev Tax is enabled after hook creation.");
    }

    /********************************************************
                         enableMevTax()
    ********************************************************/
    function testEnableMevTaxIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.enableMevTax();
    }

    function testEnableMevTax() public {
        assertFalse(_mevHook.isMevTaxEnabled(), "Mev Tax is enabled");
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "Mev Tax is not enabled");
    }

    function testMultipleEnableMevTax() public {
        assertFalse(_mevHook.isMevTaxEnabled(), "Mev Tax is enabled");
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "Mev Tax is not enabled");
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "Mev Tax is not enabled");
    }

    /********************************************************
                         disableMevTax()
    ********************************************************/
    function testDisableMevTaxIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.disableMevTax();
    }

    function testDisableMevTax() public {
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "Mev Tax is not enabled");
        vm.prank(admin);
        _mevHook.disableMevTax();
        assertFalse(_mevHook.isMevTaxEnabled(), "Mev Tax is enabled");
    }

    function testMultipleDisableMevTax() public {
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "Mev Tax is not enabled");
        vm.prank(admin);
        _mevHook.disableMevTax();
        assertFalse(_mevHook.isMevTaxEnabled(), "Mev Tax is enabled");
        vm.prank(admin);
        _mevHook.disableMevTax();
        assertFalse(_mevHook.isMevTaxEnabled(), "Mev Tax is enabled");
    }

    /********************************************************
                     getMevTaxMultiplier()
    ********************************************************/
    function testGetMevTaxMultiplierStartingState() public {
        assertEq(_mevHook.getMevTaxMultiplier(), 0, "Mev Tax Multiplier is not 0 after hook creation.");
    }

    /********************************************************
                     setMevTaxMultiplier()
    ********************************************************/
    function testSetMevTaxMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.setMevTaxMultiplier(1e18);
    }

    function testSetMevTaxMultiplier() public {
        uint256 firstMevTaxMultiplier = _mevHook.getMevTaxMultiplier();

        uint256 newMevTaxMultiplier = 1e18;

        assertNotEq(
            firstMevTaxMultiplier,
            newMevTaxMultiplier,
            "New MevTaxMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        _mevHook.setMevTaxMultiplier(newMevTaxMultiplier);
        assertEq(_mevHook.getMevTaxMultiplier(), newMevTaxMultiplier, "mevTaxMultiplier is not correct");
    }
}
