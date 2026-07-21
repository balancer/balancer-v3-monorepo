// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseECLPSpecificTest } from "./utils/BaseECLPSpecificTest.sol";

/**
 * @notice Fuzz tests asserting that liquidity round trips around a swap are never profitable on this E-CLP.
 * @dev Three attacker shapes are covered: add -> swap -> remove (self-sandwich), remove -> swap -> add (the
 * flash-loan-shaped ordering), and a plain proportional add -> remove round trip. All three additionally assert that
 * the BPT rate (`vault.getBptRate`, i.e. pool invariant divided by total supply) never decreases across the whole
 * sequence, which is what actually means "the LPs that stayed in the pool were not diluted". That is the same
 * property the Medusa campaigns track as `property_currentBptRate`, read through the same Vault getter.
 *
 * The pool configuration, the price-1 initialization and the state readers live in `BaseECLPSpecificTest`.
 *
 * ## Valuation of the attacker's holdings
 *
 * The attacker changes the composition of their holdings, so the two tokens have to be valued against each other
 * somehow. This suite values them 1:1, summing the 18-decimal-scaled balances of both tokens. That choice is
 * defensible for this specific pool: the whole reachable price interval is
 * `[alpha, beta] = [0.980392156862745098, 1.000000630371029932]`, so in any state the pool can reach, one unit of
 * token 0 is worth between 0.9804 and 1.0000007 units of token 1, and the pool starts at exactly 1.
 *
 * The residual ambiguity of the 1:1 sum is therefore at most 6.3e-7 relative (`beta - 1`), in the direction that
 * favours an attacker who ends up long token 0. That is more than two orders of magnitude smaller than the 1e-4 swap
 * fee every attacker in these sequences has to pay, so the conclusion is not load-bearing on the valuation choice.
 * No tolerance is added on top: the assertions below are exact.
 */
