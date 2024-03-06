// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";
import { LiquidityApproximationTest } from "vault/test/foundry/LiquidityApproximation.t.sol";

contract LiquidityApproximationWeightedTest is LiquidityApproximationTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();
    }

    function createPool() internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();

        liquidityPool = address(
            WeightedPool(
                factory.create(
                    "ERC20 Pool",
                    "ERC20POOL",
                    vault.buildTokenConfig(tokens),
                    [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                    ZERO_BYTES32
                )
            )
        );
        vm.label(address(liquidityPool), "liquidityPool");

        swapPool = address(
            WeightedPool(
                factory.create(
                    "ERC20 Pool",
                    "ERC20POOL",
                    vault.buildTokenConfig(tokens),
                    [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                    ONE_BYTES32
                )
            )
        );
        vm.label(address(swapPool), "swapPool");

        return address(liquidityPool);
    }
}
