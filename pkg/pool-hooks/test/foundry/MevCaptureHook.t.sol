// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolSwapParams, MAX_FEE_PERCENTAGE } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
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

    MevCaptureHookMock private _mevCaptureHook;

    BalancerContractRegistry private registry;

    function setUp() public override {
        super.setUp();

        bytes4[] memory mevCaptureHookSelectors = new bytes4[](9);

        mevCaptureHookSelectors[0] = IMevCaptureHook.disableMevCapture.selector;
        mevCaptureHookSelectors[1] = IMevCaptureHook.enableMevCapture.selector;
        mevCaptureHookSelectors[2] = IMevCaptureHook.setMaxMevSwapFeePercentage.selector;
        mevCaptureHookSelectors[3] = IMevCaptureHook.setDefaultMevCaptureMultiplier.selector;
        mevCaptureHookSelectors[4] = IMevCaptureHook.setPoolMevCaptureMultiplier.selector;
        mevCaptureHookSelectors[5] = IMevCaptureHook.setDefaultMevCaptureThreshold.selector;
        mevCaptureHookSelectors[6] = IMevCaptureHook.setPoolMevCaptureThreshold.selector;
        mevCaptureHookSelectors[7] = IMevCaptureHook.addMevCaptureExemptSenders.selector;
        mevCaptureHookSelectors[8] = IMevCaptureHook.removeMevCaptureExemptSenders.selector;

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
        _mevCaptureHook = new MevCaptureHookMock(IVault(address(vault)), registry);
        vm.label(address(_mevCaptureHook), "MEV Hook");
        return address(_mevCaptureHook);
    }

    function testGetBalancerContractRegistry() public view {
        assertEq(address(_mevCaptureHook.getBalancerContractRegistry()), address(registry), "Wrong registry");
    }

    /********************************************************
                      isMevCaptureEnabled()
    ********************************************************/

    function testIsMevCaptureEnabledStartingState() public view {
        assertFalse(_mevCaptureHook.isMevCaptureEnabled(), "MEV capture is enabled after hook creation.");
    }

    /********************************************************
                       enableMevCapture()
    ********************************************************/

    function testEnableMevCaptureIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.enableMevCapture();
    }

    function testEnableMevCapture() public {
        assertFalse(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is enabled");
        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MevCaptureEnabledSet(true);
        _mevCaptureHook.enableMevCapture();
        assertTrue(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is not enabled");
    }

    function testMultipleEnableMevCapture() public {
        assertFalse(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is enabled");
        vm.prank(admin);
        _mevCaptureHook.enableMevCapture();
        assertTrue(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is not enabled");
        vm.prank(admin);
        _mevCaptureHook.enableMevCapture();
        assertTrue(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is not enabled");
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
                      disableMevCapture()
    ********************************************************/

    function testDisableMevCaptureIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.disableMevCapture();
    }

    function testDisableMevCapture() public {
        vm.prank(admin);
        _mevCaptureHook.enableMevCapture();
        assertTrue(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is not enabled");

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MevCaptureEnabledSet(false);
        _mevCaptureHook.disableMevCapture();
        assertFalse(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is enabled");
    }

    function testMultipleDisableMevCapture() public {
        vm.prank(admin);
        _mevCaptureHook.enableMevCapture();
        assertTrue(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is not enabled");
        vm.prank(admin);
        _mevCaptureHook.disableMevCapture();
        assertFalse(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is enabled");
        vm.prank(admin);
        _mevCaptureHook.disableMevCapture();
        assertFalse(_mevCaptureHook.isMevCaptureEnabled(), "MEV Capture is enabled");
    }

    /********************************************************
                   getDefaultMevCaptureMultiplier()
    ********************************************************/
    function testGetDefaultMevCaptureMultiplierStartingState() public view {
        assertEq(
            _mevCaptureHook.getDefaultMevCaptureMultiplier(),
            0,
            "Default MEV Capture Multiplier is not 0 after hook creation."
        );
    }

    /********************************************************
                   setDefaultMevCaptureMultiplier()
    ********************************************************/

    function testSetDefaultMevCaptureMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setDefaultMevCaptureMultiplier(1e18);
    }

    function testSetDefaultMevCaptureMultiplier() public {
        uint256 firstDefaultMevCaptureMultiplier = _mevCaptureHook.getDefaultMevCaptureMultiplier();

        uint256 newDefaultMevCaptureMultiplier = 1e18;

        assertNotEq(
            firstDefaultMevCaptureMultiplier,
            newDefaultMevCaptureMultiplier,
            "New defaultMevCaptureMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.DefaultMevCaptureMultiplierSet(newDefaultMevCaptureMultiplier);
        _mevCaptureHook.setDefaultMevCaptureMultiplier(newDefaultMevCaptureMultiplier);
        assertEq(
            _mevCaptureHook.getDefaultMevCaptureMultiplier(),
            newDefaultMevCaptureMultiplier,
            "defaultMevCaptureMultiplier is not correct"
        );
    }

    function testSetDefaultMevCaptureMultiplierRegisteredPool() public {
        vm.prank(admin);
        _mevCaptureHook.setPoolMevCaptureMultiplier(pool, 5e18);

        vm.prank(admin);
        _mevCaptureHook.setDefaultMevCaptureMultiplier(1e18);

        assertNotEq(
            _mevCaptureHook.getDefaultMevCaptureMultiplier(),
            _mevCaptureHook.getPoolMevCaptureMultiplier(pool),
            "setDefaultMevCaptureMultiplier changed pool multiplier."
        );
    }

    /********************************************************
                   getDefaultMevCaptureThreshold()
    ********************************************************/

    function testGetDefaultMevCaptureThresholdStartingState() public view {
        assertEq(
            _mevCaptureHook.getDefaultMevCaptureThreshold(),
            0,
            "Default MEV Capture Threshold is not 0 after hook creation."
        );
    }

    /********************************************************
                   setDefaultMevCaptureThreshold()
    ********************************************************/

    function testSetDefaultMevCaptureThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setDefaultMevCaptureThreshold(1e18);
    }

    function testSetDefaultMevCaptureThreshold() public {
        uint256 firstDefaultMevCaptureThreshold = _mevCaptureHook.getDefaultMevCaptureThreshold();

        uint256 newDefaultMevCaptureThreshold = 1e18;

        assertNotEq(
            firstDefaultMevCaptureThreshold,
            newDefaultMevCaptureThreshold,
            "New defaultMevCaptureThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.DefaultMevCaptureThresholdSet(newDefaultMevCaptureThreshold);
        _mevCaptureHook.setDefaultMevCaptureThreshold(newDefaultMevCaptureThreshold);
        assertEq(
            _mevCaptureHook.getDefaultMevCaptureThreshold(),
            newDefaultMevCaptureThreshold,
            "defaultMevCaptureThreshold is not correct"
        );
    }

    function testSetDefaultMevCaptureThresholdRegisteredPool() public {
        vm.prank(admin);
        _mevCaptureHook.setPoolMevCaptureThreshold(pool, 5e18);

        vm.prank(admin);
        _mevCaptureHook.setDefaultMevCaptureThreshold(1e18);

        assertNotEq(
            _mevCaptureHook.getDefaultMevCaptureThreshold(),
            _mevCaptureHook.getPoolMevCaptureThreshold(pool),
            "setDefaultMevCaptureThreshold changed pool threshold."
        );
    }

    /********************************************************
                   getPoolMevCaptureMultiplier()
    ********************************************************/

    function testGetPoolMevCaptureMultiplierPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.getPoolMevCaptureMultiplier(pool);
    }

    /********************************************************
                   setPoolMevCaptureMultiplier()
    ********************************************************/

    function testSetPoolMevCaptureMultiplierPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        address newHook = createHook();

        authorizer.grantRole(
            IAuthentication(newHook).getActionId(IMevCaptureHook.setPoolMevCaptureMultiplier.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.setPoolMevCaptureMultiplier(pool, 5e18);
    }

    function testSetPoolMevCaptureMultiplierIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setPoolMevCaptureMultiplier(pool, 5e18);
    }

    function testSetPoolMevCaptureMultiplier() public {
        uint256 firstPoolMevCaptureMultiplier = _mevCaptureHook.getPoolMevCaptureMultiplier(pool);
        uint256 firstDefaultMevCaptureMultiplier = _mevCaptureHook.getDefaultMevCaptureMultiplier();

        uint256 newPoolMevCaptureMultiplier = 5e18;

        assertNotEq(
            firstPoolMevCaptureMultiplier,
            newPoolMevCaptureMultiplier,
            "New defaultMevCaptureMultiplier cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.PoolMevCaptureMultiplierSet(pool, newPoolMevCaptureMultiplier);
        _mevCaptureHook.setPoolMevCaptureMultiplier(pool, newPoolMevCaptureMultiplier);
        assertEq(
            _mevCaptureHook.getPoolMevCaptureMultiplier(pool),
            newPoolMevCaptureMultiplier,
            "poolMevCaptureMultiplier is not correct"
        );

        assertEq(
            _mevCaptureHook.getDefaultMevCaptureMultiplier(),
            firstDefaultMevCaptureMultiplier,
            "Default multiplier changed"
        );
    }

    /********************************************************
                   getPoolMevCaptureThreshold()
    ********************************************************/

    function testGetPoolMevCaptureThresholdPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        createHook();

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.getPoolMevCaptureThreshold(pool);
    }

    /********************************************************
                   setPoolMevCaptureThreshold()
    ********************************************************/

    function testSetPoolMevCaptureThresholdPoolNotRegistered() public {
        // Creates a new hook and stores into _mevCaptureHook, so the pool won't be registered with the new MevCaptureHook.
        address newHook = createHook();

        authorizer.grantRole(
            IAuthentication(newHook).getActionId(IMevCaptureHook.setPoolMevCaptureThreshold.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureHookNotRegisteredInPool.selector, pool));
        _mevCaptureHook.setPoolMevCaptureThreshold(pool, 5e18);
    }

    function testSetPoolMevCaptureThresholdIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.setPoolMevCaptureThreshold(pool, 5e18);
    }

    function testSetPoolMevCaptureThreshold() public {
        uint256 firstPoolMevCaptureThreshold = _mevCaptureHook.getPoolMevCaptureThreshold(pool);
        uint256 firstDefaultMevCaptureThreshold = _mevCaptureHook.getDefaultMevCaptureThreshold();

        uint256 newPoolMevCaptureThreshold = 5e18;

        assertNotEq(
            firstPoolMevCaptureThreshold,
            newPoolMevCaptureThreshold,
            "New defaultMevCaptureThreshold cannot be equal to current value"
        );

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.PoolMevCaptureThresholdSet(pool, newPoolMevCaptureThreshold);
        _mevCaptureHook.setPoolMevCaptureThreshold(pool, newPoolMevCaptureThreshold);
        assertEq(
            _mevCaptureHook.getPoolMevCaptureThreshold(pool),
            newPoolMevCaptureThreshold,
            "poolMevCaptureThreshold is not correct"
        );

        assertEq(
            _mevCaptureHook.getDefaultMevCaptureThreshold(),
            firstDefaultMevCaptureThreshold,
            "Default threshold changed"
        );
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
        _mevCaptureHook.setPoolMevCaptureThreshold(pool, threshold);
        _mevCaptureHook.setPoolMevCaptureMultiplier(pool, multiplier);
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
                   addMevCaptureExemptSenders
    ********************************************************/

    function testAddMevCaptureExemptSendersIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.addMevCaptureExemptSenders([address(1), address(2)].toMemoryArray());
    }

    function testAddMevCaptureExemptSenders() public {
        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MevCaptureExemptSenderAdded(lp);
        vm.expectEmit();
        emit IMevCaptureHook.MevCaptureExemptSenderAdded(bob);
        vm.expectEmit();
        emit IMevCaptureHook.MevCaptureExemptSenderAdded(alice);
        _mevCaptureHook.addMevCaptureExemptSenders([lp, bob, alice].toMemoryArray());
        assertTrue(_mevCaptureHook.isMevCaptureExempt(lp), "LP was not added properly as MEV capture-exempt");
        assertTrue(_mevCaptureHook.isMevCaptureExempt(bob), "Bob was not added properly as MEV capture-exempt");
        assertTrue(_mevCaptureHook.isMevCaptureExempt(alice), "Alice was not added properly as MEV capture-exempt");
    }

    function testAddMevCaptureExemptSendersRevertsWithDuplicated() public {
        vm.prank(admin);
        _mevCaptureHook.addMevCaptureExemptSenders([lp, bob, alice].toMemoryArray());

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.MevCaptureExemptSenderAlreadyAdded.selector, bob));
        vm.prank(admin);
        _mevCaptureHook.addMevCaptureExemptSenders([bob].toMemoryArray());
    }

    /********************************************************
                   removeMevCaptureExemptSenders
    ********************************************************/

    function testRemoveMevCaptureExemptSendersIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _mevCaptureHook.removeMevCaptureExemptSenders([alice, bob].toMemoryArray());
    }

    function testRemoveMevCaptureExemptSenders() public {
        vm.prank(admin);
        _mevCaptureHook.addMevCaptureExemptSenders([lp, bob, alice].toMemoryArray());

        vm.prank(admin);
        vm.expectEmit();
        emit IMevCaptureHook.MevCaptureExemptSenderRemoved(lp);
        vm.expectEmit();
        emit IMevCaptureHook.MevCaptureExemptSenderRemoved(alice);
        _mevCaptureHook.removeMevCaptureExemptSenders([lp, alice].toMemoryArray());

        assertTrue(_mevCaptureHook.isMevCaptureExempt(bob), "Bob was not added properly as MEV capture-exempt");
        assertFalse(_mevCaptureHook.isMevCaptureExempt(lp), "LP was not removed properly as MEV capture-exempt");
        assertFalse(_mevCaptureHook.isMevCaptureExempt(alice), "Alice was not removed properly as MEV capture-exempt");
    }

    function testRemoveMevCaptureExemptSendersRevertsIfNotExist() public {
        vm.prank(admin);
        _mevCaptureHook.addMevCaptureExemptSenders([lp, alice].toMemoryArray());

        vm.expectRevert(abi.encodeWithSelector(IMevCaptureHook.SenderNotRegisteredAsMevCaptureExempt.selector, bob));
        vm.prank(admin);
        _mevCaptureHook.removeMevCaptureExemptSenders([bob].toMemoryArray());
    }

    /********************************************************
                       isMevCaptureExempt
    ********************************************************/

    function testIsMevCaptureExempt() public {
        vm.prank(admin);
        _mevCaptureHook.addMevCaptureExemptSenders([lp, alice].toMemoryArray());

        assertTrue(_mevCaptureHook.isMevCaptureExempt(lp), "LP is not exempt");
        assertFalse(_mevCaptureHook.isMevCaptureExempt(bob), "Bob is exempt");
        assertTrue(_mevCaptureHook.isMevCaptureExempt(alice), "Alice is not exempt");
    }
}
