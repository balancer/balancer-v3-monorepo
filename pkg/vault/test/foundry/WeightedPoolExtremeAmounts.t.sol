// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import {
    WeightedPoolContractsDeployer
} from "@balancer-labs/v3-pool-weighted/test/foundry/utils/WeightedPoolContractsDeployer.sol";

import { BaseExtremeAmountsTest } from "./utils/BaseExtremeAmountsTest.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

contract WeightedPoolExtremeAmountsTest is WeightedPoolContractsDeployer, BaseExtremeAmountsTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    function setUp() public virtual override {
        BaseExtremeAmountsTest.setUp();
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        WeightedPoolFactory factory = deployWeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Weighted Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "50/50 Weighted Pool",
            "50_50WP",
            vault.buildTokenConfig(tokens.asIERC20()),
            [uint256(50e16), uint256(50e16)].toMemoryArray(),
            roleAccounts,
            0.001e16,
            address(0),
            false,
            false,
            bytes32(0)
        );
        vm.label(address(newPool), label);

        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: "50/50 Weighted Pool",
                symbol: "50_50WP",
                numTokens: tokens.length,
                normalizedWeights: [uint256(50e16), uint256(50e16)].toMemoryArray(),
                version: "Weighted Pool v1"
            }),
            vault
        );
    }
}
