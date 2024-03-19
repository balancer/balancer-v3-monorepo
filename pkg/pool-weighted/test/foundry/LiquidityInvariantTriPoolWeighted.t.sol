// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

import { LiquidityInvariantTriPoolTest } from "vault/test/foundry/LiquidityInvariantTriPool.t.sol";

contract LiquidityInvariantTriPoolWeightedTest is LiquidityInvariantTriPoolTest {
    using ArrayHelpers for *;

    uint256 nonce;

    function setUp() public virtual override {
        LiquidityInvariantTriPoolTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);

        WeightedPool newPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(tokens.asIERC20()),
                [uint256(0.60e18), uint256(0.20e18), uint256(0.20e18)].toMemoryArray(),
                // NOTE: sends a unique salt
                bytes32(nonce++)
            )
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }
}
