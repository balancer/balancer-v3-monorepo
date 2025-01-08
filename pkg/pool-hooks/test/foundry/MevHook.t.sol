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
            IAuthentication(address(_mevHook)).getActionId(IMevHook.setDefaultMevTaxMultiplier.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(address(_mevHook)).getActionId(IMevHook.setPoolMevTaxMultiplier.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(address(_mevHook)).getActionId(IMevHook.setDefaultMevTaxThreshold.selector),
            admin
        );
        authorizer.grantRole(
            IAuthentication(address(_mevHook)).getActionId(IMevHook.setPoolMevTaxThreshold.selector),
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
                   getDefaultMevTaxMultiplier()
    ********************************************************/
    function testGetDefaultMevTaxMultiplierStartingState() public {
        assertEq(_mevHook.getDefaultMevTaxMultiplier(), 0, "Default Mev Tax Multiplier is not 0 after hook creation.");
    }

    /********************************************************
                   setDefaultMevTaxMultiplier()
    ********************************************************/
    function testSetDefaultMevTaxMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.setDefaultMevTaxMultiplier(1e18);
    }

    function testSetDefaultMevTaxMultiplier() public {
        uint256 firstDefaultMevTaxMultiplier = _mevHook.getDefaultMevTaxMultiplier();

        uint256 newDefaultMevTaxMultiplier = 1e18;

        assertNotEq(
            firstDefaultMevTaxMultiplier,
            newDefaultMevTaxMultiplier,
            "New defaultMevTaxMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        _mevHook.setDefaultMevTaxMultiplier(newDefaultMevTaxMultiplier);
        assertEq(
            _mevHook.getDefaultMevTaxMultiplier(),
            newDefaultMevTaxMultiplier,
            "defaultMevTaxMultiplier is not correct"
        );
    }

    /********************************************************
                   getDefaultMevTaxThreshold()
    ********************************************************/
    function testGetDefaultMevTaxThresholdStartingState() public {
        assertEq(_mevHook.getDefaultMevTaxThreshold(), 0, "Default Mev Tax Threshold is not 0 after hook creation.");
    }

    /********************************************************
                   setDefaultMevTaxThreshold()
    ********************************************************/
    function testSetDefaultMevTaxThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.setDefaultMevTaxThreshold(1e18);
    }

    function testSetDefaultMevTaxThreshold() public {
        uint256 firstDefaultMevTaxThreshold = _mevHook.getDefaultMevTaxThreshold();

        uint256 newDefaultMevTaxThreshold = 1e18;

        assertNotEq(
            firstDefaultMevTaxThreshold,
            newDefaultMevTaxThreshold,
            "New defaultMevTaxThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        _mevHook.setDefaultMevTaxThreshold(newDefaultMevTaxThreshold);
        assertEq(
            _mevHook.getDefaultMevTaxThreshold(),
            newDefaultMevTaxThreshold,
            "defaultMevTaxThreshold is not correct"
        );
    }
}
