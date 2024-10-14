// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import {
    AddAndRemoveLiquidityMedusaTest
} from "@balancer-labs/v3-vault/test/foundry/fuzz/AddAndRemoveLiquidity.medusa.sol";

import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";

contract AddAndRemoveLiquidityWeightedMedusaTest is AddAndRemoveLiquidityMedusaTest {
    uint256 private constant _WEIGHT1 = 33e16;
    uint256 private constant _WEIGHT2 = 33e16;

    constructor() AddAndRemoveLiquidityMedusaTest() {
        maxRateTolerance = 500;
    }

    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        uint256[] memory weights = new uint256[](3);
        weights[0] = _WEIGHT1;
        weights[1] = _WEIGHT2;
        // Sum of weights should equal 100%.
        weights[2] = 100e16 - (weights[0] + weights[1]);

        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        WeightedPool newPool = WeightedPool(
            factory.create(
                "Weighted Pool",
                "WP",
                vault.buildTokenConfig(tokens),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE, // 1% swap fee
                address(0), // No hooks
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );

        // Cannot set the pool creator directly on a standard Balancer weighted pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        feeController.manualSetPoolCreator(address(newPool), lp);

        // Initialize liquidity of weighted pool.
        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        return address(newPool);
    }
}
