// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { MevHook } from "../../contracts/MevHook.sol";

contract MevHookTest is BaseVaultTest {
    using CastingHelpers for address[];

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

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        newPool = PoolFactoryMock(poolFactory).createPool(name, symbol);
        vm.label(newPool, label);

        // Disable Unbalanced Liquidity because pool supports dynamic fee.
        PoolFactoryMock(poolFactory).registerTestPoolDisableUnbalancedLiquidity(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            poolHooksContract,
            lp
        );

        poolArgs = abi.encode(vault, name, symbol);
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
    function testIsMevTaxEnabledStartingState() public view {
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
    function testGetDefaultMevTaxMultiplierStartingState() public view {
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

    function testSetDefaultMevTaxMultiplierRegisteredPool() public {
        vm.prank(admin);
        _mevHook.setPoolMevTaxMultiplier(pool, 5e18);

        vm.prank(admin);
        _mevHook.setDefaultMevTaxMultiplier(1e18);

        assertNotEq(
            _mevHook.getDefaultMevTaxMultiplier(),
            _mevHook.getPoolMevTaxMultiplier(pool),
            "setDefaultMevTaxMultiplier changed pool multiplier."
        );
    }

    /********************************************************
                   getDefaultMevTaxThreshold()
    ********************************************************/
    function testGetDefaultMevTaxThresholdStartingState() public view {
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

    function testSetDefaultMevTaxThresholdRegisteredPool() public {
        vm.prank(admin);
        _mevHook.setPoolMevTaxThreshold(pool, 5e18);

        vm.prank(admin);
        _mevHook.setDefaultMevTaxThreshold(1e18);

        assertNotEq(
            _mevHook.getDefaultMevTaxThreshold(),
            _mevHook.getPoolMevTaxThreshold(pool),
            "setDefaultMevTaxThreshold changed pool threshold."
        );
    }

    /********************************************************
                   getPoolMevTaxMultiplier()
    ********************************************************/
    function testGetPoolMevTaxMultiplierPoolNotRegistered() public {
        // Creates a new mevHook and stores into _mevHook, so the pool won't be registered with the new MevHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevHook.MevHookNotRegisteredInPool.selector, pool));
        _mevHook.getPoolMevTaxMultiplier(pool);
    }

    /********************************************************
                   setPoolMevTaxMultiplier()
    ********************************************************/
    function testSetPoolMevTaxMultiplierPoolNotRegistered() public {
        // Creates a new mevHook and stores into _mevHook, so the pool won't be registered with the new MevHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevHook.MevHookNotRegisteredInPool.selector, pool));
        _mevHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    function testSetPoolMevTaxMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    function testSetPoolMevTaxMultiplier() public {
        uint256 firstPoolMevTaxMultiplier = _mevHook.getPoolMevTaxMultiplier(pool);
        uint256 firstDefaultMevTaxMultiplier = _mevHook.getDefaultMevTaxMultiplier();

        uint256 newPoolMevTaxMultiplier = 5e18;

        assertNotEq(
            firstPoolMevTaxMultiplier,
            newPoolMevTaxMultiplier,
            "New defaultMevTaxMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        _mevHook.setPoolMevTaxMultiplier(pool, newPoolMevTaxMultiplier);
        assertEq(
            _mevHook.getPoolMevTaxMultiplier(pool),
            newPoolMevTaxMultiplier,
            "poolMevTaxMultiplier is not correct"
        );

        assertEq(_mevHook.getDefaultMevTaxMultiplier(), firstDefaultMevTaxMultiplier, "Default multiplier changed");
    }

    /********************************************************
                   getPoolMevTaxThreshold()
    ********************************************************/
    function testGetPoolMevTaxThresholdPoolNotRegistered() public {
        // Creates a new mevHook and stores into _mevHook, so the pool won't be registered with the new MevHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevHook.MevHookNotRegisteredInPool.selector, pool));
        _mevHook.getPoolMevTaxThreshold(pool);
    }

    /********************************************************
                   setPoolMevTaxThreshold()
    ********************************************************/
    function testSetPoolMevTaxThresholdPoolNotRegistered() public {
        // Creates a new mevHook and stores into _mevHook, so the pool won't be registered with the new MevHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevHook.MevHookNotRegisteredInPool.selector, pool));
        _mevHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThreshold() public {
        uint256 firstPoolMevTaxThreshold = _mevHook.getPoolMevTaxThreshold(pool);
        uint256 firstDefaultMevTaxThreshold = _mevHook.getDefaultMevTaxThreshold();

        uint256 newPoolMevTaxThreshold = 5e18;

        assertNotEq(
            firstPoolMevTaxThreshold,
            newPoolMevTaxThreshold,
            "New defaultMevTaxThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        _mevHook.setPoolMevTaxThreshold(pool, newPoolMevTaxThreshold);
        assertEq(_mevHook.getPoolMevTaxThreshold(pool), newPoolMevTaxThreshold, "poolMevTaxThreshold is not correct");

        assertEq(_mevHook.getDefaultMevTaxThreshold(), firstDefaultMevTaxThreshold, "Default threshold changed");
    }
}
