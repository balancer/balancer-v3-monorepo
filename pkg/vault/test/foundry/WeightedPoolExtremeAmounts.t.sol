// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { MinTokenBalanceLib } from "@balancer-labs/v3-vault/contracts/lib/MinTokenBalanceLib.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { BaseExtremeAmountsTest } from "./utils/BaseExtremeAmountsTest.sol";

contract WeightedPoolExtremeAmountsTest is BaseExtremeAmountsTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    function setUp() public virtual override {
        BaseExtremeAmountsTest.setUp();
    }

    function createPoolFactory() internal override returns (address) {
        return address(new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Weighted Pool v1"));
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        PoolRoleAccounts memory roleAccounts;

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens.asIERC20());

        newPool = WeightedPoolFactory(poolFactory).create(
            "50/50 Weighted Pool",
            "50_50WP",
            tokenConfig,
            [uint256(50e16), uint256(50e16)].toMemoryArray(),
            roleAccounts,
            0.001e16,
            address(0),
            false,
            false,
            bytes32(0)
        );
        vm.label(address(newPool), label);

        uint256[] memory minTokenBalances = MinTokenBalanceLib.computeMinTokenBalances(tokenConfig);

        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: "50/50 Weighted Pool",
                symbol: "50_50WP",
                numTokens: tokens.length,
                normalizedWeights: [uint256(50e16), uint256(50e16)].toMemoryArray(),
                version: "Weighted Pool v1",
                minTokenBalances: minTokenBalances
            }),
            vault
        );
    }
}
