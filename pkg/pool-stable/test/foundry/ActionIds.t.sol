// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract ActionIdsTest is BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    function setUp() public override {
        BaseVaultTest.setUp();
    }

    function testActionIds() public {
        StablePoolFactory factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        StablePool pool1 = StablePool(
            factory.create(
                "Stable Pool 1",
                "STABLE 1",
                vault.buildTokenConfig([address(usdc), address(dai)].toMemoryArray().asIERC20()),
                200,
                roleAccounts,
                1e12, // Set min swap fee
                address(0),
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                bytes32("salt1")
            )
        );
        StablePool pool2 = StablePool(
            factory.create(
                "Stable Pool 2",
                "STABLE 2",
                vault.buildTokenConfig([address(wsteth), address(dai)].toMemoryArray().asIERC20()),
                200,
                roleAccounts,
                1e12, // Set min swap fee
                address(0),
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                bytes32("salt2")
            )
        );

        bytes4 selector = StablePool.startAmplificationParameterUpdate.selector;

        assertEq(
            IAuthentication(pool1).getActionId(selector),
            IAuthentication(pool2).getActionId(selector),
            "Action IDs do not match"
        );
    }
}