contract LiquidityRoundTripECLPSpecificTest is BaseECLPSpecificTest {
    // Fraction of the pool's total supply that the "existing LP" attacker of test 2 holds before the attack starts.
    uint256 internal constant _LP_STAKE_DIVISOR = 10;

    // Amount minted to the attacker for every freshly created token; matches what the base mints to `lp`.
    uint256 internal constant _ATTACKER_MINT_AMOUNT = 1e32;

    function setUp() public virtual override {
        BaseECLPSpecificTest.setUp();
    }

    /**
     * @notice Add liquidity, move the price with a swap, then withdraw: the attacker must not come out ahead.
     * @dev The attacker adds unbalanced (so they can pick the composition that suits them), swaps in either
     * direction, then burns exactly the BPT they minted. They start and end with zero BPT, so comparing their raw
     * token holdings before and after is a complete accounting of the sequence.
     */
    function testAddSwapRemoveIsNotProfitable__Fuzz(
        uint256 balance0Scaled18,
        uint256 addAmount0Scaled18,
        uint256 addAmount1Scaled18,
        uint256 swapAmountScaled18,
        bool swap0To1,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balance0Scaled18 = bound(balance0Scaled18, _MIN_BALANCE0_SCALED18, _MAX_BALANCE0_SCALED18);

        PoolSetup memory setup = _createAndInitPoolAtPriceOne(decimalsA, decimalsB, balance0Scaled18);
        _assertSpotPriceIsOne(setup.pool);
        _fundAttacker(setup);

        // The base fixture creates the pool with `disableUnbalancedLiquidity = false`; assert it rather than trust it,
        // since the whole test would silently change shape if that ever flipped.
        PoolConfig memory config = vault.getPoolConfig(setup.pool);
        assertFalse(config.liquidityManagement.disableUnbalancedLiquidity, "Unbalanced liquidity is disabled");

        uint256 bptRateBefore = vault.getBptRate(setup.pool);
        uint256 valueBefore = _attackerValueScaled18(setup);

        uint256 bptOut = _addUnbalanced(setup, balance0Scaled18, addAmount0Scaled18, addAmount1Scaled18);

        _swapExactIn(setup, swapAmountScaled18, swap0To1);

        vm.prank(alice);
        router.removeLiquidityProportional(setup.pool, bptOut, new uint256[](2), false, bytes(""));

        assertEq(IERC20(setup.pool).balanceOf(alice), 0, "Attacker still holds BPT");

        uint256 valueAfter = _attackerValueScaled18(setup);

        assertLe(valueAfter, valueBefore, "Add -> swap -> remove was profitable");
        assertGe(vault.getBptRate(setup.pool), bptRateBefore, "BPT rate decreased over add -> swap -> remove");
    }

    /**
     * @notice Withdraw liquidity, move the price with a swap, then re-enter with the same BPT amount.
     * @dev This is the flash-loan-shaped ordering. The attacker is an existing LP; they burn some BPT, swap, then
     * mint back exactly the BPT they burned. Since the BPT position is identical before and after, comparing raw
     * token holdings is again a complete accounting.
     */
    function testRemoveSwapAddIsNotProfitable__Fuzz(
        uint256 balance0Scaled18,
        uint256 bptInPercentage,
        uint256 swapAmountScaled18,
        bool swap0To1,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balance0Scaled18 = bound(balance0Scaled18, _MIN_BALANCE0_SCALED18, _MAX_BALANCE0_SCALED18);

        PoolSetup memory setup = _createAndInitPoolAtPriceOne(decimalsA, decimalsB, balance0Scaled18);
        _assertSpotPriceIsOne(setup.pool);
        _fundAttacker(setup);

        // The attacker becomes an existing LP first; that add is not part of the measured sequence.
        uint256 stake = IERC20(setup.pool).totalSupply() / _LP_STAKE_DIVISOR;
        _addProportional(setup, stake);

        uint256 bptRateBefore = vault.getBptRate(setup.pool);
        uint256 valueBefore = _attackerValueScaled18(setup);

        uint256 bptIn = bound(bptInPercentage, stake / 10, stake);

        vm.prank(alice);
        router.removeLiquidityProportional(setup.pool, bptIn, new uint256[](2), false, bytes(""));

        _swapExactIn(setup, swapAmountScaled18, swap0To1);

        _addProportional(setup, bptIn);

        assertEq(IERC20(setup.pool).balanceOf(alice), stake, "Attacker did not restore the original BPT position");

        uint256 valueAfter = _attackerValueScaled18(setup);

        assertLe(valueAfter, valueBefore, "Remove -> swap -> add was profitable");
        assertGe(vault.getBptRate(setup.pool), bptRateBefore, "BPT rate decreased over remove -> swap -> add");
    }

    /**
     * @notice Proportional add immediately followed by a proportional remove of all the BPT received.
     * @dev No swap in between, so this isolates the rounding direction of the two liquidity operations. The LP must
     * get back at most what they put in, for each token individually (not just in aggregate).
     */
    function testProportionalAddRemoveRoundTrip__Fuzz(
        uint256 balance0Scaled18,
        uint256 bptOutPercentage,
        uint8 decimalsA,
        uint8 decimalsB
    ) public {
        decimalsA = uint8(bound(decimalsA, _MIN_DECIMALS, _MAX_DECIMALS));
        decimalsB = uint8(bound(decimalsB, _MIN_DECIMALS, _MAX_DECIMALS));
        balance0Scaled18 = bound(balance0Scaled18, _MIN_BALANCE0_SCALED18, _MAX_BALANCE0_SCALED18);

        PoolSetup memory setup = _createAndInitPoolAtPriceOne(decimalsA, decimalsB, balance0Scaled18);
        _assertSpotPriceIsOne(setup.pool);
        _fundAttacker(setup);

        uint256 bptRateBefore = vault.getBptRate(setup.pool);

        uint256 totalSupply = IERC20(setup.pool).totalSupply();
        uint256 exactBptAmountOut = bound(bptOutPercentage, totalSupply / 1000, totalSupply / _LP_STAKE_DIVISOR);

        uint256[] memory amountsIn = _addProportional(setup, exactBptAmountOut);

        vm.prank(alice);
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            setup.pool,
            exactBptAmountOut,
            new uint256[](2),
            false,
            bytes("")
        );

        assertEq(IERC20(setup.pool).balanceOf(alice), 0, "Attacker still holds BPT");

        assertLe(amountsOut[0], amountsIn[0], "Proportional round trip returned more of token 0 than it took");
        assertLe(amountsOut[1], amountsIn[1], "Proportional round trip returned more of token 1 than it took");
        assertGe(vault.getBptRate(setup.pool), bptRateBefore, "BPT rate decreased over the proportional round trip");
    }

    /**
     * @dev Performs the attacker's unbalanced add, sizing both legs against the initial token 0 balance.
     *
     * Capping the token 1 leg by the token 0 balance keeps that leg tiny relative to the token 1 side (~0.001% of
     * it), which is unavoidable here: the pool is ~99.99% token 1 and sits 6.3e-7 below `beta`, so a token 1 deposit
     * large enough to matter for the token 1 side would push far outside the pool's invariant ratio bounds.
     *
     * @param setup The pool under test
     * @param balance0Scaled18 The token 0 balance the pool was initialized with
     * @param addAmount0Scaled18 Raw fuzz input for the token 0 leg, bounded here
     * @param addAmount1Scaled18 Raw fuzz input for the token 1 leg, bounded here
     * @return bptOut BPT minted to the attacker
     */
    function _addUnbalanced(
        PoolSetup memory setup,
        uint256 balance0Scaled18,
        uint256 addAmount0Scaled18,
        uint256 addAmount1Scaled18
    ) internal returns (uint256 bptOut) {
        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = _toRawAmount(
            bound(addAmount0Scaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10),
            setup.decimals0
        );
        exactAmountsIn[1] = _toRawAmount(
            bound(addAmount1Scaled18, _MIN_SWAP_SCALED18, balance0Scaled18 / 10),
            setup.decimals1
        );

        vm.prank(alice);
        bptOut = router.addLiquidityUnbalanced(setup.pool, exactAmountsIn, 0, false, bytes(""));
    }

    /**
     * @dev Adds liquidity proportionally as the attacker, for an exact BPT amount out.
     * @dev The `maxAmountsIn` limits are the attacker's full balances, so they are never binding. They have to be
     * read before the `prank`, since a `staticcall` in the argument list would consume it.
     *
     * @param setup The pool under test
     * @param exactBptAmountOut BPT to mint to the attacker
     * @return amountsIn Token amounts actually pulled from the attacker
     */
    function _addProportional(
        PoolSetup memory setup,
        uint256 exactBptAmountOut
    ) internal returns (uint256[] memory amountsIn) {
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = setup.token0.balanceOf(alice);
        maxAmountsIn[1] = setup.token1.balanceOf(alice);

        vm.prank(alice);
        amountsIn = router.addLiquidityProportional(setup.pool, maxAmountsIn, exactBptAmountOut, false, bytes(""));
    }

    /**
     * @dev Performs the attacker's price-moving swap, sized against the live token 0 balance.
     *
     * Token 0 is by far the scarcer side of this pool (it starts ~6.3e-7 below `beta`, holding ~0.01% token 0), and
     * it is what limits the reachable trade size in both directions: selling token 0 is capped by how much token 1
     * the pool can pay out, and buying it is capped by how little of it there is. 10% of the token 0 balance is
     * comfortably reachable either way, which is why the same cap is used for both directions here.
     *
     * @param setup The pool under test
     * @param swapAmountScaled18 Raw fuzz input for the trade size, bounded here
     * @param swap0To1 True to sell token 0, false to sell token 1
     */
    function _swapExactIn(PoolSetup memory setup, uint256 swapAmountScaled18, bool swap0To1) internal {
        uint256[] memory liveBalances = vault.getCurrentLiveBalances(setup.pool);

        (IERC20 tokenIn, IERC20 tokenOut) = swap0To1 ? (setup.token0, setup.token1) : (setup.token1, setup.token0);
        uint8 decimalsIn = swap0To1 ? setup.decimals0 : setup.decimals1;

        swapAmountScaled18 = bound(swapAmountScaled18, _MIN_SWAP_SCALED18, liveBalances[0] / 10);
        uint256 amountInRaw = _toRawAmount(swapAmountScaled18, decimalsIn);

        vm.prank(alice);
        router.swapSingleTokenExactIn(setup.pool, tokenIn, tokenOut, amountInRaw, 0, MAX_UINT256, false, bytes(""));
    }

    /// @dev Mints both pool tokens to the attacker and grants every approval the Router needs on their behalf.
    function _fundAttacker(PoolSetup memory setup) internal {
        ERC20TestToken(address(setup.token0)).mint(alice, _ATTACKER_MINT_AMOUNT);
        ERC20TestToken(address(setup.token1)).mint(alice, _ATTACKER_MINT_AMOUNT);

        vm.startPrank(alice);
        setup.token0.approve(address(permit2), MAX_UINT256);
        setup.token1.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(setup.token0), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(setup.token1), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        approveForPool(IERC20(setup.pool));
    }

    /// @dev The attacker's combined token holdings, valuing both tokens 1:1 (see the contract-level comment).
    function _attackerValueScaled18(PoolSetup memory setup) internal view returns (uint256) {
        return
            setup.token0.balanceOf(alice) *
            (10 ** (18 - setup.decimals0)) +
            setup.token1.balanceOf(alice) *
            (10 ** (18 - setup.decimals1));
    }
}
