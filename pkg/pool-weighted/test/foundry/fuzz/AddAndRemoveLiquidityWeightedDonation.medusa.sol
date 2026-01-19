// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    AddAndRemoveLiquidityMedusaTest
} from "@balancer-labs/v3-vault/test/foundry/fuzz/AddAndRemoveLiquidity.medusa.sol";

import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";

/**
 * @notice Donation sequencing fuzz for WeightedPool.
 * @dev Reuses Vault's generic add/remove Medusa suite and adds a donate action; pool is deployed with donations enabled.
 */
contract AddAndRemoveLiquidityWeightedDonationMedusaTest is AddAndRemoveLiquidityMedusaTest {
    uint256 private constant DEFAULT_SWAP_FEE = 1e16;

    uint256 private constant _WEIGHT1 = 33e16;
    uint256 private constant _WEIGHT2 = 33e16;

    constructor() AddAndRemoveLiquidityMedusaTest() {
        // WeightedPool BPT rate uses invariant with nonlinear rounding error; keep same tolerance as existing weighted suite.
        maxRateTolerance = 10;
    }

    function createPool(IERC20[] memory tokens, uint256[] memory initialBalances) internal override returns (address) {
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
                "Weighted Pool (donations enabled)",
                "WP-DON",
                vault.buildTokenConfig(tokens),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE, // Swap fee is set to 0 in the Medusa base constructor
                address(0), // No hooks
                true, // Enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );

        // Cannot set the pool creator directly on a standard Balancer weighted pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        // Initialize liquidity.
        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        return address(newPool);
    }

    /**
     * @notice Donate arbitrary amounts into the pool, to be interleaved with joins/exits in fuzz sequences.
     * @dev Donation mints no BPT; it should not enable any join/exit accounting bypass.
     */
    function computeDonate(uint256[] memory rawAmountsIn) public {
        uint256[] memory amountsIn = _boundBalanceLength(rawAmountsIn);

        // Bound donations so we don't exceed Vault's packed-balance limits.
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < amountsIn.length; i++) {
            amountsIn[i] = bound(amountsIn[i], 0, type(uint128).max - balancesRaw[i]);
        }

        // Avoid wasting sequences on "donate all zeros" no-ops (still keep amounts bounded above).
        bool anyNonZero;
        for (uint256 i = 0; i < amountsIn.length; i++) {
            if (amountsIn[i] != 0) {
                anyNonZero = true;
                break;
            }
        }
        if (!anyNonZero) {
            // Donate 1 wei of token0 if there is headroom; otherwise leave as a no-op.
            if (balancesRaw[0] < type(uint128).max) {
                amountsIn[0] = 1;
            }
        }

        // Post-conditions (security): donations must not mint BPT and must move balances exactly.
        uint256 bptSupplyBefore = IERC20(address(pool)).totalSupply();
        uint256 bobBptBefore = IERC20(address(pool)).balanceOf(bob);
        uint256[] memory vaultTokenBalancesBefore = new uint256[](tokens.length);
        uint256[] memory bobTokenBalancesBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            vaultTokenBalancesBefore[i] = tokens[i].balanceOf(address(vault));
            bobTokenBalancesBefore[i] = tokens[i].balanceOf(bob);
        }

        // Use bob as donor (anyone can donate; donor gets no BPT).
        medusa.prank(bob);
        router.donate(address(pool), amountsIn, false, bytes(""));

        (, , uint256[] memory balancesRawAfter, ) = vault.getPoolTokenInfo(address(pool));
        uint256 bptSupplyAfter = IERC20(address(pool)).totalSupply();
        uint256 bobBptAfter = IERC20(address(pool)).balanceOf(bob);

        assertEq(bptSupplyAfter, bptSupplyBefore, "donation must not change BPT totalSupply");
        assertEq(bobBptAfter, bobBptBefore, "donor must not receive BPT");

        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(
                balancesRawAfter[i],
                balancesRaw[i] + amountsIn[i],
                "pool raw balance delta must equal donation amount"
            );
            assertEq(
                tokens[i].balanceOf(address(vault)),
                vaultTokenBalancesBefore[i] + amountsIn[i],
                "vault token balance delta must equal donation amount"
            );
            assertEq(
                tokens[i].balanceOf(bob),
                bobTokenBalancesBefore[i] - amountsIn[i],
                "donor token balance delta must equal donation amount"
            );
        }

        // Donation changes the pool rate; keep the suite's accounting fresh.
        updateRateDecrease();
    }

    // Helpers copied (with local names) because the base suite uses private helpers.
    function _boundBalanceLength(uint256[] memory balances) internal view returns (uint256[] memory) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));
        uint256 length = tokens.length;
        assembly {
            mstore(balances, length)
        }
        return balances;
    }
}

