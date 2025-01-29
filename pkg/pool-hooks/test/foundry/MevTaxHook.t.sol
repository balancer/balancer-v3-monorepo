// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolSwapParams, MAX_FEE_PERCENTAGE } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IMevTaxHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevTaxHook.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { MevTaxHookMock } from "../../contracts/test/MevTaxHookMock.sol";

contract MevTaxHookTest is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    MevTaxHookMock private _mevTaxHook;

    BalancerContractRegistry private registry;

    function setUp() public override {
        super.setUp();

        bytes4[] memory mevTaxHookSelectors = new bytes4[](9);

        mevTaxHookSelectors[0] = IMevTaxHook.disableMevTax.selector;
        mevTaxHookSelectors[1] = IMevTaxHook.enableMevTax.selector;
        mevTaxHookSelectors[2] = IMevTaxHook.setMaxMevSwapFeePercentage.selector;
        mevTaxHookSelectors[3] = IMevTaxHook.setDefaultMevTaxMultiplier.selector;
        mevTaxHookSelectors[4] = IMevTaxHook.setPoolMevTaxMultiplier.selector;
        mevTaxHookSelectors[5] = IMevTaxHook.setDefaultMevTaxThreshold.selector;
        mevTaxHookSelectors[6] = IMevTaxHook.setPoolMevTaxThreshold.selector;
        mevTaxHookSelectors[7] = IMevTaxHook.addMevTaxExemptSenders.selector;
        mevTaxHookSelectors[8] = IMevTaxHook.removeMevTaxExemptSenders.selector;

        for (uint256 i = 0; i < mevTaxHookSelectors.length; i++) {
            authorizer.grantRole(IAuthentication(address(_mevTaxHook)).getActionId(mevTaxHookSelectors[i]), admin);
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
        _mevTaxHook = new MevTaxHookMock(IVault(address(vault)), registry);
        vm.label(address(_mevTaxHook), "MEV Hook");
        return address(_mevTaxHook);
    }

    function testGetBalancerContractRegistry() public view {
        assertEq(address(_mevTaxHook.getBalancerContractRegistry()), address(registry), "Wrong registry");
    }

    /********************************************************
                       isMevTaxEnabled()
    ********************************************************/
    function testIsMevTaxEnabledStartingState() public view {
        assertFalse(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is enabled after hook creation.");
    }

    /********************************************************
                         enableMevTax()
    ********************************************************/
    function testEnableMevTaxIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.enableMevTax();
    }

    function testEnableMevTax() public {
        assertFalse(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is enabled");
        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.MevTaxEnabledSet(true);
        _mevTaxHook.enableMevTax();
        assertTrue(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is not enabled");
    }

    function testMultipleEnableMevTax() public {
        assertFalse(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is enabled");
        vm.prank(admin);
        _mevTaxHook.enableMevTax();
        assertTrue(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is not enabled");
        vm.prank(admin);
        _mevTaxHook.enableMevTax();
        assertTrue(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is not enabled");
    }

    /********************************************************
                    getMaxMevSwapFeePercentage()
    ********************************************************/
    function getMaxMevSwapFeePercentage() public view {
        assertEq(
            _mevTaxHook.getMaxMevSwapFeePercentage(),
            MAX_FEE_PERCENTAGE,
            "Incorrect initial max mev fee percentage"
        );
    }

    /********************************************************
                   setMaxMevSwapFeePercentage()
    ********************************************************/
    function testSetMaxMevSwapFeePercentageIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.setMaxMevSwapFeePercentage(50e16);
    }

    function testSetMaxMevSwapFeePercentageAboveMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IMevTaxHook.MevSwapFeePercentageAboveMax.selector,
                MAX_FEE_PERCENTAGE + 1,
                MAX_FEE_PERCENTAGE
            )
        );
        vm.prank(admin);
        _mevTaxHook.setMaxMevSwapFeePercentage(MAX_FEE_PERCENTAGE + 1);
    }

    function testSetMaxMevSwapFeePercentage() public {
        uint256 newMaxMevSwapFeePercentage = 50e16;
        assertEq(
            _mevTaxHook.getMaxMevSwapFeePercentage(),
            MAX_FEE_PERCENTAGE,
            "Incorrect initial max mev fee percentage"
        );
        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.MaxMevSwapFeePercentageSet(newMaxMevSwapFeePercentage);
        _mevTaxHook.setMaxMevSwapFeePercentage(newMaxMevSwapFeePercentage);
        assertEq(
            _mevTaxHook.getMaxMevSwapFeePercentage(),
            newMaxMevSwapFeePercentage,
            "Incorrect new max mev fee percentage"
        );
    }

    /********************************************************
                         disableMevTax()
    ********************************************************/
    function testDisableMevTaxIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.disableMevTax();
    }

    function testDisableMevTax() public {
        vm.prank(admin);
        _mevTaxHook.enableMevTax();
        assertTrue(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is not enabled");

        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.MevTaxEnabledSet(false);
        _mevTaxHook.disableMevTax();
        assertFalse(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is enabled");
    }

    function testMultipleDisableMevTax() public {
        vm.prank(admin);
        _mevTaxHook.enableMevTax();
        assertTrue(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is not enabled");
        vm.prank(admin);
        _mevTaxHook.disableMevTax();
        assertFalse(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is enabled");
        vm.prank(admin);
        _mevTaxHook.disableMevTax();
        assertFalse(_mevTaxHook.isMevTaxEnabled(), "MEV Tax is enabled");
    }

    /********************************************************
                   getDefaultMevTaxMultiplier()
    ********************************************************/
    function testGetDefaultMevTaxMultiplierStartingState() public view {
        assertEq(
            _mevTaxHook.getDefaultMevTaxMultiplier(),
            0,
            "Default MEV Tax Multiplier is not 0 after hook creation."
        );
    }

    /********************************************************
                   setDefaultMevTaxMultiplier()
    ********************************************************/
    function testSetDefaultMevTaxMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.setDefaultMevTaxMultiplier(1e18);
    }

    function testSetDefaultMevTaxMultiplier() public {
        uint256 firstDefaultMevTaxMultiplier = _mevTaxHook.getDefaultMevTaxMultiplier();

        uint256 newDefaultMevTaxMultiplier = 1e18;

        assertNotEq(
            firstDefaultMevTaxMultiplier,
            newDefaultMevTaxMultiplier,
            "New defaultMevTaxMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.DefaultMevTaxMultiplierSet(newDefaultMevTaxMultiplier);
        _mevTaxHook.setDefaultMevTaxMultiplier(newDefaultMevTaxMultiplier);
        assertEq(
            _mevTaxHook.getDefaultMevTaxMultiplier(),
            newDefaultMevTaxMultiplier,
            "defaultMevTaxMultiplier is not correct"
        );
    }

    function testSetDefaultMevTaxMultiplierRegisteredPool() public {
        vm.prank(admin);
        _mevTaxHook.setPoolMevTaxMultiplier(pool, 5e18);

        vm.prank(admin);
        _mevTaxHook.setDefaultMevTaxMultiplier(1e18);

        assertNotEq(
            _mevTaxHook.getDefaultMevTaxMultiplier(),
            _mevTaxHook.getPoolMevTaxMultiplier(pool),
            "setDefaultMevTaxMultiplier changed pool multiplier."
        );
    }

    /********************************************************
                   getDefaultMevTaxThreshold()
    ********************************************************/
    function testGetDefaultMevTaxThresholdStartingState() public view {
        assertEq(_mevTaxHook.getDefaultMevTaxThreshold(), 0, "Default MEV Tax Threshold is not 0 after hook creation.");
    }

    /********************************************************
                   setDefaultMevTaxThreshold()
    ********************************************************/
    function testSetDefaultMevTaxThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.setDefaultMevTaxThreshold(1e18);
    }

    function testSetDefaultMevTaxThreshold() public {
        uint256 firstDefaultMevTaxThreshold = _mevTaxHook.getDefaultMevTaxThreshold();

        uint256 newDefaultMevTaxThreshold = 1e18;

        assertNotEq(
            firstDefaultMevTaxThreshold,
            newDefaultMevTaxThreshold,
            "New defaultMevTaxThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.DefaultMevTaxThresholdSet(newDefaultMevTaxThreshold);
        _mevTaxHook.setDefaultMevTaxThreshold(newDefaultMevTaxThreshold);
        assertEq(
            _mevTaxHook.getDefaultMevTaxThreshold(),
            newDefaultMevTaxThreshold,
            "defaultMevTaxThreshold is not correct"
        );
    }

    function testSetDefaultMevTaxThresholdRegisteredPool() public {
        vm.prank(admin);
        _mevTaxHook.setPoolMevTaxThreshold(pool, 5e18);

        vm.prank(admin);
        _mevTaxHook.setDefaultMevTaxThreshold(1e18);

        assertNotEq(
            _mevTaxHook.getDefaultMevTaxThreshold(),
            _mevTaxHook.getPoolMevTaxThreshold(pool),
            "setDefaultMevTaxThreshold changed pool threshold."
        );
    }

    /********************************************************
                   getPoolMevTaxMultiplier()
    ********************************************************/
    function testGetPoolMevTaxMultiplierPoolNotRegistered() public {
        // Creates a new hook and stores into _mevTaxHook, so the pool won't be registered with the new MevTaxHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevTaxHook.MevTaxHookNotRegisteredInPool.selector, pool));
        _mevTaxHook.getPoolMevTaxMultiplier(pool);
    }

    /********************************************************
                   setPoolMevTaxMultiplier()
    ********************************************************/
    function testSetPoolMevTaxMultiplierPoolNotRegistered() public {
        // Creates a new hook and stores into _mevTaxHook, so the pool won't be registered with the new MevTaxHook.
        address newHook = createHook();

        authorizer.grantRole(IAuthentication(newHook).getActionId(IMevTaxHook.setPoolMevTaxMultiplier.selector), admin);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IMevTaxHook.MevTaxHookNotRegisteredInPool.selector, pool));
        _mevTaxHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    function testSetPoolMevTaxMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.setPoolMevTaxMultiplier(pool, 5e18);
    }

    function testSetPoolMevTaxMultiplier() public {
        uint256 firstPoolMevTaxMultiplier = _mevTaxHook.getPoolMevTaxMultiplier(pool);
        uint256 firstDefaultMevTaxMultiplier = _mevTaxHook.getDefaultMevTaxMultiplier();

        uint256 newPoolMevTaxMultiplier = 5e18;

        assertNotEq(
            firstPoolMevTaxMultiplier,
            newPoolMevTaxMultiplier,
            "New defaultMevTaxMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.PoolMevTaxMultiplierSet(pool, newPoolMevTaxMultiplier);
        _mevTaxHook.setPoolMevTaxMultiplier(pool, newPoolMevTaxMultiplier);
        assertEq(
            _mevTaxHook.getPoolMevTaxMultiplier(pool),
            newPoolMevTaxMultiplier,
            "poolMevTaxMultiplier is not correct"
        );

        assertEq(_mevTaxHook.getDefaultMevTaxMultiplier(), firstDefaultMevTaxMultiplier, "Default multiplier changed");
    }

    /********************************************************
                   getPoolMevTaxThreshold()
    ********************************************************/
    function testGetPoolMevTaxThresholdPoolNotRegistered() public {
        // Creates a new hook and stores into _mevTaxHook, so the pool won't be registered with the new MevTaxHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevTaxHook.MevTaxHookNotRegisteredInPool.selector, pool));
        _mevTaxHook.getPoolMevTaxThreshold(pool);
    }

    /********************************************************
                   setPoolMevTaxThreshold()
    ********************************************************/
    function testSetPoolMevTaxThresholdPoolNotRegistered() public {
        // Creates a new hook and stores into _mevTaxHook, so the pool won't be registered with the new MevTaxHook.
        address newHook = createHook();

        authorizer.grantRole(IAuthentication(newHook).getActionId(IMevTaxHook.setPoolMevTaxThreshold.selector), admin);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IMevTaxHook.MevTaxHookNotRegisteredInPool.selector, pool));
        _mevTaxHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.setPoolMevTaxThreshold(pool, 5e18);
    }

    function testSetPoolMevTaxThreshold() public {
        uint256 firstPoolMevTaxThreshold = _mevTaxHook.getPoolMevTaxThreshold(pool);
        uint256 firstDefaultMevTaxThreshold = _mevTaxHook.getDefaultMevTaxThreshold();

        uint256 newPoolMevTaxThreshold = 5e18;

        assertNotEq(
            firstPoolMevTaxThreshold,
            newPoolMevTaxThreshold,
            "New defaultMevTaxThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.PoolMevTaxThresholdSet(pool, newPoolMevTaxThreshold);
        _mevTaxHook.setPoolMevTaxThreshold(pool, newPoolMevTaxThreshold);
        assertEq(
            _mevTaxHook.getPoolMevTaxThreshold(pool),
            newPoolMevTaxThreshold,
            "poolMevTaxThreshold is not correct"
        );

        assertEq(_mevTaxHook.getDefaultMevTaxThreshold(), firstDefaultMevTaxThreshold, "Default threshold changed");
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
        _mevTaxHook.setPoolMevTaxThreshold(pool, threshold);
        _mevTaxHook.setPoolMevTaxMultiplier(pool, multiplier);
        _mevTaxHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);
        vm.stopPrank();

        PoolSwapParams memory poolSwapParams;

        (bool success, uint256 computedSwapFeePercentage) = IHooks(address(_mevTaxHook))
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

        uint256 feePercentage = _mevTaxHook.calculateSwapFeePercentageExternal(
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
        _mevTaxHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

        uint256 baseFee = 1e9;
        uint256 gasDeltaMaxFee = (maxMevSwapFeePercentage - staticSwapFeePercentage).divDown(multiplier);
        gasPriceDelta = bound(gasPriceDelta, 0, gasDeltaMaxFee);

        vm.fee(baseFee);
        vm.txGasPrice(baseFee + priorityThreshold + gasPriceDelta);

        uint256 expectedFeePercentage = staticSwapFeePercentage + gasPriceDelta.mulDown(multiplier);

        uint256 feePercentage = _mevTaxHook.calculateSwapFeePercentageExternal(
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
        _mevTaxHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

        uint256 baseFee = 1e9;
        uint256 gasDeltaMaxFee = (maxMevSwapFeePercentage - staticSwapFeePercentage).divDown(multiplier);
        gasPriceDelta = bound(gasPriceDelta, gasDeltaMaxFee, gasDeltaMaxFee * 1e40);

        vm.fee(baseFee);
        vm.txGasPrice(baseFee + priorityThreshold + gasPriceDelta);

        uint256 feePercentage = _mevTaxHook.calculateSwapFeePercentageExternal(
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
        _mevTaxHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

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

        uint256 feePercentage = _mevTaxHook.calculateSwapFeePercentageExternal(
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
        _mevTaxHook.setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);

        uint256 baseFee = 1e9;
        gasPriceDelta = bound(gasPriceDelta, 0, type(uint256).max - priorityThreshold - baseFee);

        vm.fee(baseFee);
        vm.txGasPrice(baseFee + priorityThreshold + gasPriceDelta);

        uint256 feePercentage = _mevTaxHook.calculateSwapFeePercentageExternal(
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
        _mevTaxHook.addMevTaxExemptSenders([address(1), address(2)].toMemoryArray());
    }

    function testAddMevTaxExemptSenders() public {
        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.MevTaxExemptSenderAdded(lp);
        vm.expectEmit();
        emit IMevTaxHook.MevTaxExemptSenderAdded(bob);
        vm.expectEmit();
        emit IMevTaxHook.MevTaxExemptSenderAdded(alice);
        _mevTaxHook.addMevTaxExemptSenders([lp, bob, alice].toMemoryArray());
        assertTrue(_mevTaxHook.isMevTaxExempt(lp), "LP was not added properly as MEV tax-exempt");
        assertTrue(_mevTaxHook.isMevTaxExempt(bob), "Bob was not added properly as MEV tax-exempt");
        assertTrue(_mevTaxHook.isMevTaxExempt(alice), "Alice was not added properly as MEV tax-exempt");
    }

    function testAddMevTaxExemptSendersRevertsWithDuplicated() public {
        vm.prank(admin);
        _mevTaxHook.addMevTaxExemptSenders([lp, bob, alice].toMemoryArray());

        vm.expectRevert(abi.encodeWithSelector(IMevTaxHook.MevTaxExemptSenderAlreadyAdded.selector, bob));
        vm.prank(admin);
        _mevTaxHook.addMevTaxExemptSenders([bob].toMemoryArray());
    }

    /********************************************************
                   removeMevTaxExemptSenders
    ********************************************************/
    function testRemoveMevTaxExemptSendersIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevTaxHook.removeMevTaxExemptSenders([alice, bob].toMemoryArray());
    }

    function testRemoveMevTaxExemptSenders() public {
        vm.prank(admin);
        _mevTaxHook.addMevTaxExemptSenders([lp, bob, alice].toMemoryArray());

        vm.prank(admin);
        vm.expectEmit();
        emit IMevTaxHook.MevTaxExemptSenderRemoved(lp);
        vm.expectEmit();
        emit IMevTaxHook.MevTaxExemptSenderRemoved(alice);
        _mevTaxHook.removeMevTaxExemptSenders([lp, alice].toMemoryArray());

        assertTrue(_mevTaxHook.isMevTaxExempt(bob), "Bob was not added properly as MEV tax-exempt");
        assertFalse(_mevTaxHook.isMevTaxExempt(lp), "LP was not removed properly as MEV tax-exempt");
        assertFalse(_mevTaxHook.isMevTaxExempt(alice), "Alice was not removed properly as MEV tax-exempt");
    }

    function testRemoveMevTaxExemptSendersRevertsIfNotExist() public {
        vm.prank(admin);
        _mevTaxHook.addMevTaxExemptSenders([lp, alice].toMemoryArray());

        vm.expectRevert(abi.encodeWithSelector(IMevTaxHook.SenderNotRegisteredAsMevTaxExempt.selector, bob));
        vm.prank(admin);
        _mevTaxHook.removeMevTaxExemptSenders([bob].toMemoryArray());
    }

    /********************************************************
                       isMevTaxExempt
    ********************************************************/
    function testIsMevTaxExempt() public {
        vm.prank(admin);
        _mevTaxHook.addMevTaxExemptSenders([lp, alice].toMemoryArray());

        assertTrue(_mevTaxHook.isMevTaxExempt(lp), "LP is not exempt");
        assertFalse(_mevTaxHook.isMevTaxExempt(bob), "Bob is exempt");
        assertTrue(_mevTaxHook.isMevTaxExempt(alice), "Alice is not exempt");
    }
}
