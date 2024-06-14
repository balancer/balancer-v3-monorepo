// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ProtocolFeeControllerMock } from "../../contracts/test/ProtocolFeeControllerMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolFeeControllerTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 internal constant LOW_PROTOCOL_SWAP_FEE = 20e16;
    uint256 internal constant CUSTOM_PROTOCOL_SWAP_FEE = 30e16;
    uint256 internal constant MAX_PROTOCOL_SWAP_FEE = 50e16;

    uint256 internal constant LOW_PROTOCOL_YIELD_FEE = 10e16;
    uint256 internal constant CUSTOM_PROTOCOL_YIELD_FEE = 40e16;
    uint256 internal constant MAX_PROTOCOL_YIELD_FEE = 50e16;

    uint256 internal constant POOL_CREATOR_SWAP_FEE = 40e16;
    uint256 internal constant POOL_CREATOR_YIELD_FEE = 10e16;

    uint256 internal constant PROTOCOL_SWAP_FEE_AMOUNT = 100e18;
    uint256 internal constant PROTOCOL_YIELD_FEE_AMOUNT = 50e18;

    IProtocolFeeController feeController;
    IAuthentication feeControllerAuth;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        BaseVaultTest.setUp();

        feeController = vault.getProtocolFeeController();
        feeControllerAuth = IAuthentication(address(feeController));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testInitialization() public {
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
        feeController.setGlobalProtocolSwapFeePercentage(LOW_PROTOCOL_SWAP_FEE);

        assertEq(feeController.getGlobalProtocolSwapFeePercentage(), LOW_PROTOCOL_SWAP_FEE, "Global swap fee != LOW");

        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);

        assertEq(feeController.getGlobalProtocolSwapFeePercentage(), MAX_PROTOCOL_SWAP_FEE, "Global swap fee != MAX");
    }

    function testSetGlobalProtocolYieldFeePercentageRange() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(LOW_PROTOCOL_YIELD_FEE);

        assertEq(
            feeController.getGlobalProtocolYieldFeePercentage(),
            LOW_PROTOCOL_YIELD_FEE,
            "Global yield fee != LOW"
        );

        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);

        assertEq(
            feeController.getGlobalProtocolYieldFeePercentage(),
            MAX_PROTOCOL_YIELD_FEE,
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

    function testSetGlobalProtocolSwapFeePercentageTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolSwapFeePercentageTooHigh.selector);
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE + 1);
    }

    function testSetGlobalProtocolYieldFeePercentageTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolYieldFeePercentageTooHigh.selector);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE + 1);
    }

    function testSetGlobalProtocolSwapFeePercentageEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeController.GlobalProtocolSwapFeePercentageChanged(MAX_PROTOCOL_SWAP_FEE);

        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
    }

    function testSetGlobalProtocolYieldFeePercentageEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeController.GlobalProtocolYieldFeePercentageChanged(MAX_PROTOCOL_YIELD_FEE);

        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
    }

    function testPoolRegistration() public {
        // When we deploy a pool, it should call registerPool on the controller, and get the default percentages
        // (and correct aggregates).
        _registerPoolWithMaxProtocolFees();

        _verifyPoolProtocolFeePercentages(pool);
    }

    function testPoolRegistrationWithCreatorFee() public {
        _registerPoolWithMaxProtocolFees();

        // Aggregate percentage with no creator fee should just be the global fee percentages
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        assertEq(poolConfigBits.aggregateSwapFeePercentage, MAX_PROTOCOL_SWAP_FEE, "Pool aggregate swap fee != MAX");
        assertEq(poolConfigBits.aggregateYieldFeePercentage, MAX_PROTOCOL_YIELD_FEE, "Pool aggregate yield fee != MAX");

        // Setting the creator fee is a permissioned call.
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, alice));
        vm.prank(alice);
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE);

        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, alice));
        vm.prank(alice);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE);

        // Governance cannot override it.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setPoolCreatorSwapFeePercentage.selector),
            bob
        );
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, bob));
        vm.prank(bob);
        feeController.setPoolCreatorSwapFeePercentage(pool, 0);

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setPoolCreatorYieldFeePercentage.selector),
            bob
        );
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, bob));
        vm.prank(bob);
        feeController.setPoolCreatorYieldFeePercentage(pool, 0);

        // Now set the pool creator fees (only creator).
        vm.startPrank(lp);
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE);
        vm.stopPrank();

        (address poolCreator, uint256 poolCreatorSwapFee, uint256 poolCreatorYieldFee) = ProtocolFeeControllerMock(
            address(feeController)
        ).getPoolCreatorInfo(pool);
        assertEq(poolCreator, lp, "Pool creator != lp");
        assertEq(poolCreatorSwapFee, POOL_CREATOR_SWAP_FEE, "Wrong Pool Creator swap fee");
        assertEq(poolCreatorYieldFee, POOL_CREATOR_YIELD_FEE, "Wrong Pool Creator yield fee");

        // Pool percentages should be the same
        _verifyPoolProtocolFeePercentages(pool);

        // But aggregates should be different
        uint256 expectedAggregateSwapFee = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_SWAP_FEE,
            POOL_CREATOR_SWAP_FEE
        );
        uint256 expectedAggregateYieldFee = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_YIELD_FEE,
            POOL_CREATOR_YIELD_FEE
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
        feeController.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        // Have governance override a swap fee
        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_SWAP_FEE, "Pool protocol swap fee != CUSTOM");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");

        // Other one unaffected
        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol yield fee != 0");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        // Check that pool config has the right value
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        assertEq(poolConfigBits.aggregateSwapFeePercentage, CUSTOM_PROTOCOL_SWAP_FEE);
    }

    function testSettingPoolProtocolSwapFeeTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Have governance override a swap fee
        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolSwapFeePercentageTooHigh.selector);
        feeController.setProtocolSwapFeePercentage(pool, MAX_PROTOCOL_SWAP_FEE + 1);
    }

    function testSettingPoolProtocolSwapFeeEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeController.ProtocolSwapFeePercentageChanged(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        // Have governance override a swap fee
        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE);
    }

    function testSettingPoolProtocolYieldFee() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Pool creator can't do it.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        feeController.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        // Have governance override a yield fee
        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != CUSTOM");
        assertTrue(isOverride, "Pool protocol yield fee is not an override");

        // Other one unaffected
        (feePercentage, isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol swap fee != 0");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        // Check that pool config has the right value
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        assertEq(poolConfigBits.aggregateYieldFeePercentage, CUSTOM_PROTOCOL_YIELD_FEE);
    }

    function testSettingPoolProtocolYieldFeeTooHigh() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Have governance override a swap fee
        vm.prank(admin);
        vm.expectRevert(IProtocolFeeController.ProtocolYieldFeePercentageTooHigh.selector);
        feeController.setProtocolYieldFeePercentage(pool, MAX_PROTOCOL_YIELD_FEE + 1);
    }

    function testSettingPoolProtocolYieldFeeEvent() public {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeController.ProtocolYieldFeePercentageChanged(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        // Have governance override a swap fee
        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE);
    }

    function testUpdateProtocolSwapFeePercentage() public {
        // Permissionless call to update a pool swap fee percentage to the global value:
        // IF it is different, and IF it hasn't been overridden by governance.
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        // Way to check that events weren't emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Calling update now will do nothing, as it hasn't changed
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
        feeController.setGlobalProtocolSwapFeePercentage(CUSTOM_PROTOCOL_SWAP_FEE);

        // Should be able to call, and it will update.
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolSwapFeePercentageChanged(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        // Permissionless; use default caller.
        feeController.updateProtocolSwapFeePercentage(pool);

        // Should be changed, and still no override.
        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_SWAP_FEE, "Pool protocol swap fee != CUSTOM");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        // Now let governance set it high.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setProtocolSwapFeePercentage(pool, MAX_PROTOCOL_SWAP_FEE);

        // Should be changed again, and now an override.
        (feePercentage, isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE, "Pool protocol swap fee != MAX");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");

        // Global fee is still the custom one
        assertEq(feeController.getGlobalProtocolSwapFeePercentage(), CUSTOM_PROTOCOL_SWAP_FEE);

        // Change the global one
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(LOW_PROTOCOL_SWAP_FEE);

        // Now trying to change it permissionlessly will do nothing
        feeController.updateProtocolSwapFeePercentage(pool);
        (feePercentage, isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE, "Pool protocol swap fee != MAX");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");
    }

    function testUpdateProtocolYieldFeePercentage() public {
        // Permissionless call to update a pool swap fee percentage to the global value:
        // IF it is different, and IF it hasn't been overridden by governance.
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        // Way to check that events weren't emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Calling update now will do nothing, as it hasn't changed
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
        feeController.setGlobalProtocolYieldFeePercentage(CUSTOM_PROTOCOL_YIELD_FEE);

        // Should be able to call, and it will update.
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolYieldFeePercentageChanged(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        // Permissionless; use default caller.
        feeController.updateProtocolYieldFeePercentage(pool);

        // Should be changed, and still no override.
        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != CUSTOM");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        // Now let governance set it high.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setProtocolYieldFeePercentage(pool, MAX_PROTOCOL_YIELD_FEE);

        // Should be changed again, and now an override.
        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != MAX");
        assertTrue(isOverride, "Pool protocol uield fee is not an override");

        // Global fee is still the custom one
        assertEq(feeController.getGlobalProtocolYieldFeePercentage(), CUSTOM_PROTOCOL_YIELD_FEE);

        // Change the global one
        vm.prank(admin);
        feeController.setGlobalProtocolYieldFeePercentage(LOW_PROTOCOL_YIELD_FEE);

        // Now trying to change it permissionlessly will do nothing
        feeController.updateProtocolYieldFeePercentage(pool);
        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != MAX");
        assertTrue(isOverride, "Pool protocol yield fee is not an override");
    }

    function testWithdrawalByNonPoolCreator() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, alice));
        vm.prank(alice);
        feeController.withdrawPoolCreatorFees(pool, alice);
    }

    function testWithdrawalWithNoCreator() public {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

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
        feeController.setPoolCreatorSwapFeePercentage(pool, POOL_CREATOR_SWAP_FEE);
        feeController.setPoolCreatorYieldFeePercentage(pool, POOL_CREATOR_YIELD_FEE);
        vm.stopPrank();

        // Check that the aggregate percentages are set in the pool config
        uint256 expectedSwapFeePercentage = MAX_PROTOCOL_SWAP_FEE +
            MAX_PROTOCOL_SWAP_FEE.complement().mulDown(POOL_CREATOR_SWAP_FEE);
        uint256 expectedYieldFeePercentage = MAX_PROTOCOL_YIELD_FEE +
            MAX_PROTOCOL_YIELD_FEE.complement().mulDown(POOL_CREATOR_YIELD_FEE);

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

        // Collecting fees will emit events, and call `receiveAggregateFees`.
        vm.expectEmit();
        emit IProtocolFeeController.ProtocolSwapFeeCollected(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);

        vm.expectEmit();
        emit IProtocolFeeController.ProtocolYieldFeeCollected(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        uint256[] memory swapAmounts = new uint256[](2);
        uint256[] memory yieldAmounts = new uint256[](2);
        swapAmounts[daiIdx] = PROTOCOL_SWAP_FEE_AMOUNT;
        yieldAmounts[usdcIdx] = PROTOCOL_YIELD_FEE_AMOUNT;

        vm.expectCall(
            address(feeController),
            abi.encodeWithSelector(
                IProtocolFeeController.receiveAggregateFees.selector,
                pool,
                swapAmounts,
                yieldAmounts
            )
        );
        // Move them to the fee controller.
        vault.collectAggregateFees(pool);

        // Now the fee controller should have them - and the Vault should be zero.
        assertEq(vault.getAggregateSwapFeeAmount(pool, dai), 0, "Non-zero post-collection DAI protocol swap fees");
        assertEq(vault.getAggregateSwapFeeAmount(pool, usdc), 0, "Non-zero post-collection USDC protocol swap fees");
        assertEq(vault.getAggregateYieldFeeAmount(pool, dai), 0, "Non-zero post-collection DAI protocol yield fees");
        assertEq(vault.getAggregateYieldFeeAmount(pool, usdc), 0, "Non-zero post-collection USDC protocol yield fees");

        assertEq(dai.balanceOf(address(feeController)), PROTOCOL_SWAP_FEE_AMOUNT);
        assertEq(usdc.balanceOf(address(feeController)), PROTOCOL_YIELD_FEE_AMOUNT);

        uint256[] memory protocolFeeAmounts = feeController.getProtocolFeeAmounts(pool);
        uint256[] memory poolCreatorFeeAmounts = feeController.getPoolCreatorFeeAmounts(pool);

        uint256 aggregateSwapFeePercentage = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_SWAP_FEE,
            POOL_CREATOR_SWAP_FEE
        );
        uint256 aggregateYieldFeePercentage = feeController.computeAggregateFeePercentage(
            MAX_PROTOCOL_YIELD_FEE,
            POOL_CREATOR_YIELD_FEE
        );

        uint256 expectedProtocolFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT.divUp(aggregateSwapFeePercentage).mulUp(
            MAX_PROTOCOL_SWAP_FEE
        );
        uint256 expectedCreatorFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT - expectedProtocolFeeDAI;

        assertEq(expectedProtocolFeeDAI, protocolFeeAmounts[daiIdx], "Wrong disaggregated DAI protocol fee amount");
        assertEq(
            expectedCreatorFeeDAI,
            poolCreatorFeeAmounts[daiIdx],
            "Wrong disaggregated DAI pool creator fee amount"
        );

        uint256 expectedProtocolFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT.divUp(aggregateYieldFeePercentage).mulUp(
            MAX_PROTOCOL_YIELD_FEE
        );
        uint256 expectedCreatorFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT - expectedProtocolFeeUSDC;

        assertEq(expectedProtocolFeeUSDC, protocolFeeAmounts[usdcIdx], "Wrong disaggregated USDC protocol fee amount");
        assertEq(
            expectedCreatorFeeUSDC,
            poolCreatorFeeAmounts[usdcIdx],
            "Wrong disaggregated USDC pool creator fee amount"
        );

        // Now all that's left is to withdraw them.
        // Governance cannot withdraw creator fees
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.withdrawPoolCreatorFees.selector),
            admin
        );
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeController.CallerIsNotPoolCreator.selector, admin));
        vm.prank(admin);
        feeController.withdrawPoolCreatorFees(pool, admin);

        // Creator cannot withdraw protocol fees
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

        // Should be zeroed out in the controller
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

        // Should be zeroed out in the controller
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
        feeController.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
        feeController.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
        vm.stopPrank();

        pool = createPool();
    }

    function _verifyPoolProtocolFeePercentages(address pool) internal {
        (uint256 feePercentage, bool isOverride) = feeController.getPoolProtocolSwapFeeInfo(pool);

        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE);
        assertFalse(isOverride);

        (feePercentage, isOverride) = feeController.getPoolProtocolYieldFeeInfo(pool);

        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE);
        assertFalse(isOverride);
    }
}
