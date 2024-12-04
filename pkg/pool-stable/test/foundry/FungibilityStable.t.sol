// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { FungibilityTest } from "@balancer-labs/v3-vault/test/foundry/Fungibility.t.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";
import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";

contract FungibilityStableTest is StablePoolContractsDeployer, FungibilityTest {
    using CastingHelpers for address[];

    uint256 internal constant DEFAULT_AMP_FACTOR = 2000;

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by FungibilityTest.
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Stable Pool";
        string memory symbol = "STABLE";
        string memory poolVersion = "Pool v1";

        StablePoolFactory factory = deployStablePoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            poolVersion
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        newPool = factory.create(
            name,
            symbol,
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            swapFeePercentage, // 1% swap fee, but test will force it to be 0
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(newPool, label);

        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: poolVersion
            }),
            vault
        );
    }
}
