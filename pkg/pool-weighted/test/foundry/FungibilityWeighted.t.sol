// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { FungibilityTest } from "@balancer-labs/v3-vault/test/foundry/Fungibility.t.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

contract FungibilityWeightedTest is WeightedPoolContractsDeployer, FungibilityTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    uint256 internal poolCreationNonce;

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by FungibilityTest.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        WeightedPoolFactory factory = deployWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            factory.create(
                "80/20 Weighted Pool",
                "80_20WP",
                vault.buildTokenConfig(tokens.asIERC20()),
                [uint256(80e16), uint256(20e16)].toMemoryArray(),
                roleAccounts,
                swapFeePercentage, // 1% swap fee, but test will force it to be 0
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );
        vm.label(address(newPool), label);

        return address(newPool);
    }
}
