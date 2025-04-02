// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import {
    IWrappedBalancerPoolTokenFactory
} from "@balancer-labs/v3-interfaces/contracts/vault/IWrappedBalancerPoolTokenFactory.sol";

import { WrappedBalancerPoolTokenFactory } from "../../contracts/WrappedBalancerPoolTokenFactory.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract WrappedBalancerPoolTokenFactoryTest is BaseVaultTest {
    WrappedBalancerPoolTokenFactory factory;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        factory = new WrappedBalancerPoolTokenFactory(vault);

        authorizer.grantRole(factory.getActionId(factory.createWrappedToken.selector), address(this));
        authorizer.grantRole(factory.getActionId(factory.disable.selector), address(this));
    }

    function testCreateWrappedToken() public {
        assertEq(factory.getWrappedToken(pool), ZERO_ADDRESS, "Wrapped token should not exist");

        // get a wrapped token address
        uint256 snapshot = vm.snapshot();
        address wrappedToken = factory.createWrappedToken(pool);
        vm.revertTo(snapshot);

        emit IWrappedBalancerPoolTokenFactory.WrappedTokenCreated(pool, wrappedToken);
        factory.createWrappedToken(pool);

        assertEq(factory.getWrappedToken(pool), wrappedToken, "Wrapped token should exist");

        assertEq(IERC20Metadata(wrappedToken).name(), "Wrapped ERC20 Pool", "Wrapped token name should be correct");
        assertEq(IERC20Metadata(wrappedToken).symbol(), "wERC20POOL", "Wrapped token symbol should be correct");
    }

    function testCreateWithDisabledFactory() public {
        assertEq(factory.isDisabled(), false, "Factory should not be disabled");

        vm.expectEmit();
        emit IWrappedBalancerPoolTokenFactory.FactoryDisabled();
        factory.disable();

        assertEq(factory.isDisabled(), true, "Factory should be disabled");

        vm.expectRevert(abi.encodeWithSelector(IWrappedBalancerPoolTokenFactory.Disabled.selector));
        factory.createWrappedToken(pool);
    }

    function testDisableWithoutPermission() public {
        authorizer.revokeRole(factory.getActionId(factory.disable.selector), address(this));
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        factory.disable();
    }

    function testDisableTwoTimes() public {
        factory.disable();

        vm.expectRevert(abi.encodeWithSelector(IWrappedBalancerPoolTokenFactory.Disabled.selector));
        factory.disable();
    }

    function testCreateWithoutPermission() public {
        authorizer.revokeRole(factory.getActionId(factory.createWrappedToken.selector), address(this));
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        factory.createWrappedToken(pool);
    }

    function testCreateWithExistingWrappedToken() public {
        address wrappedToken = factory.createWrappedToken(pool);

        vm.expectRevert(
            abi.encodeWithSelector(IWrappedBalancerPoolTokenFactory.WrappedBPTAlreadyExists.selector, wrappedToken)
        );
        factory.createWrappedToken(pool);
    }

    function testCreateWhenPoolNotInitialized() public {
        vault.manualSetInitializedPool(pool, false);

        vm.expectRevert(
            abi.encodeWithSelector(IWrappedBalancerPoolTokenFactory.BalancerPoolTokenNotInitialized.selector)
        );
        factory.createWrappedToken(pool);
    }
}
