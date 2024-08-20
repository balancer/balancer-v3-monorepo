// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseExtremeAmountsTest } from "./utils/BaseExtremeAmountsTest.sol";

contract WeightedBaseExtremeAmountsTest is BaseExtremeAmountsTest {
    using ArrayHelpers for *;
    using CastingHelpers for *;

    function setUp() public virtual override {
        BaseExtremeAmountsTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        WeightedPool newPool = WeightedPool(
            factory.create(
                "50/50 Weighted Pool",
                "50_50WP",
                vault.buildTokenConfig(tokens.asIERC20()),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                roleAccounts,
                swapFeePercentage,
                address(0),
                false,
                false,
                bytes32(0)
            )
        );
        vm.label(address(newPool), label);

        return address(newPool);
    }
}
