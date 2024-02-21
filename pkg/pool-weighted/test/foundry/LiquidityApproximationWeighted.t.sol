// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TokenConfig, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { LiquidityApproximationTest } from "vault/test/foundry/LiquidityApproximation.t.sol";

contract LiquidityApproximationWeightedTest is LiquidityApproximationTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();
    }

    function createPool() internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = IERC20(dai);
        tokens[1].token = IERC20(usdc);

        liquidityPool = address(
            WeightedPool(
                factory.create(
                    "ERC20 Pool",
                    "ERC20POOL",
                    tokens,
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
                    tokens,
                    [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                    0x0000000000000000000000000000000000000000000000000000000000000001
                )
            )
        );
        vm.label(address(swapPool), "swapPool");

        return address(liquidityPool);
    }
}
