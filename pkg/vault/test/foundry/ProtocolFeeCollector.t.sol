// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { ProtocolFeeCollectorMock } from "../../contracts/test/ProtocolFeeCollectorMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolFeeCollectorTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 internal constant LOW_PROTOCOL_SWAP_FEE = 20e16;
    uint256 internal constant CUSTOM_PROTOCOL_SWAP_FEE = 30e16;
    uint256 internal constant MAX_PROTOCOL_SWAP_FEE = 50e16;

    uint256 internal constant LOW_PROTOCOL_YIELD_FEE = 10e16;
    uint256 internal constant CUSTOM_PROTOCOL_YIELD_FEE = 40e16;
    uint256 internal constant MAX_PROTOCOL_YIELD_FEE = 50e16;

    uint256 internal constant POOL_CREATOR_FEE = 50e16;

    uint256 internal constant PROTOCOL_SWAP_FEE_AMOUNT = 100e18;
    uint256 internal constant PROTOCOL_YIELD_FEE_AMOUNT = 50e18;

    IProtocolFeeCollector feeCollector;
    IAuthentication feeCollectorAuth;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        BaseVaultTest.setUp();

        feeCollector = vault.getProtocolFeeCollector();
        feeCollectorAuth = IAuthentication(address(feeCollector));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testInitialization() public {
        assertEq(address(feeCollector.vault()), address(vault));

        // Fees should initialize to 0
        assertEq(feeCollector.getGlobalProtocolSwapFeePercentage(), 0, "Global swap fee percentage is non-zero");
        assertEq(feeCollector.getGlobalProtocolYieldFeePercentage(), 0, "Global yield fee percentage is non-zero");

        (uint256 feePercentage, bool isOverride) = feeCollector.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol swap fee percentage is non-zero");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        (feePercentage, isOverride) = feeCollector.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol yield fee percentage is non-zero");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        uint256[] memory feeAmounts = feeCollector.getAggregateProtocolFeeAmounts(pool);
        assertEq(feeAmounts[0], 0, "Collected protocol fee amount [0] is non-zero");
        assertEq(feeAmounts[1], 0, "Collected protocol fee amount [1] is non-zero");

        feeAmounts = feeCollector.getAggregatePoolCreatorFeeAmounts(pool);
        assertEq(feeAmounts[0], 0, "Collected creator fee amount [0] is non-zero");
        assertEq(feeAmounts[1], 0, "Collected creator fee amount [1] is non-zero");
    }

    function testSetGlobalProtocolSwapFeePercentageRange() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeCollector.setGlobalProtocolSwapFeePercentage(LOW_PROTOCOL_SWAP_FEE);

        assertEq(feeCollector.getGlobalProtocolSwapFeePercentage(), LOW_PROTOCOL_SWAP_FEE, "Global swap fee != LOW");

        vm.prank(admin);
        feeCollector.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);

        assertEq(feeCollector.getGlobalProtocolSwapFeePercentage(), MAX_PROTOCOL_SWAP_FEE, "Global swap fee != MAX");
    }

    function testSetGlobalProtocolYieldFeePercentageRange() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeCollector.setGlobalProtocolYieldFeePercentage(LOW_PROTOCOL_YIELD_FEE);

        assertEq(feeCollector.getGlobalProtocolYieldFeePercentage(), LOW_PROTOCOL_YIELD_FEE, "Global yield fee != LOW");

        vm.prank(admin);
        feeCollector.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);

        assertEq(feeCollector.getGlobalProtocolYieldFeePercentage(), MAX_PROTOCOL_YIELD_FEE, "Global yield fee != MAX");
    }

    function testSetGlobalProtocolSwapFeePercentagePermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeCollector.setGlobalProtocolSwapFeePercentage(0);
    }

    function testSetGlobalProtocolYieldFeePercentagePermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        feeCollector.setGlobalProtocolYieldFeePercentage(0);
    }

    function testSetGlobalProtocolSwapFeePercentageTooHigh() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(IProtocolFeeCollector.ProtocolSwapFeePercentageTooHigh.selector);
        feeCollector.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE + 1);
    }

    function testSetGlobalProtocolYieldFeePercentageTooHigh() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.prank(admin);
        vm.expectRevert(IProtocolFeeCollector.ProtocolYieldFeePercentageTooHigh.selector);
        feeCollector.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE + 1);
    }

    function testSetGlobalProtocolSwapFeePercentageEvent() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeCollector.GlobalProtocolSwapFeePercentageChanged(MAX_PROTOCOL_SWAP_FEE);

        vm.prank(admin);
        feeCollector.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
    }

    function testSetGlobalProtocolYieldFeePercentageEvent() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeCollector.GlobalProtocolYieldFeePercentageChanged(MAX_PROTOCOL_YIELD_FEE);

        vm.prank(admin);
        feeCollector.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
    }

    function testPoolRegistration() public {
        // When we deploy a pool, it should call registerPool on the collector, and get the default percentages
        // (and correct aggregates).
        _registerPoolWithMaxProtocolFees();

        _verifyPoolProtocolFeePercentages(pool);
    }

    function testPoolRegistrationWithCreatorFee() public {
        _registerPoolWithMaxProtocolFees();

        // Aggregate percentage with no creator fee should just be the global fee percentages
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(
            poolConfig.poolState.aggregateProtocolSwapFeePercentage,
            MAX_PROTOCOL_SWAP_FEE,
            "Pool aggregate swap fee != MAX"
        );
        assertEq(
            poolConfig.poolState.aggregateProtocolYieldFeePercentage,
            MAX_PROTOCOL_YIELD_FEE,
            "Pool aggregate yield fee != MAX"
        );

        // Setting the creator fee is a permissioned call.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setPoolCreatorFeePercentage(pool, POOL_CREATOR_FEE);

        // Governance cannot override it.
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setPoolCreatorFeePercentage.selector), bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(bob);
        vault.setPoolCreatorFeePercentage(pool, 0);

        // Now set the pool creator fee (only creator).
        vm.prank(lp);
        vault.setPoolCreatorFeePercentage(pool, POOL_CREATOR_FEE);

        (address poolCreator, uint256 poolCreatorFee) = vault.getPoolCreatorInfo(pool);
        assertEq(poolCreator, lp, "Pool creator != lp");
        assertEq(poolCreatorFee, POOL_CREATOR_FEE, "Wrong Pool Creator fee");

        // Pool percentages should be the same
        _verifyPoolProtocolFeePercentages(pool);

        // But aggregates should be different
        uint256 expectedAggregateSwapFee = ProtocolFeeCollectorMock(address(feeCollector)).getAggregateFeePercentage(
            MAX_PROTOCOL_SWAP_FEE,
            POOL_CREATOR_FEE
        );
        uint256 expectedAggregateYieldFee = ProtocolFeeCollectorMock(address(feeCollector)).getAggregateFeePercentage(
            MAX_PROTOCOL_YIELD_FEE,
            POOL_CREATOR_FEE
        );

        poolConfig = vault.getPoolConfig(pool);
        assertEq(
            poolConfig.poolState.aggregateProtocolSwapFeePercentage,
            expectedAggregateSwapFee,
            "Wrong aggregate swap fee"
        );
        assertEq(
            poolConfig.poolState.aggregateProtocolYieldFeePercentage,
            expectedAggregateYieldFee,
            "Wrong aggregate yield fee"
        );
    }

    function testSettingPoolProtocolSwapFee() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Pool creator can't do it.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        feeCollector.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        // Have governance override a swap fee
        vm.prank(admin);
        feeCollector.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        (uint256 feePercentage, bool isOverride) = feeCollector.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_SWAP_FEE, "Pool protocol swap fee != CUSTOM");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");

        // Other one unaffected
        (feePercentage, isOverride) = feeCollector.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol yield fee != 0");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        // Check that pool config has the right value
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(poolConfig.poolState.aggregateProtocolSwapFeePercentage, CUSTOM_PROTOCOL_SWAP_FEE);
    }

    function testSettingPoolProtocolSwapFeeTooHigh() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolSwapFeePercentage.selector),
            admin
        );

        // Have governance override a swap fee
        vm.prank(admin);
        vm.expectRevert(IProtocolFeeCollector.ProtocolSwapFeePercentageTooHigh.selector);
        feeCollector.setProtocolSwapFeePercentage(pool, MAX_PROTOCOL_SWAP_FEE + 1);
    }

    function testSettingPoolProtocolSwapFeeEvent() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolSwapFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeCollector.ProtocolSwapFeePercentageChanged(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        // Have governance override a swap fee
        vm.prank(admin);
        feeCollector.setProtocolSwapFeePercentage(pool, CUSTOM_PROTOCOL_SWAP_FEE);
    }

    function testSettingPoolProtocolYieldFee() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Pool creator can't do it.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        feeCollector.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        // Have governance override a yield fee
        vm.prank(admin);
        feeCollector.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        (uint256 feePercentage, bool isOverride) = feeCollector.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != CUSTOM");
        assertTrue(isOverride, "Pool protocol yield fee is not an override");

        // Other one unaffected
        (feePercentage, isOverride) = feeCollector.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, 0, "Pool protocol swap fee != 0");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        // Check that pool config has the right value
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(poolConfig.poolState.aggregateProtocolYieldFeePercentage, CUSTOM_PROTOCOL_YIELD_FEE);
    }

    function testSettingPoolProtocolYieldFeeTooHigh() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolYieldFeePercentage.selector),
            admin
        );

        // Have governance override a swap fee
        vm.prank(admin);
        vm.expectRevert(IProtocolFeeCollector.ProtocolYieldFeePercentageTooHigh.selector);
        feeCollector.setProtocolYieldFeePercentage(pool, MAX_PROTOCOL_YIELD_FEE + 1);
    }

    function testSettingPoolProtocolYieldFeeEvent() public {
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolYieldFeePercentage.selector),
            admin
        );

        vm.expectEmit();
        emit IProtocolFeeCollector.ProtocolYieldFeePercentageChanged(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        // Have governance override a swap fee
        vm.prank(admin);
        feeCollector.setProtocolYieldFeePercentage(pool, CUSTOM_PROTOCOL_YIELD_FEE);
    }

    function testUpdateProtocolSwapFeePercentage() public {
        // Permissionless call to update a pool swap fee percentage to the global value:
        // IF it is different, and IF it hasn't been overridden by governance.
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        // Way to check that events weren't emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Calling update now will do nothing, as it hasn't changed
        feeCollector.updateProtocolSwapFeePercentage(pool);
        assertEq(entries.length, 0, "swap fee update emitted an event");

        // And nothing changed.
        _verifyPoolProtocolFeePercentages(pool);

        // Now change the global one.
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeCollector.setGlobalProtocolSwapFeePercentage(CUSTOM_PROTOCOL_SWAP_FEE);

        // Should be able to call, and it will update.
        vm.expectEmit();
        emit IProtocolFeeCollector.ProtocolSwapFeePercentageChanged(pool, CUSTOM_PROTOCOL_SWAP_FEE);

        // Permissionless; use default caller.
        feeCollector.updateProtocolSwapFeePercentage(pool);

        // Should be changed, and still no override.
        (uint256 feePercentage, bool isOverride) = feeCollector.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_SWAP_FEE, "Pool protocol swap fee != CUSTOM");
        assertFalse(isOverride, "Pool protocol swap fee is an override");

        // Now let governance set it high.
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeCollector.setProtocolSwapFeePercentage(pool, MAX_PROTOCOL_SWAP_FEE);

        // Should be changed again, and now an override.
        (feePercentage, isOverride) = feeCollector.getPoolProtocolSwapFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE, "Pool protocol swap fee != MAX");
        assertTrue(isOverride, "Pool protocol swap fee is not an override");

        // Global fee is still the custom one
        assertEq(feeCollector.getGlobalProtocolSwapFeePercentage(), CUSTOM_PROTOCOL_SWAP_FEE);

        // Change the global one
        vm.prank(admin);
        feeCollector.setGlobalProtocolSwapFeePercentage(LOW_PROTOCOL_SWAP_FEE);

        // Now trying to change it permissionlessly will do nothing
        feeCollector.updateProtocolSwapFeePercentage(pool);
        (feePercentage, isOverride) = feeCollector.getPoolProtocolSwapFeeInfo(pool);
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
        feeCollector.updateProtocolYieldFeePercentage(pool);
        assertEq(entries.length, 0, "yield fee update emitted an event");

        // And nothing changed.
        _verifyPoolProtocolFeePercentages(pool);

        // Now change the global one.
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeCollector.setGlobalProtocolYieldFeePercentage(CUSTOM_PROTOCOL_YIELD_FEE);

        // Should be able to call, and it will update.
        vm.expectEmit();
        emit IProtocolFeeCollector.ProtocolYieldFeePercentageChanged(pool, CUSTOM_PROTOCOL_YIELD_FEE);

        // Permissionless; use default caller.
        feeCollector.updateProtocolYieldFeePercentage(pool);

        // Should be changed, and still no override.
        (uint256 feePercentage, bool isOverride) = feeCollector.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, CUSTOM_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != CUSTOM");
        assertFalse(isOverride, "Pool protocol yield fee is an override");

        // Now let governance set it high.
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setProtocolYieldFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeCollector.setProtocolYieldFeePercentage(pool, MAX_PROTOCOL_YIELD_FEE);

        // Should be changed again, and now an override.
        (feePercentage, isOverride) = feeCollector.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != MAX");
        assertTrue(isOverride, "Pool protocol uield fee is not an override");

        // Global fee is still the custom one
        assertEq(feeCollector.getGlobalProtocolYieldFeePercentage(), CUSTOM_PROTOCOL_YIELD_FEE);

        // Change the global one
        vm.prank(admin);
        feeCollector.setGlobalProtocolYieldFeePercentage(LOW_PROTOCOL_YIELD_FEE);

        // Now trying to change it permissionlessly will do nothing
        feeCollector.updateProtocolYieldFeePercentage(pool);
        (feePercentage, isOverride) = feeCollector.getPoolProtocolYieldFeeInfo(pool);
        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE, "Pool protocol yield fee != MAX");
        assertTrue(isOverride, "Pool protocol yield fee is not an override");
    }

    function testWithdrawalByNonPoolCreator() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeCollector.CallerIsNotPoolCreator.selector, alice));
        vm.prank(alice);
        feeCollector.withdrawPoolCreatorFees(pool, alice);
    }

    function testWithdrawalWithNoCreator() public {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");

        factoryMock.registerTestPool(address(newPool), vault.buildTokenConfig(tokens));

        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeCollector.PoolCreatorNotRegistered.selector, newPool));
        vm.prank(alice);
        feeCollector.withdrawPoolCreatorFees(address(newPool), alice);
    }

    function testProtocolFeeCollection() public {
        _registerPoolWithMaxProtocolFees();
        _verifyPoolProtocolFeePercentages(pool);

        require(vault.getAggregateProtocolSwapFeeAmount(pool, dai) == 0, "Non-zero initial DAI protocol swap fees");
        require(vault.getAggregateProtocolSwapFeeAmount(pool, usdc) == 0, "Non-zero initial USDC protocol swap fees");

        require(vault.getAggregateProtocolYieldFeeAmount(pool, dai) == 0, "Non-zero initial DAI protocol yield fees");
        require(vault.getAggregateProtocolYieldFeeAmount(pool, usdc) == 0, "Non-zero initial USDC protocol yield fees");

        // Set a creator fee percentage (before there are any fees), so they will be disaggregated upon collection.
        vm.prank(lp);
        vault.setPoolCreatorFeePercentage(pool, POOL_CREATOR_FEE);

        // Check that the aggregate percentages are set in the pool config
        uint256 expectedSwapFeePercentage = MAX_PROTOCOL_SWAP_FEE +
            MAX_PROTOCOL_SWAP_FEE.complement().mulDown(POOL_CREATOR_FEE);
        uint256 expectedYieldFeePercentage = MAX_PROTOCOL_YIELD_FEE +
            MAX_PROTOCOL_YIELD_FEE.complement().mulDown(POOL_CREATOR_FEE);

        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(poolConfig.poolState.aggregateProtocolSwapFeePercentage, expectedSwapFeePercentage);
        assertEq(poolConfig.poolState.aggregateProtocolYieldFeePercentage, expectedYieldFeePercentage);

        vault.manualSetAggregateProtocolSwapFeeAmount(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);
        vault.manualSetAggregateProtocolYieldFeeAmount(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        // Pool should have the protocol swap and yield fees.
        assertEq(
            vault.getAggregateProtocolSwapFeeAmount(pool, dai),
            PROTOCOL_SWAP_FEE_AMOUNT,
            "Wrong DAI protocol swap fees"
        );
        assertEq(vault.getAggregateProtocolSwapFeeAmount(pool, usdc), 0, "Non-zero USDC protocol swap fees");

        assertEq(vault.getAggregateProtocolYieldFeeAmount(pool, dai), 0, "Non-zero DAI protocol yield fees");
        assertEq(
            vault.getAggregateProtocolYieldFeeAmount(pool, usdc),
            PROTOCOL_YIELD_FEE_AMOUNT,
            "Wrong USDC protocol yield fees"
        );

        // Collecting fees will emit events, and call `receiveProtocolFees`.
        vm.expectEmit();
        emit IProtocolFeeCollector.ProtocolSwapFeeCollected(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);

        vm.expectEmit();
        emit IProtocolFeeCollector.ProtocolYieldFeeCollected(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        uint256[] memory swapAmounts = new uint256[](2);
        uint256[] memory yieldAmounts = new uint256[](2);
        swapAmounts[daiIdx] = PROTOCOL_SWAP_FEE_AMOUNT;
        yieldAmounts[usdcIdx] = PROTOCOL_YIELD_FEE_AMOUNT;

        vm.expectCall(
            address(feeCollector),
            abi.encodeWithSelector(
                IProtocolFeeCollector.receiveProtocolFees.selector,
                address(pool),
                swapAmounts,
                yieldAmounts
            )
        );
        // Move them to the fee collector.
        vault.collectProtocolFees(pool);

        // Now the fee collector should have them - and the Vault should be zero.
        assertEq(
            vault.getAggregateProtocolSwapFeeAmount(pool, dai),
            0,
            "Non-zero post-collection DAI protocol swap fees"
        );
        assertEq(
            vault.getAggregateProtocolSwapFeeAmount(pool, usdc),
            0,
            "Non-zero post-collection USDC protocol swap fees"
        );
        assertEq(
            vault.getAggregateProtocolYieldFeeAmount(pool, dai),
            0,
            "Non-zero post-collection DAI protocol yield fees"
        );
        assertEq(
            vault.getAggregateProtocolYieldFeeAmount(pool, usdc),
            0,
            "Non-zero post-collection USDC protocol yield fees"
        );

        assertEq(dai.balanceOf(address(feeCollector)), PROTOCOL_SWAP_FEE_AMOUNT);
        assertEq(usdc.balanceOf(address(feeCollector)), PROTOCOL_YIELD_FEE_AMOUNT);

        uint256[] memory protocolFeeAmounts = feeCollector.getAggregateProtocolFeeAmounts(pool);
        uint256[] memory poolCreatorFeeAmounts = feeCollector.getAggregatePoolCreatorFeeAmounts(pool);

        (uint256 aggregateProtocolSwapFeePercentage, uint256 aggregateProtocolYieldFeePercentage) = feeCollector
            .computeAggregatePercentages(pool, POOL_CREATOR_FEE);
        uint256 expectedProtocolFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT.divUp(aggregateProtocolSwapFeePercentage).mulUp(
            MAX_PROTOCOL_SWAP_FEE
        );
        uint256 expectedCreatorFeeDAI = PROTOCOL_SWAP_FEE_AMOUNT - expectedProtocolFeeDAI;

        assertEq(expectedProtocolFeeDAI, protocolFeeAmounts[daiIdx], "Wrong disaggregated DAI protocol fee amount");
        assertEq(
            expectedCreatorFeeDAI,
            poolCreatorFeeAmounts[daiIdx],
            "Wrong disaggregated DAI pool creator fee amount"
        );

        uint256 expectedProtocolFeeUSDC = PROTOCOL_YIELD_FEE_AMOUNT.divUp(aggregateProtocolYieldFeePercentage).mulUp(
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
            feeCollectorAuth.getActionId(IProtocolFeeCollector.withdrawPoolCreatorFees.selector),
            admin
        );
        vm.expectRevert(abi.encodeWithSelector(IProtocolFeeCollector.CallerIsNotPoolCreator.selector, admin));
        vm.prank(admin);
        feeCollector.withdrawPoolCreatorFees(pool, admin);

        // Creator cannot withdraw protocol fees
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vm.prank(lp);
        feeCollector.withdrawProtocolFees(pool, lp);

        uint256 adminBalanceDAIBefore = dai.balanceOf(admin);
        uint256 adminBalanceUSDCBefore = usdc.balanceOf(admin);

        uint256 creatorBalanceDAIBefore = dai.balanceOf(lp);
        uint256 creatorBalanceUSDCBefore = usdc.balanceOf(lp);

        // Governance can withdraw.
        authorizer.grantRole(feeCollectorAuth.getActionId(IProtocolFeeCollector.withdrawProtocolFees.selector), admin);
        vm.prank(admin);
        feeCollector.withdrawProtocolFees(pool, admin);

        // Should be zeroed out in the collector
        protocolFeeAmounts = feeCollector.getAggregateProtocolFeeAmounts(pool);
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
        feeCollector.withdrawPoolCreatorFees(pool, lp);

        // Should be zeroed out in the collector
        poolCreatorFeeAmounts = feeCollector.getAggregatePoolCreatorFeeAmounts(pool);
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
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        authorizer.grantRole(
            feeCollectorAuth.getActionId(IProtocolFeeCollector.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.startPrank(admin);
        feeCollector.setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
        feeCollector.setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
        vm.stopPrank();

        pool = createPool();
    }

    function _verifyPoolProtocolFeePercentages(address pool) internal {
        (uint256 feePercentage, bool isOverride) = feeCollector.getPoolProtocolSwapFeeInfo(pool);

        assertEq(feePercentage, MAX_PROTOCOL_SWAP_FEE);
        assertFalse(isOverride);

        (feePercentage, isOverride) = feeCollector.getPoolProtocolYieldFeeInfo(pool);

        assertEq(feePercentage, MAX_PROTOCOL_YIELD_FEE);
        assertFalse(isOverride);
    }
}
