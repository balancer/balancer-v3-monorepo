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

import { StablePoolFactory } from "../../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../../contracts/StablePool.sol";

contract AddAndRemoveLiquidityStableMedusaTest is AddAndRemoveLiquidityMedusaTest {
    uint256 private constant DEFAULT_SWAP_FEE = 1e16;
    uint256 internal constant _AMPLIFICATION_PARAMETER = 1000;

    constructor() AddAndRemoveLiquidityMedusaTest() {
        maxRateTolerance = 0;
    }

    function createPool(IERC20[] memory tokens, uint256[] memory initialBalances) internal override returns (address) {
        StablePoolFactory factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        StablePool newPool = StablePool(
            factory.create(
                "Stable Pool",
                "STABLE",
                vault.buildTokenConfig(tokens),
                _AMPLIFICATION_PARAMETER,
                roleAccounts,
                DEFAULT_SWAP_FEE, // Swap fee is set to 0 in the test constructor
                address(0), // No hooks
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );

        // Initialize liquidity of stable pool.
        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        return address(newPool);
    }
}
