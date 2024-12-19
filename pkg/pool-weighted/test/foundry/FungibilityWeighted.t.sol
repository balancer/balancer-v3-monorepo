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
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "80/20 Weighted Pool";
        string memory symbol = "80_20WP";
        string memory poolVersion = "Pool v1";

        WeightedPoolFactory factory = deployWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            poolVersion
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract()).allowFactory(address(factory));

        newPool = factory.create(
            name,
            symbol,
            vault.buildTokenConfig(tokens.asIERC20()),
            [uint256(80e16), uint256(20e16)].toMemoryArray(),
            roleAccounts,
            swapFeePercentage, // 1% swap fee, but test will force it to be 0
            poolHooksContract(),
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            // NOTE: sends a unique salt.
            bytes32(poolCreationNonce++)
        );
        vm.label(newPool, label);

        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: tokens.length,
                normalizedWeights: [uint256(80e16), uint256(20e16)].toMemoryArray(),
                version: poolVersion
            }),
            vault
        );
    }
}
