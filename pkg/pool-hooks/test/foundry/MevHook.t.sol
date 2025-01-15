// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolSwapParams, MAX_FEE_PERCENTAGE } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
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
            IAuthentication(address(_mevHook)).getActionId(IMevHook.setMaxMevSwapFeePercentage.selector),
            admin
        );
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

        // Pool supports unbalanced liquidity even if technically the dynamic fee above static fee because it blocks
        // unbalanced liquidity operations when that happens.
        PoolFactoryMock(poolFactory).registerPoolWithHook(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            poolHooksContract
        );

        poolArgs = abi.encode(vault, name, symbol);
    }

    function createHook() internal override returns (address) {
        address mevHook = address(new MevHook(IVault(address(vault))));
        _mevHook = IMevHook(mevHook);
        vm.label(mevHook, "MEV Hook");
        return mevHook;
    }

    /********************************************************
                       isMevTaxEnabled()
    ********************************************************/
    function testIsMevTaxEnabledStartingState() public view {
        assertFalse(_mevHook.isMevTaxEnabled(), "MEV Tax is enabled after hook creation.");
    }

    /********************************************************
                         enableMevTax()
    ********************************************************/
    function testEnableMevTaxIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.enableMevTax();
    }

    function testEnableMevTax() public {
        assertFalse(_mevHook.isMevTaxEnabled(), "MEV Tax is enabled");
        vm.prank(admin);
        vm.expectEmit();
        emit IMevHook.MevTaxEnabledSet(true);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "MEV Tax is not enabled");
    }

    function testMultipleEnableMevTax() public {
        assertFalse(_mevHook.isMevTaxEnabled(), "MEV Tax is enabled");
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "MEV Tax is not enabled");
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "MEV Tax is not enabled");
    }

    /********************************************************
                    getMaxMevSwapFeePercentage()
    ********************************************************/
    function getMaxMevSwapFeePercentage() public view {
        assertEq(_mevHook.getMaxMevSwapFeePercentage(), MAX_FEE_PERCENTAGE, "Incorrect initial max mev fee percentage");
    }

    /********************************************************
                   setMaxMevSwapFeePercentage()
    ********************************************************/
    function testSetMaxMevSwapFeePercentageIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevHook.setMaxMevSwapFeePercentage(50e16);
    }

    function testSetMaxMevSwapFeePercentageAboveMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IMevHook.MevSwapFeePercentageAboveMax.selector,
                MAX_FEE_PERCENTAGE + 1,
                MAX_FEE_PERCENTAGE
            )
        );
        vm.prank(admin);
        _mevHook.setMaxMevSwapFeePercentage(MAX_FEE_PERCENTAGE + 1);
    }

    function testSetMaxMevSwapFeePercentage() public {
        uint256 newMaxMevSwapFeePercentage = 50e16;
        assertEq(_mevHook.getMaxMevSwapFeePercentage(), MAX_FEE_PERCENTAGE, "Incorrect initial max mev fee percentage");
        vm.prank(admin);
        vm.expectEmit();
        emit IMevHook.MaxMevSwapFeePercentageSet(newMaxMevSwapFeePercentage);
        _mevHook.setMaxMevSwapFeePercentage(newMaxMevSwapFeePercentage);
        assertEq(
            _mevHook.getMaxMevSwapFeePercentage(),
            newMaxMevSwapFeePercentage,
            "Incorrect new max mev fee percentage"
        );
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
        assertTrue(_mevHook.isMevTaxEnabled(), "MEV Tax is not enabled");

        vm.prank(admin);
        vm.expectEmit();
        emit IMevHook.MevTaxEnabledSet(false);
        _mevHook.disableMevTax();
        assertFalse(_mevHook.isMevTaxEnabled(), "MEV Tax is enabled");
    }

    function testMultipleDisableMevTax() public {
        vm.prank(admin);
        _mevHook.enableMevTax();
        assertTrue(_mevHook.isMevTaxEnabled(), "MEV Tax is not enabled");
        vm.prank(admin);
        _mevHook.disableMevTax();
        assertFalse(_mevHook.isMevTaxEnabled(), "MEV Tax is enabled");
        vm.prank(admin);
        _mevHook.disableMevTax();
        assertFalse(_mevHook.isMevTaxEnabled(), "MEV Tax is enabled");
    }

    /********************************************************
                   getDefaultMevTaxMultiplier()
    ********************************************************/
    function testGetDefaultMevTaxMultiplierStartingState() public view {
        assertEq(_mevHook.getDefaultMevTaxMultiplier(), 0, "Default MEV Tax Multiplier is not 0 after hook creation.");
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
        vm.expectEmit();
        emit IMevHook.DefaultMevTaxMultiplierSet(newDefaultMevTaxMultiplier);
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
        assertEq(_mevHook.getDefaultMevTaxThreshold(), 0, "Default MEV Tax Threshold is not 0 after hook creation.");
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
        vm.expectEmit();
        emit IMevHook.DefaultMevTaxThresholdSet(newDefaultMevTaxThreshold);
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
        address newHook = createHook();

        authorizer.grantRole(IAuthentication(newHook).getActionId(IMevHook.setPoolMevTaxMultiplier.selector), admin);

        vm.prank(admin);
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
        vm.expectEmit();
        emit IMevHook.PoolMevTaxMultiplierSet(pool, newPoolMevTaxMultiplier);
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
        address newHook = createHook();

        authorizer.grantRole(IAuthentication(newHook).getActionId(IMevHook.setPoolMevTaxThreshold.selector), admin);

        vm.prank(admin);
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
        vm.expectEmit();
        emit IMevHook.PoolMevTaxThresholdSet(pool, newPoolMevTaxThreshold);
        _mevHook.setPoolMevTaxThreshold(pool, newPoolMevTaxThreshold);
        assertEq(_mevHook.getPoolMevTaxThreshold(pool), newPoolMevTaxThreshold, "poolMevTaxThreshold is not correct");

        assertEq(_mevHook.getDefaultMevTaxThreshold(), firstDefaultMevTaxThreshold, "Default threshold changed");
    }

    /**
     * @dev No matter what the parameters are,
     * - `staticFeePercentage <= computedFeePercentage <= maxFeePercentage` if `maxFeePercentage > staticFeePercentage`
     * - `computedFeePercentage = staticFeePercentage` if `maxFeePercentage <= staticFeePercentage`
     */
    function testCallbackBoundaries__Fuzz(
        uint256 txGasPrice,
        uint256 txBaseFee,
        uint256 threshold,
        uint256 multiplier,
        uint256 maxMevSwapFeePercentage,
        uint256 staticSwapFeePercentage
    ) public {
        txGasPrice = bound(txGasPrice, 1, 100e9);
        txBaseFee = bound(txBaseFee, 1, txGasPrice);
        threshold = bound(threshold, 1, 100e9);
        multiplier = bound(multiplier, 1, 1_000_000e18);
        maxMevSwapFeePercentage = bound(maxMevSwapFeePercentage, 1, MAX_FEE_PERCENTAGE);
        staticSwapFeePercentage = bound(staticSwapFeePercentage, 1e12, 10e16);

        vm.txGasPrice(txGasPrice);
        vm.fee(txBaseFee);
        vm.startPrank(admin);
        _mevHook.setPoolMevTaxThreshold(pool, threshold);
        _mevHook.setPoolMevTaxMultiplier(pool, multiplier);
        _mevHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);
        vm.stopPrank();

        PoolSwapParams memory poolSwapParams;

        (bool success, uint256 computedSwapFeePercentage) = IHooks(address(_mevHook)).onComputeDynamicSwapFeePercentage(
            poolSwapParams,
            pool,
            staticSwapFeePercentage
        );
        assertGe(
            computedSwapFeePercentage,
            staticSwapFeePercentage,
            "Computed swap fee percentage below static fee percentage"
        );
        if (maxMevSwapFeePercentage >= staticSwapFeePercentage) {
            assertLe(
                computedSwapFeePercentage,
                maxMevSwapFeePercentage,
                "Computed swap fee percentage above max fee percentage"
            );
        } else {
            assertEq(
                computedSwapFeePercentage,
                staticSwapFeePercentage,
                "Computed swap fee percentage is not the static fee percentage"
            );
        }
        assertTrue(success, "Hook failed");
    }
}
