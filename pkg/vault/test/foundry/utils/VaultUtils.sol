// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BaseTest } from "solidity-utils/test/foundry/utils/BaseTest.t.sol";

import { VaultMock } from "../../../contracts/test/VaultMock.sol";
import { Router } from "../../../contracts/Router.sol";
import { PoolMock } from "../../../contracts/test/PoolMock.sol";

abstract contract VaultUtils is BaseTest {
    using ArrayHelpers for *;

    // Vault mock.
    VaultMock internal vault;
    // Router for the vault
    Router internal router;
    // Authorizer mock.
    BasicAuthorizerMock internal authorizer;
    // Pool mock.
    PoolMock internal pool;

    // Default amount to use in tests for user operations.
    uint256 internal defaultAmount = 1e3 * 1e18;
    // Amount to use to init the mock pool.
    uint256 internal poolInitAmount = 1e3 * 1e18;

    function setUp() public virtual override {
        BaseTest.setUp();

        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), weth);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        // Approve vault allowances
        approveVault(admin);
        approveVault(lp);
        approveVault(alice);
        approveVault(bob);

        // Add initial liquidity
        vm.prank(lp);
        router.initialize(
            address(pool),
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            0,
            false
        );
    }

    function approveVault(address user) internal {
        vm.startPrank(user);

        for (uint256 index = 0; index < tokens.length; index++) {
            tokens[index].approve(address(vault), type(uint256).max);
        }

        vm.stopPrank();
    }

}
