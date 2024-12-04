// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ProtocolFeeControllerMock } from "../../contracts/test/ProtocolFeeControllerMock.sol";
import { ProtocolFeeController } from "../../contracts/ProtocolFeeController.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolFeeControllerTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 internal constant LOW_PROTOCOL_SWAP_FEE_PCT = 20e16; // 20%
    uint256 internal constant CUSTOM_PROTOCOL_SWAP_FEE_PCT = 30e16; // 30%
    uint256 internal constant MAX_PROTOCOL_SWAP_FEE_PCT = 50e16; // 50%

    uint256 internal constant LOW_PROTOCOL_YIELD_FEE_PCT = 10e16; // 10%
    uint256 internal constant CUSTOM_PROTOCOL_YIELD_FEE_PCT = 40e16; // 40%
    uint256 internal constant MAX_PROTOCOL_YIELD_FEE_PCT = 50e16; // 50%

    uint256 internal constant POOL_CREATOR_SWAP_FEE_PCT = 40e16; // 40%
    uint256 internal constant POOL_CREATOR_YIELD_FEE_PCT = 10e16; // 10%

    uint256 internal constant PROTOCOL_SWAP_FEE_AMOUNT = 100e18;
    uint256 internal constant PROTOCOL_YIELD_FEE_AMOUNT = 50e18;

    IAuthentication feeControllerAuth;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        BaseVaultTest.setUp();

        feeControllerAuth = IAuthentication(address(feeController));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testInitialization() public view {
        assertEq(address(feeController.vault()), address(vault));

        // Fees should initialize to 0
        assertEq(feeController.getGlobalProtocolSwapFeePercentage(), 0, "Global swap fee percentage is non-zero");
        assertEq(feeController.getGlobalProtocolYieldFeePercentage(), 0, "Global yield fee percentage is non-zero");

        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol swap fee percentage is non-zero");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol yield fee percentage is non-zero");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        uint256[] memory feeAmounts = feeController.getProtocolFeeAmounts(pool);
        assertEq(feeAmounts[0], 0, "Collected protocol fee amount [0] is non-zero");
        assertEq(feeAmounts[1], 0, "Collected protocol fee amount [1] is non-zero");

        feeAmounts = feeController.getPoolCreatorFeeAmounts(pool);
        assertEq(feeAmounts[0], 0, "Collected creator fee amount [0] is non-zero");
        assertEq(feeAmounts[1], 0, "Collected creator fee amount [1] is non-zero");
    }

    function testSetGlobalProtocolSwapFeePercentageRange() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(LOW_PROTOCOL_SWAP_FEE_PCT);

        assertEq(
            feeController.getGlobalProtocolSwapFeePercentage(),
            LOW_PROTOCOL_SWAP_FEE_PCT,
            "Global swap fee != LOW"
        );

        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE_PCT);

        assertEq(
            feeController.getGlobalProtocolSwapFeePercentage(),
            MAX_PROTOCOL_SWAP_FEE_PCT,
            "Global swap fee != MAX"
        );
    }

    function testSetGlobalProtocolYieldFeePercentageRange() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(LOW_PROTOCOL_YIELD_FEE_PCT);

        assertEq(
            feeController.getGlobalProtocolYieldFeePercentage(),
            LOW_PROTOCOL_YIELD_FEE_PCT,
            "Global yield fee != LOW"
        );

        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE_PCT);

        assertEq(
            feeController.getGlobalProtocolYieldFeePercentage(),
            MAX_PROTOCOL_YIELD_FEE_PCT,
            "Global yield fee != MAX"
        );
    }

    function testSetGlobalProtocolSwapFeePercentagePermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeController.setGlobalProtocolSwapFeePercentage(0);
    }

    function testSetGlobalProtocolYieldFeePercentagePermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeController.setGlobalProtocolYieldFeePercentage(0);
    }

    function testSetPoolCreatorSwapFeePercentageAboveMAx() public {
        uint256 maxCreatorFeePct = ProtocolFeeController(address(feeController)).MAX_CREATOR_FEE_PERCENTAGE();

        vm.expectRevert(IProtocolFeeController.PoolCreatorFeePercentageTooHigh.selector);
        vm.prank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, maxCreatorFeePct + 1);
    }

    function testSetPoolCreatorYieldFeePercentageAboveMAx() public {
        uint256 maxCreatorFeePct = ProtocolFeeController(address(feeController)).MAX_CREATOR_FEE_PERCENTAGE();

        vm.expectRevert(IProtocolFeeController.PoolCreatorFeePercentageTooHigh.selector);
        vm.prank(lp);
        feeController.setPoolCreatorYieldFeePercentage(pool, maxCreatorFeePct + 1);
    }

    function testSetGlobalProtocolSwapFeePercentageTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolSwapFeePercentageTooHigh.selector);
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE_PCT + 1);
    }

    function testSetGlobalProtocolYieldFeePercentageTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolYieldFeePercentageTooHigh.selector);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE_PCT + 1);
    }

    function testSetGlobalProtocolSwapFeePercentageEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeController.GlobalProtocolSwapFeePercentageChanged(MAX_PROTOCOL_SWAP_FEE_PCT);

        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE_PCT);
    }

    function testSetGlobalProtocolYieldFeePercentageEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeController.GlobalProtocolYieldFeePercentageChanged(MAX_PROTOCOL_YIELD_FEE_PCT);

        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE_PCT);
    }

    function testPoolRegistration() public {
        // When we deploy a pool, it should call registerPool on the controller, and get the default percentages
        // (and correct aggregates).
        _registerPoolWithMaxProtocolFees();

        _verifyPoolProtocolFeePercentages(pool);
    }

    function testPoolRegistrationWithCreatorFee() public {
        _registerPoolWithMaxProtocolFees();

        // Aggregate percentages with no creator fee should just be the global fee percentages.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        assertEq(
            poolConfigBits.aggregateSwapFeePercentage,
            MAX_PROTOCOL_SWAP_FEE_PCT,
            "Pool aggregate swap fee != MAX"
        );
        assertEq(
            poolConfigBits.aggregateYieldFeePercentage,
            MAX_PROTOCOL_YIELD_FEE_PCT,
            "Pool aggregate yield fee != MAX"
        );

        // Setting the creator fee is a permissioned call.
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, alice, pool));
        vm.prank(alice);
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE_PCT);

        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, alice, pool));
        vm.prank(alice);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE_PCT);

        // Governance cannot override it.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setPoolCreatorSwapFeePercentage.selector),
            bob
        );
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, bob, pool));
        vm.prank(bob);
        feeController.setPoolCreatorSwapFeePercentage(pool, 0);

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setPoolCreatorYieldFeePercentage.selector),
            bob
        );
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, bob, pool));
        vm.prank(bob);
        feeController.setPoolCreatorYieldFeePercentage(pool, 0);

        // Now set the pool creator fees (only creator).
        vm.startPrank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE_PCT);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE_PCT);
        vm.stopPrank();

        (address poolCreator, uint256 poolCreatorSwapFee, uint256 poolCreatorYieldFee) = ProtocolFeeControllerMock(
            address(feeController)
        ).getPoolCreatorInfo(pool);
        assertEq(poolCreator, lp, "Pool creator != lp");
        assertEq(poolCreatorSwapFee, POOL_CREATOR_SWAP_FEE_PCT, "Wrong Pool Creator swap fee");
        assertEq(poolCreatorYieldFee, POOL_CREATOR_YIELD_FEE_PCT, "Wrong Pool Creator yield fee");

        // Pool percentages should be the same.
        _verifyPoolProtocolFeePercentages(pool);

        // But aggregates should be different.
        uint256 expectedAggregateSwapFee = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_SWAP_FEE_PCT,
            POOL_CREATOR_SWAP_FEE_PCT
        );
        uint256 expectedAggregateYieldFee = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_YIELD_FEE_PCT,
            POOL_CREATOR_YIELD_FEE_PCT
        );

        poolConfigBits = vault.getPoolConfig(pool);
        assertEq(poolConfigBits.aggregateSwapFeePercentage, expectedAggregateSwapFee, "Wrong aggregate swap fee");
        assertEq(poolConfigBits.aggregateYieldFeePercentage, expectedAggregateYieldFee, "Wrong aggregate yield fee");
    }

    function testSettingPoolProtocolSwapFee() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Pool creator can't do it.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        feeController.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE_PCT);

        // Have governance override a swap fee.
        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE_PCT);

        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_SWAP_FEE_PCT, "Pool protocol swap fee != CUSTOM");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");

        // Other one unaffected
        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol yield fee != 0");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        // Check that pool config has the right value.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        assertEq(poolConfigBits.aggregateSwapFeePercentage, CUSTOM_PROTOCOL_SWAP_FEE_PCT);
    }

    function testProtocolSwapFeeLowResolution__Fuzz(uint256 extraFee) public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        vm.prank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, 0);

        // Add bits to the fee, but keep them >= 24 bits.
        extraFee = bound(
            uint256(extraFee),
            FEE_SCALING_FACTOR,
            MAX_PROTOCOL_SWAP_FEE_PCT - CUSTOM_PROTOCOL_SWAP_FEE_PCT
        );

        uint256 lowPrecisionFee = ((CUSTOM_PROTOCOL_SWAP_FEE_PCT + extraFee) / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;

        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, lowPrecisionFee);

        // Retrieve it from the Vault - should be the same as we set.
        PoolConfig memory config = vault.getPoolConfig(pool);
        assertEq(config.aggregateSwapFeePercentage, lowPrecisionFee);
    }

    function testProtocolSwapFeeHighResolution__Fuzz(uint16 precisionFee) public {
        // Add some bits that make it higher than 24-bit resolution.
        uint256 highPrecisionBits = bound(uint256(precisionFee), 1, FEE_SCALING_FACTOR - 1);

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        vm.prank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, 0);

        uint256 highPrecisionFee = CUSTOM_PROTOCOL_SWAP_FEE_PCT + highPrecisionBits;

        vm.prank(admin);
        vm.expectRevert(IVaultErrors.FeePrecisionTooHigh.selector);
        feeController.setProtocolSwapFeePercentage(pool, highPrecisionFee);
    }

    function testProtocolYieldFeeLowResolution__Fuzz(uint256 extraFee) public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        vm.prank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, 0);

        // Add bits to the fee, but keep them >= 24 bits.
        extraFee = bound(
            uint256(extraFee),
            FEE_SCALING_FACTOR,
            MAX_PROTOCOL_YIELD_FEE_PCT - CUSTOM_PROTOCOL_YIELD_FEE_PCT
        );

        uint256 lowPrecisionFee = ((CUSTOM_PROTOCOL_YIELD_FEE_PCT + extraFee) / FEE_SCALING_FACTOR) *
            FEE_SCALING_FACTOR;

        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, lowPrecisionFee);

        // Retrieve it from the Vault - should be the same as we set.
        PoolConfig memory config = vault.getPoolConfig(pool);
        assertEq(config.aggregateYieldFeePercentage, lowPrecisionFee);
    }

    function testProtocolYieldFeeHighResolution__Fuzz(uint16 precisionFee) public {
        // Add some bits that make it higher than 24-bit resolution.
        uint256 highPrecisionBits = bound(uint256(precisionFee), 1, FEE_SCALING_FACTOR - 1);

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        vm.prank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, 0);

        uint256 highPrecisionFee = CUSTOM_PROTOCOL_YIELD_FEE_PCT + highPrecisionBits;

        vm.prank(admin);
        vm.expectRevert(IVaultErrors.FeePrecisionTooHigh.selector);
        feeController.setProtocolYieldFeePercentage(pool, highPrecisionFee);
    }

    function testSettingPoolProtocolSwapFeeTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Have governance override a swap fee.
        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolSwapFeePercentageTooHigh.selector);
        feeController.setProtocolSwapFeePercentage(pool, MAX_PROTOCOL_SWAP_FEE_PCT + 1);
    }

    function testSettingPoolProtocolSwapFeeEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IVaultEvents.AggregateSwapFeePercentageChanged(pool, CUSTOM_PROTOCOL_SWAP_FEE_PCT);
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolSwapFeePercentageChanged(pool, CUSTOM_PROTOCOL_SWAP_FEE_PCT);

        // Have governance override a swap fee.
        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE_PCT);
    }

    function testSettingPoolProtocolYieldFee() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Pool creator can't do it.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        feeController.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE_PCT);

        // Have governance override a yield fee.
        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE_PCT);

        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_YIELD_FEE_PCT, "Pool protocol yield fee != CUSTOM");
        assertTrue(isOverride, "Pool protocol yield fee is not an override");

        // Other one unaffected
        (feePercentage, isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol swap fee != 0");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        // Check that pool config has the right value.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        assertEq(poolConfigBits.aggregateYieldFeePercentage, CUSTOM_PROTOCOL_YIELD_FEE_PCT);
    }

    function testSettingPoolProtocolYieldFeeTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Have governance override a swap fee.
        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolYieldFeePercentageTooHigh.selector);
        feeController.setProtocolYieldFeePercentage(pool, MAX_PROTOCOL_YIELD_FEE_PCT + 1);
    }

    function testSettingPoolProtocolYieldFeeEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IVaultEvents.AggregateYieldFeePercentageChanged(pool, CUSTOM_PROTOCOL_YIELD_FEE_PCT);
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolYieldFeePercentageChanged(pool, CUSTOM_PROTOCOL_YIELD_FEE_PCT);

        // Have governance override a swap fee.
        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE_PCT);
    }

    function testUpdateProtocolSwapFeePercentage() public {
        // Permissionless call to update a pool swap fee percentage to the global value:
        // IF it is different, and IF it hasn't been overridden by governance.
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        // This checks that events weren't emitted.
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Calling update now will do nothing, as it hasn't changed.
        feeController.updateProtocolSwapFeePercentage(pool);
        assertEq(entries.length, 0, "swap fee update emitted an event");

        // And nothing changed.
        _verifyPoolProtocolFeePercentages(pool);

        // Now change the global one.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(CUSTOM_PROTOCOL_SWAP_FEE_PCT);

        // Should be able to call, and it will update.
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolSwapFeePercentageChanged(pool, CUSTOM_PROTOCOL_SWAP_FEE_PCT);

        // Permissionless; use default caller.
        feeController.updateProtocolSwapFeePercentage(pool);

        // Should be changed, and still no override.
        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_SWAP_FEE_PCT, "Pool protocol swap fee != CUSTOM");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        // Now let governance set it high.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, MAX_PROTOCOL_SWAP_FEE_PCT);

        // Should be changed again, and now an override.
        (feePercentage, isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE_PCT, "Pool protocol swap fee != MAX");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");

        // Global fee is still the custom one.
        assertEq(feeController.getGlobalProtocolSwapFeePercentage(), CUSTOM_PROTOCOL_SWAP_FEE_PCT);

        // Change the global one.
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(LOW_PROTOCOL_SWAP_FEE_PCT);

        // Now trying to change it permissionlessly will do nothing.
        feeController.updateProtocolSwapFeePercentage(pool);
        (feePercentage, isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE_PCT, "Pool protocol swap fee != MAX");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");
    }

    function testUpdateProtocolYieldFeePercentage() public {
        // Permissionless call to update a pool swap fee percentage to the global value:
        // IF it is different, and IF it hasn't been overridden by governance.
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        // This checks that events weren't emitted.
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Calling update now will do nothing, as it hasn't changed.
        feeController.updateProtocolYieldFeePercentage(pool);
        assertEq(entries.length, 0, "yield fee update emitted an event");

        // And nothing changed.
        _verifyPoolProtocolFeePercentages(pool);

        // Now change the global one.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(CUSTOM_PROTOCOL_YIELD_FEE_PCT);

        // Should be able to call, and it will update.
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolYieldFeePercentageChanged(pool, CUSTOM_PROTOCOL_YIELD_FEE_PCT);

        // Permissionless; use default caller.
        feeController.updateProtocolYieldFeePercentage(pool);

        // Should be changed, and still no override.
        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_YIELD_FEE_PCT, "Pool protocol yield fee != CUSTOM");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        // Now let governance set it high.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, MAX_PROTOCOL_YIELD_FEE_PCT);

        // Should be changed again, and now an override.
        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE_PCT, "Pool protocol yield fee != MAX");
        assertTrue(isOverride, "Pool protocol yield fee is not an override");

        // Global fee is still the custom one.
        assertEq(feeController.getGlobalProtocolYieldFeePercentage(), CUSTOM_PROTOCOL_YIELD_FEE_PCT);

        // Change the global one.
        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(LOW_PROTOCOL_YIELD_FEE_PCT);

        // Now trying to change it permissionlessly will do nothing.
        feeController.updateProtocolYieldFeePercentage(pool);
        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE_PCT, "Pool protocol yield fee != MAX");
        assertTrue(isOverride, "Pool protocol yield fee is not an override");
    }

    function testWithdrawalByNonPoolCreator() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, alice, pool));
        vm.prank(alice);
        feeController.withdrawPoolCreatorFees(pool, alice);
    }

    function testMaxPoolCreatorAndProtocolSwapFees() public {
        // Protocol fees will be zero.
        (pool, ) = createPool();

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Set valid value at the limit of precision.
        vm.startPrank(admin);
        feeController.setProtocolSwapFeePercentage(
            pool,
            ProtocolFeeController(address(feeController)).MAX_PROTOCOL_SWAP_FEE_PERCENTAGE()
        );
        vm.stopPrank();

        // Set max pool creator fees
        vm.startPrank(lp);
        feeController.setPoolCreatorSwapFeePercentage(
            pool,
            ProtocolFeeController(address(feeController)).MAX_CREATOR_FEE_PERCENTAGE()
        );

        // Aggregate swap fee percentage should be smaller than the max allowed.
        (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage) = IPoolInfo(pool)
            .getAggregateFeePercentages();
        assertLe(aggregateSwapFeePercentage, MAX_FEE_PERCENTAGE, "Aggregate swap fee exceeds max (~100%)");
        assertEq(aggregateYieldFeePercentage, 0, "Aggregate yield fee is not zero");
    }

    function testMaxPoolCreatorAndProtocolYieldFees() public {
        // Protocol fees will be zero.
        (pool, ) = createPool();

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Set valid value at the limit of precision.
        vm.startPrank(admin);
        feeController.setProtocolYieldFeePercentage(
            pool,
            ProtocolFeeController(address(feeController)).MAX_PROTOCOL_YIELD_FEE_PERCENTAGE()
        );
        vm.stopPrank();

        // Set max pool creator fees
        vm.startPrank(lp);
        feeController.setPoolCreatorYieldFeePercentage(
            pool,
            ProtocolFeeController(address(feeController)).MAX_CREATOR_FEE_PERCENTAGE()
        );

        // Aggregate yield fee percentage should be smaller than the max allowed.
        (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage) = IPoolInfo(pool)
            .getAggregateFeePercentages();
        assertLe(aggregateYieldFeePercentage, MAX_FEE_PERCENTAGE, "Aggregate yield fee exceeds max (~100%)");
        assertEq(aggregateSwapFeePercentage, 0, "Aggregate swap fee is not zero");
    }

    function testPermissionlessWithdrawalByNonPoolCreator() public {
        _registerPoolWithMaxProtocolFees();

        vm.startPrank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE_PCT);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE_PCT);
        vm.stopPrank();

        vault.manualSetAggregateSwapFeeAmount(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        uint256 aggregateSwapFeePercentage = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_SWAP_FEE_PCT,
            POOL_CREATOR_SWAP_FEE_PCT
        );
        uint256 aggregateYieldFeePercentage = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_YIELD_FEE_PCT,
            POOL_CREATOR_YIELD_FEE_PCT
        );

        uint256 expectedProtocolFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT.divUp(aggregateSwapFeePercentage).mulUp(
            MAX_PROTOCOL_SWAP_FEE_PCT
        );
        uint256 expectedCreatorFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT - expectedProtocolFeeDAI;

        uint256 expectedProtocolFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT.divUp(aggregateYieldFeePercentage).mulUp(
            MAX_PROTOCOL_YIELD_FEE_PCT
        );
        uint256 expectedCreatorFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT - expectedProtocolFeeUSDC;

        uint256 creatorBalanceDAIBefore = dai.balanceOf(lp);
        uint256 creatorBalanceUSDCBefore = usdc.balanceOf(lp);

        feeController.collectAggregateFees(pool);
        feeController.withdrawPoolCreatorFees(pool);

        assertEq(
            dai.balanceOf(lp) - creatorBalanceDAIBefore,
            expectedCreatorFeeDAI,
            "Wrong ending balance of DAI (creator)"
        );
        assertEq(
            usdc.balanceOf(lp) - creatorBalanceUSDCBefore,
            expectedCreatorFeeUSDC,
            "Wrong ending balance of USDC (creator)"
        );
    }

    function testWithdrawalWithNoCreator() public {
        PoolMock newPool = deployPoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

        factoryMock.registerTestPool(address(newPool), vault.buildTokenConfig(tokens));

        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.PoolCreatorNotRegistered.selector, newPool));
        vm.prank(alice);
        feeController.withdrawPoolCreatorFees(address(newPool), alice);
    }

    function testProtocolFeeCollection() public {
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        require(vault.getAggregateSwapFeeAmount(pool, dai) == 0, "Non-zero initial DAI protocol swap fees");
        require(vault.getAggregateSwapFeeAmount(pool, usdc) == 0, "Non-zero initial USDC protocol swap fees");

        require(vault.getAggregateYieldFeeAmount(pool, dai) == 0, "Non-zero initial DAI protocol yield fees");
        require(vault.getAggregateYieldFeeAmount(pool, usdc) == 0, "Non-zero initial USDC protocol yield fees");

        // Set a creator fee percentage (before there are any fees), so they will be disaggregated upon collection.
        vm.startPrank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE_PCT);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE_PCT);
        vm.stopPrank();

        // Check that the aggregate percentages are set in the pool config.
        uint256 expectedSwapFeePercentage = MAX_PROTOCOL_SWAP_FEE_PCT +
            MAX_PROTOCOL_SWAP_FEE_PCT.complement().mulDown(POOL_CREATOR_SWAP_FEE_PCT);
        uint256 expectedYieldFeePercentage = MAX_PROTOCOL_YIELD_FEE_PCT +
            MAX_PROTOCOL_YIELD_FEE_PCT.complement().mulDown(POOL_CREATOR_YIELD_FEE_PCT);

        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        assertEq(poolConfigBits.aggregateSwapFeePercentage, expectedSwapFeePercentage);
        assertEq(poolConfigBits.aggregateYieldFeePercentage, expectedYieldFeePercentage);

        vault.manualSetAggregateSwapFeeAmount(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        // Pool should have the protocol swap and yield fees.
        assertEq(vault.getAggregateSwapFeeAmount(pool, dai), PROTOCOL_SWAP_FEE_AMOUNT, "Wrong DAI protocol swap fees");
        assertEq(vault.getAggregateSwapFeeAmount(pool, usdc), 0, "Non-zero USDC protocol swap fees");

        assertEq(vault.getAggregateYieldFeeAmount(pool, dai), 0, "Non-zero DAI protocol yield fees");
        assertEq(
            vault.getAggregateYieldFeeAmount(pool, usdc),
            PROTOCOL_YIELD_FEE_AMOUNT,
            "Wrong USDC protocol yield fees"
        );

        uint256 reservesOfDaiBeforeCollect = vault.getReservesOf(dai);
        uint256 reservesOfUsdcBeforeCollect = vault.getReservesOf(usdc);

        // Collecting fees will emit events, and call `receiveAggregateFees`.
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolSwapFeeCollected(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);

        vm.expectEmit();
        emit IProtocolFeeController.ProtocolYieldFeeCollected(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        uint256[] memory swapAmounts = new uint256[](2);
        uint256[] memory yieldAmounts = new uint256[](2);
        swapAmounts[daiIdx] = PROTOCOL_SWAP_FEE_AMOUNT;
        yieldAmounts[usdcIdx] = PROTOCOL_YIELD_FEE_AMOUNT;

        vm.expectCall(address(feeController), abi.encodeCall(ProtocolFeeController.collectAggregateFeesHook, pool));
        // Move them to the fee controller.
        feeController.collectAggregateFees(pool);

        // Now the fee controller should have them - and the Vault should be zero.
        assertEq(vault.getAggregateSwapFeeAmount(pool, dai), 0, "Non-zero post-collection DAI protocol swap fees");
        assertEq(vault.getAggregateSwapFeeAmount(pool, usdc), 0, "Non-zero post-collection USDC protocol swap fees");
        assertEq(vault.getAggregateYieldFeeAmount(pool, dai), 0, "Non-zero post-collection DAI protocol yield fees");
        assertEq(vault.getAggregateYieldFeeAmount(pool, usdc), 0, "Non-zero post-collection USDC protocol yield fees");

        assertEq(dai.balanceOf(address(feeController)), PROTOCOL_SWAP_FEE_AMOUNT);
        assertEq(usdc.balanceOf(address(feeController)), PROTOCOL_YIELD_FEE_AMOUNT);

        uint256[] memory protocolFeeAmounts = feeController.getProtocolFeeAmounts(pool);
        uint256[] memory poolCreatorFeeAmounts = feeController.getPoolCreatorFeeAmounts(pool);

        // Check reserves.
        assertEq(
            vault.getReservesOf(dai),
            reservesOfDaiBeforeCollect - protocolFeeAmounts[daiIdx] - poolCreatorFeeAmounts[daiIdx],
            "DAI: Incorrect Vault reserves"
        );
        assertEq(
            vault.getReservesOf(usdc),
            reservesOfUsdcBeforeCollect - protocolFeeAmounts[usdcIdx] - poolCreatorFeeAmounts[usdcIdx],
            "USDC: Incorrect Vault reserves"
        );

        uint256 aggregateSwapFeePercentage = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_SWAP_FEE_PCT,
            POOL_CREATOR_SWAP_FEE_PCT
        );
        uint256 aggregateYieldFeePercentage = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_YIELD_FEE_PCT,
            POOL_CREATOR_YIELD_FEE_PCT
        );

        uint256 expectedProtocolFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT.divUp(aggregateSwapFeePercentage).mulUp(
            MAX_PROTOCOL_SWAP_FEE_PCT
        );
        uint256 expectedCreatorFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT - expectedProtocolFeeDAI;

        assertEq(expectedProtocolFeeDAI, protocolFeeAmounts[daiIdx], "Wrong disaggregated DAI protocol fee amount");
        assertEq(
            expectedCreatorFeeDAI,
            poolCreatorFeeAmounts[daiIdx],
            "Wrong disaggregated DAI pool creator fee amount"
        );

        uint256 expectedProtocolFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT.divUp(aggregateYieldFeePercentage).mulUp(
            MAX_PROTOCOL_YIELD_FEE_PCT
        );
        uint256 expectedCreatorFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT - expectedProtocolFeeUSDC;

        assertEq(expectedProtocolFeeUSDC, protocolFeeAmounts[usdcIdx], "Wrong disaggregated USDC protocol fee amount");
        assertEq(
            expectedCreatorFeeUSDC,
            poolCreatorFeeAmounts[usdcIdx],
            "Wrong disaggregated USDC pool creator fee amount"
        );

        // `withdrawPoolCreatorFees` is overloaded.
        bytes4 permissionedSelector = bytes4(keccak256("withdrawPoolCreatorFees(address,address)"));

        // Now all that's left is to withdraw them.
        // Governance cannot withdraw creator fees.
        authorizer.grantRole(feeControllerAuth.getActionId(permissionedSelector), admin);
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, admin, pool));
        vm.prank(admin);
        feeController.withdrawPoolCreatorFees(pool, admin);

        // Creator cannot withdraw protocol fees.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        feeController.withdrawProtocolFees(pool, lp);

        uint256 adminBalanceDAIBefore = dai.balanceOf(admin);
        uint256 adminBalanceUSDCBefore = usdc.balanceOf(admin);

        uint256 creatorBalanceDAIBefore = dai.balanceOf(lp);
        uint256 creatorBalanceUSDCBefore = usdc.balanceOf(lp);

        // Governance can withdraw.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.withdrawProtocolFees.selector),
            admin
        );

        vm.prank(admin);
        feeController.withdrawProtocolFees(pool, admin);

        // Should be zeroed out in the controller.
        protocolFeeAmounts = feeController.getProtocolFeeAmounts(pool);
        assertEq(protocolFeeAmounts[0], 0, "Non-zero protocol fee amounts after withdrawal [0]");
        assertEq(protocolFeeAmounts[1], 0, "Non-zero protocol fee amounts after withdrawal [1]");

        assertEq(
            dai.balanceOf(admin) - adminBalanceDAIBefore,
            expectedProtocolFeeDAI,
            "Wrong ending balance of DAI (protocol)"
        );
        assertEq(
            usdc.balanceOf(admin) - adminBalanceUSDCBefore,
            expectedProtocolFeeUSDC,
            "Wrong ending balance of USDC (protocol)"
        );

        vm.prank(lp);
        feeController.withdrawPoolCreatorFees(pool, lp);

        // Should be zeroed out in the controller.
        poolCreatorFeeAmounts = feeController.getPoolCreatorFeeAmounts(pool);
        assertEq(poolCreatorFeeAmounts[0], 0, "Non-zero creator fee amounts after withdrawal [0]");
        assertEq(poolCreatorFeeAmounts[1], 0, "Non-zero creator fee amounts after withdrawal [1]");

        assertEq(
            dai.balanceOf(lp) - creatorBalanceDAIBefore,
            expectedCreatorFeeDAI,
            "Wrong ending balance of DAI (creator)"
        );
        assertEq(
            usdc.balanceOf(lp) - creatorBalanceUSDCBefore,
            expectedCreatorFeeUSDC,
            "Wrong ending balance of USDC (creator)"
        );
    }

    function testProtocolFeeCollectionEvents() public {
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        // Set a creator fee percentage (before there are any fees), so they will be disaggregated upon collection.
        vm.startPrank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE_PCT);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE_PCT);
        vm.stopPrank();

        vault.manualSetAggregateSwapFeeAmount(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        // Move them to the fee controller.
        feeController.collectAggregateFees(pool);

        uint256[] memory protocolFeeAmounts = feeController.getProtocolFeeAmounts(pool);
        uint256[] memory poolCreatorFeeAmounts = feeController.getPoolCreatorFeeAmounts(pool);

        // Governance can withdraw.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.withdrawProtocolFees.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeController.ProtocolFeesWithdrawn(pool, IERC20(dai), admin, protocolFeeAmounts[daiIdx]);

        vm.expectEmit();
        emit IProtocolFeeController.ProtocolFeesWithdrawn(pool, IERC20(usdc), admin, protocolFeeAmounts[usdcIdx]);

        vm.prank(admin);
        feeController.withdrawProtocolFees(pool, admin);

        vm.expectEmit();
        emit IProtocolFeeController.PoolCreatorFeesWithdrawn(pool, IERC20(dai), bob, poolCreatorFeeAmounts[daiIdx]);

        vm.expectEmit();
        emit IProtocolFeeController.PoolCreatorFeesWithdrawn(pool, IERC20(usdc), bob, poolCreatorFeeAmounts[usdcIdx]);

        // Test permissioned collection of pool creator fees.
        vm.prank(lp);
        feeController.withdrawPoolCreatorFees(pool, bob);

        // Reset fees for permissionless test.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);
        feeController.collectAggregateFees(pool);

        vm.expectEmit();
        emit IProtocolFeeController.PoolCreatorFeesWithdrawn(pool, IERC20(dai), lp, poolCreatorFeeAmounts[daiIdx]);

        vm.expectEmit();
        emit IProtocolFeeController.PoolCreatorFeesWithdrawn(pool, IERC20(usdc), lp, poolCreatorFeeAmounts[usdcIdx]);

        // Test permissionless collection of pool creator fees.
        feeController.withdrawPoolCreatorFees(pool);
    }

    function testProtocolFeeCollectionForToken() public {
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        uint256 expectedProtocolFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT;
        uint256 expectedProtocolFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT;

        vault.manualSetAggregateSwapFeeAmount(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        // Move them to the fee controller.
        feeController.collectAggregateFees(pool);

        uint256[] memory protocolFeeAmounts = feeController.getProtocolFeeAmounts(pool);

        // Governance can withdraw.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.withdrawProtocolFeesForToken.selector),
            admin
        );

        uint256 adminBalanceDAIBefore = IERC20(dai).balanceOf(admin);
        uint256 adminBalanceUSDCBefore = IERC20(usdc).balanceOf(admin);

        vm.expectEmit();
        emit IProtocolFeeController.ProtocolFeesWithdrawn(pool, IERC20(dai), admin, protocolFeeAmounts[daiIdx]);

        vm.prank(admin);
        feeController.withdrawProtocolFeesForToken(pool, admin, IERC20(dai));

        // Dai should be collected, USDC should not.
        protocolFeeAmounts = feeController.getProtocolFeeAmounts(pool);
        assertEq(protocolFeeAmounts[daiIdx], 0, "Non-zero protocol fee amounts after withdrawal [dai]");
        assertEq(
            protocolFeeAmounts[usdcIdx],
            expectedProtocolFeeUSDC,
            "Non-zero protocol fee amounts after withdrawal [usdc]"
        );

        assertEq(
            dai.balanceOf(admin) - adminBalanceDAIBefore,
            expectedProtocolFeeDAI,
            "Wrong ending balance of DAI (protocol)"
        );
        assertEq(usdc.balanceOf(admin), adminBalanceUSDCBefore, "Wrong ending balance of USDC (protocol)");
    }

    function testWithdrawProtocolFeesPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeController.withdrawProtocolFees(pool, alice);
    }

    function testWithdrawProtocolFeesPoolNotRegistered() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.withdrawProtocolFees.selector),
            admin
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0xbeef)));
        vm.prank(admin);
        feeController.withdrawProtocolFees(address(0xbeef), alice);
    }

    function testWithdrawProtocolFeesForTokenPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeController.withdrawProtocolFeesForToken(pool, alice, IERC20(dai));
    }

    function testWithdrawProtocolFeesForTokenPoolNotRegistered() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.withdrawProtocolFeesForToken.selector),
            admin
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotRegistered.selector, address(0xbeef)));
        vm.prank(admin);
        feeController.withdrawProtocolFeesForToken(address(0xbeef), alice, IERC20(dai));
    }

    function testWithdrawProtocolFeesForTokenInvalidToken() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.withdrawProtocolFeesForToken.selector),
            admin
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.TokenNotRegistered.selector, IERC20(weth)));
        vm.prank(admin);
        feeController.withdrawProtocolFeesForToken(pool, alice, IERC20(weth));
    }

    function testSetMaliciousGlobalFeePercentages() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.startPrank(admin);
        vm.expectRevert(IVaultErrors.FeePrecisionTooHigh.selector);
        feeController.setGlobalProtocolSwapFeePercentage(CUSTOM_PROTOCOL_SWAP_FEE_PCT + 1234567890123);

        vm.expectRevert(IVaultErrors.FeePrecisionTooHigh.selector);
        feeController.setGlobalProtocolYieldFeePercentage(CUSTOM_PROTOCOL_SWAP_FEE_PCT + 123456890123);
        vm.stopPrank();
    }

    function testAdjustedSwapFeePrecision() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Set valid value at the limit of precision.
        vm.prank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, FEE_SCALING_FACTOR);

        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE_PCT);

        uint256 fullPrecisionAggregateFeePercentage = CUSTOM_PROTOCOL_SWAP_FEE_PCT +
            CUSTOM_PROTOCOL_SWAP_FEE_PCT.complement().mulDown(FEE_SCALING_FACTOR);

        // Full precision should not equal the nominal value
        assertNotEq(fullPrecisionAggregateFeePercentage, CUSTOM_PROTOCOL_SWAP_FEE_PCT, "Fee precision lost");

        uint256 correctedFeePercentage = (fullPrecisionAggregateFeePercentage / FEE_SCALING_FACTOR) *
            FEE_SCALING_FACTOR;
        assertEq(correctedFeePercentage, CUSTOM_PROTOCOL_SWAP_FEE_PCT, "Fee precision not adjusted");

        // Retrieve it from the Vault - should be the same as we set.
        PoolConfig memory config = vault.getPoolConfig(pool);
        assertEq(
            config.aggregateSwapFeePercentage,
            CUSTOM_PROTOCOL_SWAP_FEE_PCT,
            "Wrong aggregate swap fee percentage"
        );
    }

    function testAdjustedSwapFeePrecision__Fuzz(
        uint256 protocolSwapFeePercentage,
        uint256 poolCreatorFeePercentage
    ) public {
        protocolSwapFeePercentage = bound(protocolSwapFeePercentage, FEE_SCALING_FACTOR, MAX_PROTOCOL_SWAP_FEE_PCT);
        poolCreatorFeePercentage = bound(
            poolCreatorFeePercentage,
            FEE_SCALING_FACTOR,
            ProtocolFeeController(address(feeController)).MAX_CREATOR_FEE_PERCENTAGE()
        );

        // Ensure valid precision of each component.
        protocolSwapFeePercentage = (protocolSwapFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;
        poolCreatorFeePercentage = (poolCreatorFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Set valid value at the limit of precision.
        vm.prank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, poolCreatorFeePercentage);

        // Mainly checking that this doesn't revert.
        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, protocolSwapFeePercentage);

        uint256 expectedAggregatePercentage = feeController.computeAggregateFeePercentage(
            protocolSwapFeePercentage,
            poolCreatorFeePercentage
        );

        // Retrieve it from the Vault - should be the same as we set.
        PoolConfig memory config = vault.getPoolConfig(pool);
        assertEq(config.aggregateSwapFeePercentage, expectedAggregatePercentage, "Wrong aggregate swap fee percentage");
    }

    function testAdjustedYieldFeePrecision() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Set valid value at the limit of precision.
        vm.prank(lp);
        feeController.setPoolCreatorYieldFeePercentage(pool, FEE_SCALING_FACTOR);

        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE_PCT);

        uint256 fullPrecisionAggregateFeePercentage = CUSTOM_PROTOCOL_YIELD_FEE_PCT +
            CUSTOM_PROTOCOL_YIELD_FEE_PCT.complement().mulDown(FEE_SCALING_FACTOR);

        // Full precision should not equal the nominal value
        assertNotEq(fullPrecisionAggregateFeePercentage, CUSTOM_PROTOCOL_YIELD_FEE_PCT, "Fee precision lost");

        uint256 correctedFeePercentage = (fullPrecisionAggregateFeePercentage / FEE_SCALING_FACTOR) *
            FEE_SCALING_FACTOR;
        assertEq(correctedFeePercentage, CUSTOM_PROTOCOL_YIELD_FEE_PCT, "Fee precision not adjusted");

        // Retrieve it from the Vault - should be the same as we set.
        PoolConfig memory config = vault.getPoolConfig(pool);
        assertEq(
            config.aggregateYieldFeePercentage,
            CUSTOM_PROTOCOL_YIELD_FEE_PCT,
            "Wrong aggregate yield fee percentage"
        );
    }

    function testAdjustedYieldFeePrecision__Fuzz(
        uint256 protocolYieldFeePercentage,
        uint256 poolCreatorFeePercentage
    ) public {
        protocolYieldFeePercentage = bound(protocolYieldFeePercentage, FEE_SCALING_FACTOR, MAX_PROTOCOL_YIELD_FEE_PCT);
        poolCreatorFeePercentage = bound(
            poolCreatorFeePercentage,
            FEE_SCALING_FACTOR,
            ProtocolFeeController(address(feeController)).MAX_CREATOR_FEE_PERCENTAGE()
        );

        // Ensure valid precision of each component.
        protocolYieldFeePercentage = (protocolYieldFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;
        poolCreatorFeePercentage = (poolCreatorFeePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Set valid value at the limit of precision.
        vm.prank(lp);
        feeController.setPoolCreatorYieldFeePercentage(pool, poolCreatorFeePercentage);

        // Mainly checking that this doesn't revert.
        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, protocolYieldFeePercentage);

        uint256 expectedAggregatePercentage = feeController.computeAggregateFeePercentage(
            protocolYieldFeePercentage,
            poolCreatorFeePercentage
        );

        // Retrieve it from the Vault - should be the same as we set.
        PoolConfig memory config = vault.getPoolConfig(pool);
        assertEq(
            config.aggregateYieldFeePercentage,
            expectedAggregatePercentage,
            "Wrong aggregate swap fee percentage"
        );
    }

    function testConstants() public view {
        uint256 maxCreatorFeePercentage = ProtocolFeeController(address(feeController)).MAX_CREATOR_FEE_PERCENTAGE();

        // Creator fee percentage is pretty close to max fee percentage.
        assertGe(maxCreatorFeePercentage, 99.99e16, "Max creator fee percentage abs value");
        assertApproxEqAbs(maxCreatorFeePercentage, MAX_FEE_PERCENTAGE, 0.001e16, "Max fee percentage too far off");

        uint256 maxProtocolSwapFeePercentage = ProtocolFeeController(address(feeController))
            .MAX_PROTOCOL_SWAP_FEE_PERCENTAGE();
        uint256 maxProtocolYieldFeePercentage = ProtocolFeeController(address(feeController))
            .MAX_PROTOCOL_YIELD_FEE_PERCENTAGE();

        uint256 expectedSwapAggregatePercentage = feeController.computeAggregateFeePercentage(
            maxProtocolSwapFeePercentage,
            maxCreatorFeePercentage
        );

        uint256 expectedYieldAggregatePercentage = feeController.computeAggregateFeePercentage(
            maxProtocolYieldFeePercentage,
            maxCreatorFeePercentage
        );

        assertLe(
            expectedSwapAggregatePercentage,
            MAX_FEE_PERCENTAGE,
            "Maximum possible aggregate fee percentage is above max allowed"
        );
        assertLe(
            expectedYieldAggregatePercentage,
            MAX_FEE_PERCENTAGE,
            "Maximum possible aggregate fee percentage is above max allowed"
        );
    }

    function _registerPoolWithMaxProtocolFees() internal {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.startPrank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE_PCT);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE_PCT);
        vm.stopPrank();

        (pool, ) = createPool();
    }

    function _verifyPoolProtocolFeePercentages(address pool) internal view {
        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);

        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE_PCT, "Wrong protocol swap fee percentage");
        assertFalse(isOverride, "swap fee percentage override is true");

        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);

        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE_PCT, "Wrong protocol yield fee percentage");
        assertFalse(isOverride, "yield fee percentage override is true");
    }
}
