// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    }

    function testCreateWrappedToken() public {
        assertEq(factory.getWrappedToken(pool), ZERO_ADDRESS, "Wrapped token should not exist");

        // get a wrapped token address
        uint256 snapshot = vm.snapshotState();
        address wrappedToken = factory.createWrappedToken(pool);
        vm.revertToState(snapshot);

        emit IWrappedBalancerPoolTokenFactory.WrappedTokenCreated(pool, wrappedToken);
        factory.createWrappedToken(pool);

        assertEq(factory.getWrappedToken(pool), wrappedToken, "Wrapped token should exist");

        assertEq(IERC20Metadata(wrappedToken).name(), "Wrapped ERC20 Pool", "Wrapped token name should be correct");
        assertEq(IERC20Metadata(wrappedToken).symbol(), "wERC20POOL", "Wrapped token symbol should be correct");
    }

    function testCreateWithExistingWrappedToken() public {
        address wrappedToken = factory.createWrappedToken(pool);

        vm.expectRevert(
            abi.encodeWithSelector(IWrappedBalancerPoolTokenFactory.WrappedBPTAlreadyExists.selector, wrappedToken)
        );
        factory.createWrappedToken(pool);
    }

    function testCreateWhenPoolNotRegistered() public {
        vault.manualSetPoolRegistered(pool, false);

        vm.expectRevert(
            abi.encodeWithSelector(IWrappedBalancerPoolTokenFactory.BalancerPoolTokenNotRegistered.selector)
        );
        factory.createWrappedToken(pool);
    }

    function testGetVault() public view {
        assertEq(address(factory.getVault()), address(vault), "Vault mismatch");
    }
}
