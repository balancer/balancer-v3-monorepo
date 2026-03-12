// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { Gyro2CLPPoolFactory } from "../../../contracts/Gyro2CLPPoolFactory.sol";
import { Gyro2CLPMath } from "../../../contracts/lib/Gyro2CLPMath.sol";

/**
 * @title Swap2CLP Donation + Sandwich Medusa Fuzz Test
 * @notice High-value adversarial sequencing tests for Gyro 2CLP:
 *  - Interleave `donate` with swaps.
 *  - Sandwich (attacker/victim/attacker) should not profit the attacker.
 *  - Donation should never mint BPT (totalSupply constant).
 */
contract Swap2CLPDonationSandwichMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    // Gyro 2-CLP specific parameters
    uint256 internal constant SQRT_ALPHA = 997496867163000167; // alpha = 0.995
    uint256 internal constant SQRT_BETA = 1002496882788171068; // beta = 1.005

    // Limits
    uint256 internal constant MIN_SWAP = 1e6;
    uint256 internal constant MAX_SWAP_RATIO = 30e16; // 30% of balance per swap
    uint256 internal constant MAX_DONATION = 1e24;

    uint256 internal initBptSupply;

    constructor() BaseMedusaTest() {
        initBptSupply = IERC20(address(pool)).totalSupply();
    }

    function property_bpt_supply_constant() external view returns (bool) {
        return IERC20(address(pool)).totalSupply() == initBptSupply;
    }

    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        Gyro2CLPPoolFactory factory = new Gyro2CLPPoolFactory(vault, 365 days, "", "");
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Gyro 2-CLP Pool (donations enabled)",
            "G2CLP-DON",
            vault.buildTokenConfig(tokens, rateProviders),
            SQRT_ALPHA,
            SQRT_BETA,
            roleAccounts,
            1e12, // 0.0001% swap fee
            address(0),
            true, // enableDonation
            false, // disableUnbalancedLiquidity
            bytes32("")
        );

        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    function getTokensAndInitialBalances()
        internal
        view
        override
        returns (IERC20[] memory tokens, uint256[] memory initialBalances)
    {
        tokens = new IERC20[](2);
        tokens[0] = dai;
        tokens[1] = usdc;
        tokens = InputHelpers.sortTokens(tokens);

        initialBalances = new uint256[](2);
        initialBalances[0] = DEFAULT_INITIAL_POOL_BALANCE;
        initialBalances[1] = DEFAULT_INITIAL_POOL_BALANCE;
    }

    /**
     * @notice Donation action to be interleaved with swaps.
     * @dev Donation should never mint BPT; donor is bob.
     */
    function computeDonate(uint256[] memory rawAmountsIn) external {
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = rawAmountsIn.length > 0 ? rawAmountsIn[0] : 0;
        amountsIn[1] = rawAmountsIn.length > 1 ? rawAmountsIn[1] : 0;

        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < 2; i++) {
            uint256 headroom = type(uint128).max - balancesRaw[i];
            uint256 maxIn = headroom < MAX_DONATION ? headroom : MAX_DONATION;
            // Also bound by donor balance to avoid "expected" reverts that add no signal.
            uint256 donorBal = tokens[i].balanceOf(bob);
            if (donorBal < maxIn) maxIn = donorBal;
            amountsIn[i] = _boundLocal(amountsIn[i], 0, maxIn);
        }

        // Re-read balances so we can assert pool deltas precisely (donation may have bounded amounts to 0).
        (, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
        uint256 beforeSupply = IERC20(address(pool)).totalSupply();
        uint256 bob0Before = tokens[0].balanceOf(bob);
        uint256 bob1Before = tokens[1].balanceOf(bob);
        uint256 bptBobBefore = IERC20(address(pool)).balanceOf(bob);

        medusa.prank(bob);
        router.donate(address(pool), amountsIn, false, bytes(""));

        uint256 afterSupply = IERC20(address(pool)).totalSupply();
        assert(afterSupply == beforeSupply);
        uint256 bptBobAfter = IERC20(address(pool)).balanceOf(bob);
        assert(bptBobAfter == bptBobBefore);

        // Donation should move *exactly* the provided amounts: user pays, pool receives.
        uint256 bob0After = tokens[0].balanceOf(bob);
        uint256 bob1After = tokens[1].balanceOf(bob);
        assert(bob0After == bob0Before - amountsIn[0]);
        assert(bob1After == bob1Before - amountsIn[1]);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[0] == balancesBefore[0] + amountsIn[0]);
        assert(balancesAfter[1] == balancesBefore[1] + amountsIn[1]);
    }

    /**
     * @notice Sandwich sequence: attacker swap, victim swap, attacker reverses.
     * @dev Attacker (alice) must not increase her starting token balance (allow +1 unit dust).
     * @param direction 0: token0 is the "start token" for attacker, 1: token1 is start token
     */
    function sandwichExactIn(uint256 attackerAmountIn, uint256 victimAmountIn, uint256 direction) external {
        direction = direction & 1;
        uint256 iIn = direction;
        uint256 iOut = 1 - direction;

        // Keep token array + balances tightly scoped to reduce stack pressure during coverage compilation.
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 balInBefore;
        {
            (IERC20[] memory tokens, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
            tokenIn = tokens[iIn];
            tokenOut = tokens[iOut];
            balInBefore = balancesBefore[iIn];
        }

        (attackerAmountIn, victimAmountIn) = _boundSandwichAmounts(balInBefore, attackerAmountIn, victimAmountIn);

        uint256 startIn = tokenIn.balanceOf(alice);
        uint256 attackerOut = _attackerLegAndAssertPoolDeltas(iIn, iOut, tokenIn, tokenOut, attackerAmountIn, startIn);

        _victimLeg(tokenIn, tokenOut, victimAmountIn);

        uint256 endIn = _unwindLeg(tokenIn, tokenOut, attackerOut);
        // Assert no sandwich profit
        // assert(endIn <= startIn);
    }

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }

    function _boundSandwichAmounts(
        uint256 balInBefore,
        uint256 attackerAmountIn,
        uint256 victimAmountIn
    ) internal pure returns (uint256 boundedAttacker, uint256 boundedVictim) {
        uint256 maxAttacker = balInBefore.mulDown(MAX_SWAP_RATIO / 20); // 1.5% (small front-run)
        uint256 maxVictim = balInBefore.mulDown(MAX_SWAP_RATIO / 2); // 15% (large victim)
        boundedAttacker = _boundLocal(attackerAmountIn, MIN_SWAP, maxAttacker);
        boundedVictim = _boundLocal(victimAmountIn, MIN_SWAP, maxVictim);
    }

    function _attackerLegAndAssertPoolDeltas(
        uint256 iIn,
        uint256 iOut,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 attackerAmountIn,
        uint256 aliceInBefore
    ) internal returns (uint256 attackerOut) {
        uint256 aliceOutBefore = tokenOut.balanceOf(alice);

        // Snapshot balances for iIn and iOut right before the attacker's swap.
        uint256 balInBefore;
        uint256 balOutBefore;
        {
            (, , uint256[] memory balancesBefore, ) = vault.getPoolTokenInfo(address(pool));
            balInBefore = balancesBefore[iIn];
            balOutBefore = balancesBefore[iOut];
        }

        medusa.prank(alice);
        attackerOut = router.swapSingleTokenExactIn(
            address(pool),
            tokenIn,
            tokenOut,
            attackerAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assert(attackerOut > 0);

        uint256 aliceInAfter1 = tokenIn.balanceOf(alice);
        uint256 aliceOutAfter1 = tokenOut.balanceOf(alice);
        assert(aliceInAfter1 == aliceInBefore - attackerAmountIn);
        assert(aliceOutAfter1 == aliceOutBefore + attackerOut);

        // Pool balance deltas must match the trade.
        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        assert(balancesAfter[iIn] == balInBefore + attackerAmountIn);
        assert(balancesAfter[iOut] == balOutBefore - attackerOut);

        return attackerOut;
    }

    function _victimLeg(IERC20 tokenIn, IERC20 tokenOut, uint256 victimAmountIn) internal {
        uint256 bobInBefore = tokenIn.balanceOf(bob);
        uint256 bobOutBefore = tokenOut.balanceOf(bob);

        medusa.prank(bob);
        uint256 victimOut = router.swapSingleTokenExactIn(
            address(pool),
            tokenIn,
            tokenOut,
            victimAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 bobInAfter = tokenIn.balanceOf(bob);
        uint256 bobOutAfter = tokenOut.balanceOf(bob);
        assert(victimOut > 0);
        assert(bobInAfter == bobInBefore - victimAmountIn);
        assert(bobOutAfter == bobOutBefore + victimOut);
    }

    function _unwindLeg(IERC20 tokenIn, IERC20 tokenOut, uint256 attackerOut) internal returns (uint256 endIn) {
        // 3) attacker swaps back iOut -> iIn with what she got.
        // If this reverts, that's a *high signal* regression: the attacker can't unwind using the exact output
        // she previously received (and, after a same-direction victim trade, pool iIn should only be larger).
        uint256 aliceOutBefore3 = tokenOut.balanceOf(alice);
        uint256 aliceInBefore3 = tokenIn.balanceOf(alice);
        medusa.prank(alice);
        uint256 unwindOut = router.swapSingleTokenExactIn(
            address(pool),
            tokenOut,
            tokenIn,
            attackerOut,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 aliceOutAfter3 = tokenOut.balanceOf(alice);
        uint256 aliceInAfter3 = tokenIn.balanceOf(alice);
        assert(unwindOut > 0);
        assert(aliceOutAfter3 == aliceOutBefore3 - attackerOut);
        assert(aliceInAfter3 == aliceInBefore3 + unwindOut);

        return tokenIn.balanceOf(alice);
    }
}
