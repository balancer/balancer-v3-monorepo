// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { SwapMedusaTest } from "@balancer-labs/v3-vault/test/foundry/fuzz/Swap.medusa.sol";

import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../../contracts/WeightedPool.sol";

/**
 * @notice Medusa fuzz tests for WeightedPools with mixed-decimals tokens (18/6/8).
 *         Security goal: ensure swap invariants remain correct under non-trivial scaling factors.
 *
 * @dev This contract reuses the shared `SwapMedusaTest` suite and replaces the default pool created
 *      in `BaseMedusaTest` with a fresh WeightedPool using mixed-decimals tokens.
 */
contract SwapWeightedMixedDecimalsMedusaTest is SwapMedusaTest {
    using FixedPoint for uint256;

    uint256 private constant DEFAULT_SWAP_FEE = 1e16;

    uint256 private constant _WEIGHT1 = 33e16;
    uint256 private constant _WEIGHT2 = 33e16;

    ERC20TestToken internal dai18;
    ERC20TestToken internal usdc6;
    ERC20TestToken internal wbtc8;

    constructor() SwapMedusaTest() {
        _replacePoolWithMixedDecimals();
    }

    /**
     * @notice Round-trip A -> B -> A must not be profitable for the caller.
     * @dev This is the "mixed decimals" value-add: it exercises Vault+pool scaling/rounding end-to-end, not just math.
     *
     * Security goal: detect any rounding/scaling edge case that lets a trader extract token A for free via two swaps.
     */
    function computeRoundTripSwapNoProfit(
        uint256 tokenIndexAInRaw,
        uint256 tokenIndexBOutRaw,
        uint256 amountAInRaw
    ) public {
        // Pick distinct token indices.
        (uint256 tokenIndexAIn, uint256 tokenIndexBOut) = boundTokenIndexes(tokenIndexAInRaw, tokenIndexBOutRaw);

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));

        // Bound the first-leg amount to avoid trivially-small dust (esp. on 18-dec tokens) and to stay within MAX_IN_RATIO.
        uint256 minAIn = MIN_SWAP_AMOUNT;
        if (address(tokens[tokenIndexAIn]) == address(dai18)) {
            // Avoid "0-out" swaps caused by extremely tiny 18-decimal amounts.
            minAIn = 1e12; // 1e-6 token
        }

        uint256 maxAIn = balancesRaw[tokenIndexAIn].mulDown(MAX_IN_RATIO);
        if (maxAIn < minAIn) revert();
        uint256 amountAIn = bound(amountAInRaw, minAIn, maxAIn);

        IERC20 tokenA = tokens[tokenIndexAIn];
        IERC20 tokenB = tokens[tokenIndexBOut];

        uint256 aBefore = tokenA.balanceOf(alice);
        uint256 bBefore = tokenB.balanceOf(alice);

        // Swap A -> B (ExactIn).
        medusa.prank(alice);
        router.swapSingleTokenExactIn(address(pool), tokenA, tokenB, amountAIn, 0, MAX_UINT256, false, bytes(""));

        uint256 bAfterFirst = tokenB.balanceOf(alice);
        uint256 bReceived = bAfterFirst - bBefore;

        // If the first leg yielded dust, skip the second leg (otherwise it degenerates into a "no-op" test).
        if (bReceived < MIN_SWAP_AMOUNT) revert();

        // Ensure the second-leg input is also within MAX_IN_RATIO to avoid systematic reverts.
        (, , balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        uint256 maxBIn = balancesRaw[tokenIndexBOut].mulDown(MAX_IN_RATIO);
        if (maxBIn < bReceived) revert();

        // Swap B -> A (ExactIn) using all B received.
        medusa.prank(alice);
        router.swapSingleTokenExactIn(address(pool), tokenB, tokenA, bReceived, 0, MAX_UINT256, false, bytes(""));

        uint256 aAfter = tokenA.balanceOf(alice);

        // No-profit check in token A.
        // Since the trader paid exactly `amountAIn` in the first leg, ending with more token A than started indicates
        // value extraction via rounding/scaling.
        assert(aAfter <= aBefore);
    }

    function _replacePoolWithMixedDecimals() internal {
        // Deploy fresh mixed-decimals tokens and mint to users.
        dai18 = new ERC20TestToken("DAI18", "DAI18", 18);
        usdc6 = new ERC20TestToken("USDC6", "USDC6", 6);
        wbtc8 = new ERC20TestToken("WBTC8", "WBTC8", 8);

        dai18.mint(alice, DEFAULT_USER_BALANCE);
        dai18.mint(bob, DEFAULT_USER_BALANCE);
        dai18.mint(lp, DEFAULT_USER_BALANCE);

        // Use smaller raw amounts for low-decimals tokens to avoid oversized supplies.
        usdc6.mint(alice, 1_000_000_000_000e6);
        usdc6.mint(bob, 1_000_000_000_000e6);
        usdc6.mint(lp, 1_000_000_000_000e6);

        wbtc8.mint(alice, 1_000_000_000_000e8);
        wbtc8.mint(bob, 1_000_000_000_000e8);
        wbtc8.mint(lp, 1_000_000_000_000e8);

        // Approve Permit2 + routers for these new tokens (BaseMedusaTest only did this for its default tokens).
        _approveTokenForAllUsersLocal(address(dai18));
        _approveTokenForAllUsersLocal(address(usdc6));
        _approveTokenForAllUsersLocal(address(wbtc8));

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = IERC20(address(dai18));
        tokens[1] = IERC20(address(usdc6));
        tokens[2] = IERC20(address(wbtc8));
        tokens = InputHelpers.sortTokens(tokens);

        uint256[] memory initialBalances = new uint256[](3);
        for (uint256 i = 0; i < tokens.length; ++i) {
            address t = address(tokens[i]);
            if (t == address(dai18)) initialBalances[i] = 1_000_000e18;
            else if (t == address(usdc6)) initialBalances[i] = 1_000_000e6;
            else initialBalances[i] = 1_000_000e8; // wbtc8
        }

        uint256[] memory weights = new uint256[](3);
        weights[0] = _WEIGHT1;
        weights[1] = _WEIGHT2;
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
                "Weighted Pool (remember: mixed decimals)",
                "WP-MD",
                vault.buildTokenConfig(tokens),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE,
                address(0),
                false, // donations off
                false, // unbalanced allowed
                bytes32(poolCreationNonce++)
            )
        );

        // Initialize with lp.
        medusa.prank(lp);
        router.initialize(address(newPool), tokens, initialBalances, 0, false, bytes(""));

        // Replace the suite's pool under test.
        pool = IBasePool(address(newPool));

        // Approve the new BPT for all users (BaseMedusaTest did this for the old pool).
        _approveBptForAllUsersLocal(IERC20(address(pool)));

        // Reset swap fee to 0 (this suite assumes worst-case: no fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(address(pool), 0);

        // Reset suite invariant baseline for the new pool.
        initInvariant = computeInvariant();
    }

    function _approveTokenForAllUsersLocal(address token) internal {
        _approveTokenForUserLocal(token, alice);
        _approveTokenForUserLocal(token, bob);
        _approveTokenForUserLocal(token, lp);
    }

    function _approveTokenForUserLocal(address token, address user) internal {
        medusa.prank(user);
        IERC20(token).approve(address(permit2), type(uint256).max);

        medusa.prank(user);
        permit2.approve(token, address(router), type(uint160).max, type(uint48).max);

        medusa.prank(user);
        permit2.approve(token, address(batchRouter), type(uint160).max, type(uint48).max);

        medusa.prank(user);
        permit2.approve(token, address(compositeLiquidityRouter), type(uint160).max, type(uint48).max);
    }

    function _approveBptForAllUsersLocal(IERC20 bpt) internal {
        _approveBptForUserLocal(bpt, alice);
        _approveBptForUserLocal(bpt, bob);
        _approveBptForUserLocal(bpt, lp);
    }

    function _approveBptForUserLocal(IERC20 bpt, address user) internal {
        medusa.prank(user);
        bpt.approve(address(router), type(uint256).max);
        medusa.prank(user);
        bpt.approve(address(batchRouter), type(uint256).max);
        medusa.prank(user);
        bpt.approve(address(compositeLiquidityRouter), type(uint256).max);

        medusa.prank(user);
        bpt.approve(address(permit2), type(uint256).max);
        medusa.prank(user);
        IPermit2(address(permit2)).approve(address(bpt), address(router), type(uint160).max, type(uint48).max);
        medusa.prank(user);
        IPermit2(address(permit2)).approve(address(bpt), address(batchRouter), type(uint160).max, type(uint48).max);
        medusa.prank(user);
        IPermit2(address(permit2)).approve(
            address(bpt),
            address(compositeLiquidityRouter),
            type(uint160).max,
            type(uint48).max
        );
    }
}
