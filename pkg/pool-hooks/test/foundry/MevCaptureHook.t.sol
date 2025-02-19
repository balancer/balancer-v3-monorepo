// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import {
    PoolSwapParams,
    MAX_FEE_PERCENTAGE,
    PoolRoleAccounts
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IMevCaptureHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevCaptureHook.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { MevCaptureHookMock } from "../../contracts/test/MevCaptureHookMock.sol";

contract MevCaptureHookTest is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    error MockRegistryRevert();

    uint256 private DEFAULT_MEV_TAX_MULTIPLIER = 10e18;
    uint256 private DEFAULT_MEV_TAX_THRESHOLD = 10e16;

    MevCaptureHookMock private _mevCaptureHook;

    BalancerContractRegistry private registry;

    function setUp() public override {
        super.setUp();

        bytes4[] memory mevCaptureHookSelectors = new bytes4[](9);

        mevCaptureHookSelectors[0] = IMevCaptureHook.disableMevTax.selector;
        mevCaptureHookSelectors[1] = IMevCaptureHook.enableMevTax.selector;
        mevCaptureHookSelectors[2] = IMevCaptureHook.setMaxMevSwapFeePercentage.selector;
        mevCaptureHookSelectors[3] = IMevCaptureHook.setDefaultMevTaxMultiplier.selector;
        mevCaptureHookSelectors[4] = IMevCaptureHook.setPoolMevTaxMultiplier.selector;
        mevCaptureHookSelectors[5] = IMevCaptureHook.setDefaultMevTaxThreshold.selector;
        mevCaptureHookSelectors[6] = IMevCaptureHook.setPoolMevTaxThreshold.selector;
        mevCaptureHookSelectors[7] = IMevCaptureHook.addMevTaxExemptSenders.selector;
        mevCaptureHookSelectors[8] = IMevCaptureHook.removeMevTaxExemptSenders.selector;

        for (uint256 i = 0; i < mevCaptureHookSelectors.length; i++) {
            authorizer.grantRole(
                IAuthentication(address(_mevCaptureHook)).getActionId(mevCaptureHookSelectors[i]),
                admin
            );
        }
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
        registry = new BalancerContractRegistry(vault);
        _mevCaptureHook = new MevCaptureHookMock(
            IVault(address(vault)),
            registry,
            DEFAULT_MEV_TAX_MULTIPLIER,
            DEFAULT_MEV_TAX_THRESHOLD
        );
        vm.label(address(_mevCaptureHook), "MEV Hook");
        return address(_mevCaptureHook);
    }

    function testGetBalancerContractRegistry() public view {
        assertEq(address(_mevCaptureHook.getBalancerContractRegistry()), address(registry), "Wrong registry");
    }

    /********************************************************
                         constructor()
    ********************************************************/

    function testInvalidRegistry() public {
        BalancerContractRegistry mockRegistry = BalancerContractRegistry(address(1));
        vm.mockCall(
            address(mockRegistry),
            abi.encodeWithSelector(BalancerContractRegistry.isTrustedRouter.selector, address(0)),
            abi.encode(true)
        );
        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.InvalidBalancerContractRegistry.selector));
        new MevCaptureHookMock(
            IVault(address(vault)),
            mockRegistry,
            DEFAULT_MEV_TAX_THRESHOLD,
            DEFAULT_MEV_TAX_MULTIPLIER
        );
    }

    function testRevertingRegistry() public {
        BalancerContractRegistry mockRegistry = BalancerContractRegistry(address(1));
        vm.mockCallRevert(
            address(mockRegistry),
            abi.encodeWithSelector(BalancerContractRegistry.isTrustedRouter.selector, address(0)),
            abi.encodePacked(MockRegistryRevert.selector)
        );

        vm.expectRevert(MockRegistryRevert.selector);
        new MevCaptureHookMock(
            IVault(address(vault)),
            mockRegistry,
            DEFAULT_MEV_TAX_THRESHOLD,
            DEFAULT_MEV_TAX_MULTIPLIER
        );
    }

    function testDefaultMevTaxMultiplier() public view {
        assertEq(
            _mevCaptureHook.getDefaultMevTaxMultiplier(),
            DEFAULT_MEV_TAX_MULTIPLIER,
            "Wrong default MEV tax multiplier"
        );
    }

    function testDefaultMevTaxThreshold() public view {
        assertEq(
            _mevCaptureHook.getDefaultMevTaxThreshold(),
            DEFAULT_MEV_TAX_THRESHOLD,
            "Wrong default MEV tax threshold"
        );
    }

    /********************************************************
                       isMevTaxEnabled()
    ********************************************************/
    function testIsMevTaxEnabledStartingState() public view {
        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not enabled after hook creation.");
    }

    /********************************************************
                         enableMevTax()
    ********************************************************/
    function testEnableMevTaxIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.enableMevTax();
    }

    function testEnableMevTax() public {
        // Defaults to enabled initially
        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not enabled");
        vm.startPrank(admin);
        _mevCaptureHook.disableMevTax();
        assertFalse(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is enabled after disabling");

        vm.expectEmit();
        emit IMevCaptureHook.MevTaxEnabledSet(true);
        _mevCaptureHook.enableMevTax();
        vm.stopPrank();

        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not enabled");
    }

    function testMultipleEnableMevTax() public {
        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not initially enabled");
        vm.prank(admin);
        _mevCaptureHook.enableMevTax();
        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not enabled (first time set)");
        vm.prank(admin);
        _mevCaptureHook.enableMevTax();
        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not enabled (second time set)");
    }

    /********************************************************
                    getMaxMevSwapFeePercentage()
    ********************************************************/
    function getMaxMevSwapFeePercentage() public view {
        assertEq(
            _mevCaptureHook.getMaxMevSwapFeePercentage(),
            MAX_FEE_PERCENTAGE,
            "Incorrect initial max mev fee percentage"
        );
    }

    /********************************************************
                   setMaxMevSwapFeePercentage()
    ********************************************************/
    function testSetMaxMevSwapFeePercentageIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setMaxMevSwapFeePercentage(50e16);
    }

    function testSetMaxMevSwapFeePercentageAboveMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IMevCaptureHook.MevSwapFeePercentageAboveMax.selector,
                MAX_FEE_PERCENTAGE + 1,
                MAX_FEE_PERCENTAGE
            )
        );
        vm.prank(admin);
        _mevCaptureHook.setMaxMevSwapFeePercentage(MAX_FEE_PERCENTAGE + 1);
    }

    function testSetMaxMevSwapFeePercentage() public {
        uint256 newMaxMevSwapFeePercentage = 50e16;
        assertEq(
            _mevCaptureHook.getMaxMevSwapFeePercentage(),
            MAX_FEE_PERCENTAGE,
            "Incorrect initial max mev fee percentage"
        );
        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MaxMevSwapFeePercentageSet(newMaxMevSwapFeePercentage);
        _mevCaptureHook.setMaxMevSwapFeePercentage(newMaxMevSwapFeePercentage);
        assertEq(
            _mevCaptureHook.getMaxMevSwapFeePercentage(),
            newMaxMevSwapFeePercentage,
            "Incorrect new max mev fee percentage"
        );
    }

    /********************************************************
                         disableMevTax()
    ********************************************************/
    function testDisableMevTaxIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.disableMevTax();
    }

    function testDisableMevTax() public {
        vm.prank(admin);
        _mevCaptureHook.enableMevTax();
        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not enabled");

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MevTaxEnabledSet(false);
        _mevCaptureHook.disableMevTax();
        assertFalse(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is enabled");
    }

    function testMultipleDisableMevTax() public {
        vm.prank(admin);
        _mevCaptureHook.enableMevTax();
        assertTrue(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is not enabled");
        vm.prank(admin);
        _mevCaptureHook.disableMevTax();
        assertFalse(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is enabled");
        vm.prank(admin);
        _mevCaptureHook.disableMevTax();
        assertFalse(_mevCaptureHook.isMevTaxEnabled(), "MEV Tax is enabled");
    }

    /********************************************************
                   setDefaultMevTaxMultiplier()
    ********************************************************/
    function testSetDefaultMevTaxMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setDefaultMevTaxMultiplier(1e18);
    }

    function testSetDefaultMevTaxMultiplier() public {
        uint256 firstDefaultMevTaxMultiplier = _mevCaptureHook.getDefaultMevTaxMultiplier();

        uint256 newDefaultMevTaxMultiplier = 1e18;

        assertNotEq(
            firstDefaultMevTaxMultiplier,
            newDefaultMevTaxMultiplier,
            "New defaultMevTaxMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.DefaultMevTaxMultiplierSet(newDefaultMevTaxMultiplier);
        _mevCaptureHook.setDefaultMevTaxMultiplier(newDefaultMevTaxMultiplier);
        assertEq(
            _mevCaptureHook.getDefaultMevTaxMultiplier(),
            newDefaultMevTaxMultiplier,
            "defaultMevTaxMultiplier is not correct"
        );
    }

    function testSetDefaultMevTaxMultiplierRegisteredPool() public {
        vm.prank(admin);
        _mevCaptureHook.setPoolMevTaxMultiplier(pool, 5e18);

        vm.prank(admin);
        _mevCaptureHook.setDefaultMevTaxMultiplier(1e18);

        assertNotEq(
            _mevCaptureHook.getDefaultMevTaxMultiplier(),
            _mevCaptureHook.getPoolMevTaxMultiplier(pool),
            "setDefaultMevTaxMultiplier changed pool multiplier."
        );
    }

    /********************************************************
                   setDefaultMevTaxThreshold()
    ********************************************************/
    function testSetDefaultMevTaxThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setDefaultMevTaxThreshold(1e18);
    }

    function testSetDefaultMevTaxThreshold() public {
        uint256 firstDefaultMevTaxThreshold = _mevCaptureHook.getDefaultMevTaxThreshold();

        uint256 newDefaultMevTaxThreshold = 1e18;

        assertNotEq(
            firstDefaultMevTaxThreshold,
            newDefaultMevTaxThreshold,
            "New defaultMevTaxThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.DefaultMevTaxThresholdSet(newDefaultMevTaxThreshold);
        _mevCaptureHook.setDefaultMevTaxThreshold(newDefaultMevTaxThreshold);
        assertEq(
            _mevCaptureHook.getDefaultMevTaxThreshold(),
            newDefaultMevTaxThreshold,
            "defaultMevTaxThreshold is not correct"
        );
    }

    function testSetDefaultMevTaxThresholdRegisteredPool() public {
        vm.prank(admin);
        _mevCaptureHook.setPoolMevTaxThreshold(pool, 5e18);

        vm.prank(admin);
        _mevCaptureHook.setDefaultMevTaxThreshold(1e18);

        assertNotEq(
            _mevCaptureHook.getDefaultMevTaxThreshold(),
            _mevCaptureHook.getPoolMevTaxThreshold(pool),
            "setDefaultMevTaxThreshold changed pool threshold."
        );
    }

    /********************************************************
                   getPoolMevTaxMultiplier()
    ********************************************************/
    function testGetPoolMevTaxMultiplierPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.getPoolMevTaxMultiplier(pool);
    }

    /********************************************************
                   setPoolMevTaxMultiplier()
    ********************************************************/
    function testSetPoolMevTaxMultiplierPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        address newHook = createHook();

        authorizer.grantRole(
            IAuthentication(newHook).getActionId(IMevCaptureHook.setPoolMevTaxMultiplier.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    function testSetPoolMevTaxMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    function testSetPoolMevTaxMultiplier() public {
        uint256 firstPoolMevTaxMultiplier = _mevCaptureHook.getPoolMevTaxMultiplier(pool);
        uint256 firstDefaultMevTaxMultiplier = _mevCaptureHook.getDefaultMevTaxMultiplier();

        uint256 newPoolMevTaxMultiplier = 5e18;

        assertNotEq(
            firstPoolMevTaxMultiplier,
            newPoolMevTaxMultiplier,
            "New defaultMevTaxMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.PoolMevTaxMultiplierSet(pool, newPoolMevTaxMultiplier);
        _mevCaptureHook.setPoolMevTaxMultiplier(pool, newPoolMevTaxMultiplier);
        assertEq(
            _mevCaptureHook.getPoolMevTaxMultiplier(pool),
            newPoolMevTaxMultiplier,
            "poolMevTaxMultiplier is not correct"
        );

        assertEq(
            _mevCaptureHook.getDefaultMevTaxMultiplier(),
            firstDefaultMevTaxMultiplier,
            "Default multiplier changed"
        );
    }

    function testSetPoolMevTaxMultiplierRevertIfSenderIsNotFeeManager() public {
        _mockPoolRoleAccounts(address(0x01));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    function testSetPoolMevTaxMultiplierWithSwapFeeManager() public {
        _mockPoolRoleAccounts(address(this));

        _mevCaptureHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    /********************************************************
                   getPoolMevTaxThreshold()
    ********************************************************/
    function testGetPoolMevTaxThresholdPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.getPoolMevTaxThreshold(pool);
    }

    /********************************************************
                   setPoolMevTaxThreshold()
    ********************************************************/
    function testSetPoolMevTaxThresholdPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        address newHook = createHook();

        authorizer.grantRole(
            IAuthentication(newHook).getActionId(IMevCaptureHook.setPoolMevTaxThreshold.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThresholdRevertIfSenderIsNotFeeManager() public {
        _mockPoolRoleAccounts(address(0x01));

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThresholdWithSwapFeeManager() public {
        _mockPoolRoleAccounts(address(this));

        _mevCaptureHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThreshold() public {
        uint256 firstPoolMevTaxThreshold = _mevCaptureHook.getPoolMevTaxThreshold(pool);
        uint256 firstDefaultMevTaxThreshold = _mevCaptureHook.getDefaultMevTaxThreshold();

        uint256 newPoolMevTaxThreshold = 5e18;

        assertNotEq(
            firstPoolMevTaxThreshold,
            newPoolMevTaxThreshold,
            "New defaultMevTaxThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.PoolMevTaxThresholdSet(pool, newPoolMevTaxThreshold);
        _mevCaptureHook.setPoolMevTaxThreshold(pool, newPoolMevTaxThreshold);
        assertEq(
            _mevCaptureHook.getPoolMevTaxThreshold(pool),
            newPoolMevTaxThreshold,
            "poolMevTaxThreshold is not correct"
        );

        assertEq(_mevCaptureHook.getDefaultMevTaxThreshold(), firstDefaultMevTaxThreshold, "Default threshold changed");
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
        _mevCaptureHook.setPoolMevTaxThreshold(pool, threshold);
        _mevCaptureHook.setPoolMevTaxMultiplier(pool, multiplier);
        _mevCaptureHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);
        vm.stopPrank();

        PoolSwapParams memory poolSwapParams;

        (bool success, uint256 computedSwapFeePercentage) = IHooks(address(_mevCaptureHook))
            .onComputeDynamicSwapFeePercentage(poolSwapParams, pool, staticSwapFeePercentage);
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

    /********************************************************
                   calculateSwapFeePercentage()
    ********************************************************/
    function testFeePercentageUnderThreshold__Fuzz(uint256 gasPriceDelta) public {
        uint256 staticSwapFeePercentage = 10e16; // 10% static swap fee
        uint256 priorityThreshold = 100e9;
        uint256 multiplier = 1_000_000e18;

        uint256 baseFee = 1e9;
        gasPriceDelta = bound(gasPriceDelta, 1, priorityThreshold - 1);

        vm.fee(baseFee);
        vm.txGasPrice(baseFee + priorityThreshold - gasPriceDelta);

        uint256 feePercentage = _mevCaptureHook.calculateSwapFeePercentageExternal(
            staticSwapFeePercentage,
            multiplier,
            priorityThreshold
        );
        assertEq(feePercentage, staticSwapFeePercentage, "Fee percentage not equal to static fee percentage");
    }

    function testFeePercentageBetweenThresholdAndMaxFee__Fuzz(uint256 gasPriceDelta) public {
        uint256 staticSwapFeePercentage = 10e16; // 10% static swap fee
        uint256 priorityThreshold = 100e9;
        uint256 multiplier = 1_000_000e18;

        uint256 maxMevSwapFeePercentage = 20e16; // 20% max swap fee
        vm.prank(admin);
        _mevCaptureHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

        uint256 baseFee = 1e9;
        uint256 gasDeltaMaxFee = (maxMevSwapFeePercentage - staticSwapFeePercentage).divDown(multiplier);
        gasPriceDelta = bound(gasPriceDelta, 0, gasDeltaMaxFee);

        vm.fee(baseFee);
        vm.txGasPrice(baseFee + priorityThreshold + gasPriceDelta);

        uint256 expectedFeePercentage = staticSwapFeePercentage + gasPriceDelta.mulDown(multiplier);

        uint256 feePercentage = _mevCaptureHook.calculateSwapFeePercentageExternal(
            staticSwapFeePercentage,
            multiplier,
            priorityThreshold
        );
        assertEq(feePercentage, expectedFeePercentage, "Fee percentage not equal to expected fee percentage");
        assertGe(feePercentage, staticSwapFeePercentage, "Fee percentage not greater than static fee percentage");
    }

    function testFeePercentageAboveMaxFee__Fuzz(uint256 gasPriceDelta) public {
        uint256 staticSwapFeePercentage = 10e16; // 10% static swap fee
        uint256 priorityThreshold = 100e9;
        uint256 multiplier = 1_000_000e18;

        uint256 maxMevSwapFeePercentage = 20e16; // 20% max swap fee
        vm.prank(admin);
        _mevCaptureHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

        uint256 baseFee = 1e9;
        uint256 gasDeltaMaxFee = (maxMevSwapFeePercentage - staticSwapFeePercentage).divDown(multiplier);
        gasPriceDelta = bound(gasPriceDelta, gasDeltaMaxFee, gasDeltaMaxFee * 1e40);

        vm.fee(baseFee);
        vm.txGasPrice(baseFee + priorityThreshold + gasPriceDelta);

        uint256 feePercentage = _mevCaptureHook.calculateSwapFeePercentageExternal(
            staticSwapFeePercentage,
            multiplier,
            priorityThreshold
        );
        assertEq(feePercentage, maxMevSwapFeePercentage, "Fee percentage not equal to max fee percentage");
        assertGe(feePercentage, staticSwapFeePercentage, "Fee percentage not greater than static fee percentage");
    }

    function testFeePercentageMathOverflow__Fuzz(uint256 gasPriceDelta) public {
        uint256 staticSwapFeePercentage = 10e16; // 10% static swap fee
        uint256 priorityThreshold = 100e9;
        uint256 multiplier = 1_000_000e18;

        uint256 maxMevSwapFeePercentage = 20e16; // 20% max swap fee
        vm.prank(admin);
        _mevCaptureHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

        uint256 baseFee = 1e9;
        uint256 gasDeltaMaxFee = (maxMevSwapFeePercentage - staticSwapFeePercentage).divDown(multiplier);
        gasPriceDelta = bound(gasPriceDelta, gasDeltaMaxFee * 1e40, type(uint256).max);

        vm.fee(baseFee);
        // Avoids an overflow in the calculation of txGasPrice.
        if (gasPriceDelta > type(uint256).max - baseFee - priorityThreshold) {
            vm.txGasPrice(type(uint256).max);
        } else {
            vm.txGasPrice(baseFee + priorityThreshold + gasPriceDelta);
        }

        uint256 feePercentage = _mevCaptureHook.calculateSwapFeePercentageExternal(
            staticSwapFeePercentage,
            multiplier,
            priorityThreshold
        );
        assertEq(feePercentage, maxMevSwapFeePercentage, "Fee percentage not equal to max fee percentage");
        assertGe(feePercentage, staticSwapFeePercentage, "Fee percentage not greater than static fee percentage");
    }

    function testFeePercentageAboveThresholdLowMaxFee__Fuzz(uint256 gasPriceDelta) public {
        uint256 staticSwapFeePercentage = 10e16; // 10% static swap fee
        uint256 priorityThreshold = 100e9;
        uint256 multiplier = 1_000_000e18;

        uint256 maxMevSwapFeePercentage = 5e16; // 5% max swap fee
        vm.prank(admin);
        _mevCaptureHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

        uint256 baseFee = 1e9;
        gasPriceDelta = bound(gasPriceDelta, 0, type(uint256).max - priorityThreshold - baseFee);

        vm.fee(baseFee);
        vm.txGasPrice(baseFee + priorityThreshold + gasPriceDelta);

        uint256 feePercentage = _mevCaptureHook.calculateSwapFeePercentageExternal(
            staticSwapFeePercentage,
            multiplier,
            priorityThreshold
        );
        // If maxMevSwapFeePercentage < staticSwapFeePercentage, return staticSwapFeePercentage.
        assertEq(feePercentage, staticSwapFeePercentage, "Fee percentage not equal to static fee percentage");
    }

    /********************************************************
                   addMevTaxExemptSenders
    ********************************************************/
    function testAddMevTaxExemptSendersIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.addMevTaxExemptSenders([address(1), address(2)].toMemoryArray());
    }

    function testAddMevTaxExemptSenders() public {
        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MevTaxExemptSenderAdded(lp);
        vm.expectEmit();
        emit IMevCaptureHook.MevTaxExemptSenderAdded(bob);
        vm.expectEmit();
        emit IMevCaptureHook.MevTaxExemptSenderAdded(alice);
        _mevCaptureHook.addMevTaxExemptSenders([lp, bob, alice].toMemoryArray());
        assertTrue(_mevCaptureHook.isMevTaxExemptSender(lp), "LP was not added properly as MEV tax-exempt");
        assertTrue(_mevCaptureHook.isMevTaxExemptSender(bob), "Bob was not added properly as MEV tax-exempt");
        assertTrue(_mevCaptureHook.isMevTaxExemptSender(alice), "Alice was not added properly as MEV tax-exempt");
    }

    function testAddMevTaxExemptSendersRevertsWithDuplicated() public {
        vm.prank(admin);
        _mevCaptureHook.addMevTaxExemptSenders([lp, bob, alice].toMemoryArray());

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevTaxExemptSenderAlreadyAdded.selector, bob));
        vm.prank(admin);
        _mevCaptureHook.addMevTaxExemptSenders([bob].toMemoryArray());
    }

    /********************************************************
                   removeMevTaxExemptSenders
    ********************************************************/
    function testRemoveMevTaxExemptSendersIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.removeMevTaxExemptSenders([alice, bob].toMemoryArray());
    }

    function testRemoveMevTaxExemptSenders() public {
        vm.prank(admin);
        _mevCaptureHook.addMevTaxExemptSenders([lp, bob, alice].toMemoryArray());

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MevTaxExemptSenderRemoved(lp);
        vm.expectEmit();
        emit IMevCaptureHook.MevTaxExemptSenderRemoved(alice);
        _mevCaptureHook.removeMevTaxExemptSenders([lp, alice].toMemoryArray());

        assertTrue(_mevCaptureHook.isMevTaxExemptSender(bob), "Bob was not added properly as MEV tax-exempt");
        assertFalse(_mevCaptureHook.isMevTaxExemptSender(lp), "LP was not removed properly as MEV tax-exempt");
        assertFalse(_mevCaptureHook.isMevTaxExemptSender(alice), "Alice was not removed properly as MEV tax-exempt");
    }

    function testRemoveMevTaxExemptSendersRevertsIfNotExist() public {
        vm.prank(admin);
        _mevCaptureHook.addMevTaxExemptSenders([lp, alice].toMemoryArray());

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.SenderNotRegisteredAsMevTaxExempt.selector, bob));
        vm.prank(admin);
        _mevCaptureHook.removeMevTaxExemptSenders([bob].toMemoryArray());
    }

    /********************************************************
                       isMevTaxExempt
    ********************************************************/
    function testIsMevTaxExemptSender() public {
        vm.prank(admin);
        _mevCaptureHook.addMevTaxExemptSenders([lp, alice].toMemoryArray());

        assertTrue(_mevCaptureHook.isMevTaxExemptSender(lp), "LP is not exempt");
        assertFalse(_mevCaptureHook.isMevTaxExemptSender(bob), "Bob is exempt");
        assertTrue(_mevCaptureHook.isMevTaxExemptSender(alice), "Alice is not exempt");
    }

    /********************************************************
                            Other
    ********************************************************/
    function _mockPoolRoleAccounts(address swapFeeManager) private {
        PoolRoleAccounts memory poolRoleAccounts = PoolRoleAccounts({
            pauseManager: address(0x01),
            swapFeeManager: swapFeeManager,
            poolCreator: address(0x01)
        });
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IVaultExtension.getPoolRoleAccounts.selector, pool),
            abi.encode(poolRoleAccounts)
        );
    }
}
