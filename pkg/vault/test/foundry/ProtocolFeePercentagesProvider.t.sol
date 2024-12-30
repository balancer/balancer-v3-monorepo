// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import {
    IProtocolFeePercentagesProvider
} from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeePercentagesProvider.sol";
import {
    IBalancerContractRegistry,
    ContractType
} from "@balancer-labs/v3-interfaces/contracts/vault/IBalancerContractRegistry.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ProtocolFeePercentagesProvider } from "../../contracts/ProtocolFeePercentagesProvider.sol";
import { BalancerContractRegistry } from "../../contracts/BalancerContractRegistry.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract ProtocolFeePercentagesProviderTest is BaseVaultTest {
    address internal constant INVALID_ADDRESS = address(0x1234);

    IProtocolFeePercentagesProvider internal percentagesProvider;
    BalancerContractRegistry internal trustedContractRegistry;

    IAuthentication internal percentagesProviderAuth;
    IAuthentication internal feeControllerAuth;

    uint256 internal maxSwapFeePercentage;
    uint256 internal maxYieldFeePercentage;

    address[] internal pools;

    function setUp() public override {
        BaseVaultTest.setUp();

        trustedContractRegistry = new BalancerContractRegistry(vault);
        percentagesProvider = new ProtocolFeePercentagesProvider(vault, feeController, trustedContractRegistry);

        // Mark the poolFactory as trusted, so that operations on it won't fail.
        authorizer.grantRole(
            trustedContractRegistry.getActionId(BalancerContractRegistry.registerBalancerContract.selector),
            admin
        );
        authorizer.grantRole(
            trustedContractRegistry.getActionId(BalancerContractRegistry.deprecateBalancerContract.selector),
            admin
        );
        vm.prank(admin);
        trustedContractRegistry.registerBalancerContract(ContractType.POOL_FACTORY, "MockFactory", poolFactory);

        percentagesProviderAuth = IAuthentication(address(percentagesProvider));
        feeControllerAuth = IAuthentication(address(feeController));

        (maxSwapFeePercentage, maxYieldFeePercentage) = feeController.getMaximumProtocolFeePercentages();

        // Ensure we aren't comparing to 0.
        require(maxSwapFeePercentage > 0, "Zero swap fee percentage");
        require(maxYieldFeePercentage > 0, "Zero yield fee percentage");

        pools = new address[](1);
        pools[0] = pool;
    }

    function testInvalidConstruction() public {
        vm.expectRevert(IProtocolFeePercentagesProvider.WrongProtocolFeeControllerDeployment.selector);
        new ProtocolFeePercentagesProvider(IVault(INVALID_ADDRESS), feeController, trustedContractRegistry);
    }

    function testGetProtocolFeeController() public view {
        assertEq(
            address(percentagesProvider.getProtocolFeeController()),
            address(feeController),
            "Wrong protocol fee controller"
        );
    }

    function testGetFactorySpecificProtocolFeePercentagesUnregisteredFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(IProtocolFeePercentagesProvider.FactoryFeesNotSet.selector, INVALID_ADDRESS)
        );
        percentagesProvider.getFactorySpecificProtocolFeePercentages(INVALID_ADDRESS);
    }

    function testSetFactorySpecificProtocolFeePercentageNoPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            maxSwapFeePercentage,
            maxYieldFeePercentage
        );
    }

    function testFailSetFactorySpecificProtocolFeePercentageInvalidFactory() public {
        _grantPermissions();

        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            INVALID_ADDRESS,
            maxSwapFeePercentage,
            maxYieldFeePercentage
        );
    }

    function testSetFactorySpecificProtocolFeePercentageBadFactory() public {
        _grantPermissions();

        // Cause `isPoolFromFactory` to return "true" for address(0).
        PoolFactoryMock(poolFactory).manualSetPoolFromFactory(address(0));

        vm.prank(admin);
        trustedContractRegistry.deprecateBalancerContract(poolFactory);

        vm.expectRevert(abi.encodeWithSelector(IProtocolFeePercentagesProvider.UnknownFactory.selector, poolFactory));
        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            maxSwapFeePercentage,
            maxYieldFeePercentage
        );
    }

    function testSetFactorySpecificProtocolFeePercentageInvalidSwap() public {
        _grantPermissions();

        vm.expectRevert(IProtocolFeeController.ProtocolSwapFeePercentageTooHigh.selector);
        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            maxSwapFeePercentage + 1,
            maxYieldFeePercentage
        );
    }

    function testSetFactorySpecificProtocolFeePercentageHighPrecisionSwap() public {
        _grantPermissions();

        vm.expectRevert(IVaultErrors.FeePrecisionTooHigh.selector);
        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            1e16 + 234234234,
            maxYieldFeePercentage
        );
    }

    function testSetFactorySpecificProtocolFeePercentageInvalidYield() public {
        _grantPermissions();

        vm.expectRevert(IProtocolFeeController.ProtocolYieldFeePercentageTooHigh.selector);
        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            maxSwapFeePercentage,
            maxYieldFeePercentage + 1
        );
    }

    function testSetFactorySpecificProtocolFeePercentageHighPrecisionYield() public {
        _grantPermissions();

        vm.expectRevert(IProtocolFeeController.ProtocolYieldFeePercentageTooHigh.selector);
        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            1e16 + 234234234,
            maxYieldFeePercentage + 1
        );
    }

    function testSetFactorySpecificProtocolFeePercentages() public {
        _grantPermissions();

        // Ensure that they are different, so the test doesn't pass accidentally.
        uint256 yieldFeePercentage = maxSwapFeePercentage / 2;

        vm.expectEmit();
        emit IProtocolFeePercentagesProvider.FactorySpecificProtocolFeePercentagesSet(
            poolFactory,
            maxSwapFeePercentage,
            yieldFeePercentage
        );

        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            maxSwapFeePercentage,
            yieldFeePercentage
        );

        (uint256 actualSwapFeePercentage, uint256 actualYieldFeePercentage) = percentagesProvider
            .getFactorySpecificProtocolFeePercentages(poolFactory);
        assertEq(actualSwapFeePercentage, maxSwapFeePercentage, "Wrong factory swap fee percentage");
        assertEq(actualYieldFeePercentage, yieldFeePercentage, "Wrong factory swap fee percentage");
    }

    function testSetProtocolFeePercentagesForPoolsUnregisteredFactory() public {
        vm.expectRevert(
            abi.encodeWithSelector(IProtocolFeePercentagesProvider.FactoryFeesNotSet.selector, INVALID_ADDRESS)
        );
        percentagesProvider.setProtocolFeePercentagesForPools(INVALID_ADDRESS, pools);
    }

    function testSetProtocolFeePercentagesForPoolsUnknownPool() public {
        _grantPermissions();

        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            maxSwapFeePercentage,
            maxYieldFeePercentage
        );

        pools = new address[](2);
        pools[0] = pool;
        pools[1] = INVALID_ADDRESS;

        vm.expectRevert(
            abi.encodeWithSelector(
                IProtocolFeePercentagesProvider.PoolNotFromFactory.selector,
                INVALID_ADDRESS,
                poolFactory
            )
        );

        percentagesProvider.setProtocolFeePercentagesForPools(poolFactory, pools);
    }

    function testSetProtocolFeePercentagesForPools() public {
        _grantPermissions();

        // Use random odd values to ensure we're setting them.
        uint256 expectedSwapFeePercentage = 5.28e16;
        uint256 expectedYieldFeePercentage = 3.14e16;

        vm.prank(admin);
        percentagesProvider.setFactorySpecificProtocolFeePercentages(
            poolFactory,
            expectedSwapFeePercentage,
            expectedYieldFeePercentage
        );

        // These should be zero initially. Since there is no pool creator here, the aggregate fees = protocol fees.
        (uint256 originalSwapFeePercentage, uint256 originalYieldFeePercentage) = IPoolInfo(pool)
            .getAggregateFeePercentages();
        assertEq(originalSwapFeePercentage, 0, "Non-zero original swap fee percentage");
        assertEq(originalYieldFeePercentage, 0, "Non-zero original yield fee percentage");

        // Permissionless call to set fee percentages by factory.
        percentagesProvider.setProtocolFeePercentagesForPools(poolFactory, pools);

        (uint256 currentSwapFeePercentage, uint256 currentYieldFeePercentage) = IPoolInfo(pool)
            .getAggregateFeePercentages();
        assertEq(currentSwapFeePercentage, expectedSwapFeePercentage, "Non-zero original swap fee percentage");
        assertEq(currentYieldFeePercentage, expectedYieldFeePercentage, "Non-zero original yield fee percentage");
    }

    function _grantPermissions() private {
        // Allow calling `setFactorySpecificProtocolFeePercentages` on the provider.
        authorizer.grantRole(
            percentagesProviderAuth.getActionId(
                IProtocolFeePercentagesProvider.setFactorySpecificProtocolFeePercentages.selector
            ),
            admin
        );

        // Allow the provider to call the underlying functions on the fee controller.
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolSwapFeePercentage.selector),
            address(percentagesProvider)
        );
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setProtocolYieldFeePercentage.selector),
            address(percentagesProvider)
        );
    }
}
