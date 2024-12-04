// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Test the mathematical approximation that allows handling liquidity operations in the Vault.
 * @dev Liquidity operations that are unbalanced allow for indirect swaps. It is crucial to guarantee
 * that the swap fees for indirect swaps facilitated through liquidity operations are not lower than
 * those for direct swaps.
 *
 * This is a base contract that can be reused for each pool type. There are existing derived contracts
 * for Stable and Weighted Pools.
 *
 * To ensure this, we analyze the results of two different operations:
 * unbalanced liquidity operation (addLiquidityUnbalanced) combined with
 * add/remove liquidity proportionally, and swapExactIn. Consider the following scenario:
 *
 * Pool begins with balances of [100, 100].
 * Alice begins with balances of [100, 0].
 * She executes addLiquidityUnbalanced([100, 0]) and subsequently removeLiquidityProportionally,
 * resulting in balances of [66, 33].
 * Bob, starting with the same balances [100, 0], performs a swapExactIn(34).
 * We determine the amount Alice indirectly traded as 34 (100 - 66 = 34),
 * enabling us to compare the swap fees incurred on the trade.
 * This comparison ensures that the fees for a direct swap remain lower than those for an indirect swap.
 * Finally, we assess the final balances of Alice and Bob. Two criteria must be satisfied:
 *   a. The initial coin balances for the trade should be identical,
 *      meaning Alice's [66, ...] should correspond to Bob's [66, ...].
 *   b. The resulting balances from the trade should ensure that Bob always has an equal or greater amount than Alice.
 *      But the difference should never be too much, i.e. we don't want to steal from users on liquidity operations.
 *      This implies that Alice's balance [..., 33] should be less than or at most equal to Bob's [..., 34].
 *
 * This methodology and evaluation criteria are applicable to all unbalanced liquidity operations and pool types.
 * Furthermore, this approach validates the correct amount of BPT minted/burned for liquidity operations.
 * If more BPT were minted or fewer BPT were burned than required,
 * it would result in Alice having more assets at the end than Bob, which we have verified to be untrue.
 *
 * Bob should always maintain a balance of USDC equal to or greater than Alice's
 * since liquidity operations should not confer any advantage over a pure swap.
 * At the same time, we aim to avoid unfairly diminishing user balances.
 * Therefore, Alice's balance should ideally be slightly less than Bob's,
 * though extremely close. This allowance for a minor discrepancy accounts
 * for the inherent imperfections in Solidity's mathematics and rounding errors in the code.
 */
contract LiquidityApproximationTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    address internal swapPool;
    address internal liquidityPool;
    // Allow small roundingDelta to account for rounding.
    // Up to this delta it's acceptable for it to be beneficial to swap with the direct method vs swapping with the
    // indirect method).
    uint256 internal excessRoundingDelta = 0.05e16; // 0.05%

    // We want the indirect method to be as close to the direct one in the worst case. Therefore, the delta
    // in the opposite direction (i.e. indirect better than direct) is much tighter.
    uint256 internal defectRoundingDelta = 0.0000001e16; // 0.0000001%

    // Absolute rounding delta whenever indirect method is more beneficial.
    uint256 internal absoluteRoundingDelta = 1e12;

    // The percentage delta of the swap fee, which is sufficiently large to compensate for
    // inaccuracies in liquidity approximations within the specified limits for these tests.
    uint256 internal liquidityPercentageDelta = 25e16; // 25%
    uint256 internal swapFeePercentageDelta = 20e16; // 20%

    // Pool dependent: min / max swap fee percentage.
    // Overwrite these in pool-specific setups if required.
    uint256 internal maxSwapFeePercentage = 10e16; // 10%;
    uint256 internal minSwapFeePercentage = 0;
    uint256 internal maxAmount = 3e8 * 1e18 - 1;
    uint256 internal minAmount = 1e18;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        poolInitAmount = 1e9 * 1e18;
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        approveForPool(IERC20(liquidityPool));
        approveForPool(IERC20(swapPool));

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
    }

    function createPool() internal virtual override returns (address, bytes memory) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        (liquidityPool, ) = _createPool(tokens, "liquidityPool");
        (swapPool, ) = _createPool(tokens, "swapPool");

        // NOTE: return is empty, because this test does not use the `pool` variable.
        return (address(0), bytes(""));
    }

    function initPool() internal override {
        vm.startPrank(lp);
        _initPool(swapPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(liquidityPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    // Add

    function testAddLiquidityUnbalanced__Fuzz(uint256 daiAmountIn, uint256 swapFeePercentage) public {
        daiAmountIn = bound(daiAmountIn, minAmount, maxAmount);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        uint256 amountOut = addUnbalancedOnlyDai(daiAmountIn, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquidityUnbalancedNoSwapFee__Fuzz(uint256 daiAmountIn) public {
        daiAmountIn = bound(daiAmountIn, minAmount, maxAmount);
        addUnbalancedOnlyDai(daiAmountIn, 0);
        assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquiditySingleTokenExactOut__Fuzz(uint256 exactBptAmountOut, uint256 swapFeePercentage) public {
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, maxAmount / 2 - 1);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        uint256 amountOut = addExactOutArbitraryBptOut(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquiditySingleTokenExactOutNoSwapFee__Fuzz(uint256 exactBptAmountOut) public {
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, maxAmount / 2 - 1);
        addExactOutArbitraryBptOut(exactBptAmountOut, 0);
        assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquidityProportionalAndRemoveExactIn__Fuzz(
        uint256 exactBptAmount,
        uint256 swapFeePercentage
    ) public {
        exactBptAmount = bound(exactBptAmount, minAmount, maxAmount / 2 - 1);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        uint256 amountOut = removeExactInAllBptIn(exactBptAmount, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testAddLiquidityProportionalAndRemoveExactInNoSwapFee__Fuzz(uint256 exactBptAmount) public {
        exactBptAmount = bound(exactBptAmount, minAmount, maxAmount / 2 - 1);
        removeExactInAllBptIn(exactBptAmount, 0);
        assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquidityProportionalAndRemoveExactOut__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage
    ) public {
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, maxAmount / 2 - 1);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);

        uint256 amountOut = removeExactOutAllUsdcAmountOut(exactBptAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testAddLiquidityProportionalAndRemoveExactOutNoSwapFee__Fuzz(uint256 exactBptAmountOut) public {
        exactBptAmountOut = bound(exactBptAmountOut, minAmount, maxAmount / 2 - 1);

        removeExactOutAllUsdcAmountOut(exactBptAmountOut, 0);
        assertLiquidityOperationNoSwapFee();
    }

    // Remove

    function testRemoveLiquiditySingleTokenExactOut__Fuzz(
        uint256 exactAmountOut,
        uint256 swapFeePercentage
    ) public virtual {
        exactAmountOut = bound(exactAmountOut, minAmount, maxAmount);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);

        uint256 amountOut = removeExactOutArbitraryAmountOut(exactAmountOut, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactOutNoSwapFee__Fuzz(uint256 exactAmountOut) public virtual {
        exactAmountOut = bound(exactAmountOut, minAmount, maxAmount);

        removeExactOutArbitraryAmountOut(exactAmountOut, 0);
        assertLiquidityOperationNoSwapFee();
    }

    function testRemoveLiquiditySingleTokenExactIn__Fuzz(uint256 exactBptAmountIn, uint256 swapFeePercentage) public {
        exactBptAmountIn = bound(exactBptAmountIn, minAmount, maxAmount);
        swapFeePercentage = bound(swapFeePercentage, minSwapFeePercentage, maxSwapFeePercentage);
        uint256 amountOut = removeExactInArbitraryBptIn(exactBptAmountIn, swapFeePercentage);
        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactInNoSwapFee__Fuzz(uint256 exactBptAmountIn) public {
        exactBptAmountIn = bound(exactBptAmountIn, minAmount, maxAmount);
        removeExactInArbitraryBptIn(exactBptAmountIn, 0);
        assertLiquidityOperationNoSwapFee();
    }

    // Utils

    function assertLiquidityOperationNoSwapFee() internal {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        // Alice and Bob have no BPT tokens.
        assertEq(IERC20(swapPool).balanceOf(alice), 0, "Alice should have 0 BPT");
        assertEq(IERC20(liquidityPool).balanceOf(alice), 0, "Alice should have 0 BPT");
        assertEq(IERC20(swapPool).balanceOf(bob), 0, "Bob should have 0 BPT");
        assertEq(IERC20(liquidityPool).balanceOf(bob), 0, "Bob should have 0 BPT");

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        if (usdc.balanceOf(alice) <= defaultBalance) {
            // No amount out (trade too small, rounding ate the difference).
            // Dai balances are the same, so we just check that the USDC balances are better for Bob (direct swap).
            // There's no point in continuing the test in this case.
            assertGe(usdc.balanceOf(bob), usdc.balanceOf(alice), "Alice lost less than bob");
            return;
        }

        uint256 aliceAmountOut = usdc.balanceOf(alice) - defaultBalance;
        uint256 bobAmountOut = usdc.balanceOf(bob) - defaultBalance;
        uint256 bobToAliceRatio = bobAmountOut.divDown(aliceAmountOut);

        // Early returns:
        // - 0 output for direct swaps: check that the indirect swap output is very low.
        // - Very small indirect output: it's not worth checking relative error.
        if (bobAmountOut == 0) {
            assertLe(aliceAmountOut, PRODUCTION_MIN_TRADE_AMOUNT, "Bob got 0 and Alice got something");
            return;
        } else if (aliceAmountOut < absoluteRoundingDelta) {
            assertGe(bobToAliceRatio, 1e18, "Bob got less USDC than Alice");
            return;
        }

        // `bobAmountOut >= aliceAmountOut - absoluteRoundingDelta`
        assertGe(bobAmountOut, aliceAmountOut - absoluteRoundingDelta, "Swap fee delta is too big");

        // It's ok if a direct swap is more convenient than an indirect swap, up to `excessRoundingDelta`.
        // In the other direction, the margin is tighter.
        assertGe(bobToAliceRatio, 1e18 - defectRoundingDelta, "Bob has less USDC compared to Alice");
        assertLe(bobToAliceRatio, 1e18 + excessRoundingDelta, "Bob has too much USDC compared to Alice");
    }

    function assertLiquidityOperation(uint256 amountOut, uint256 swapFeePercentage, bool addLiquidity) internal view {
        // Alice and Bob have no BPT tokens.
        assertEq(IERC20(swapPool).balanceOf(alice), 0, "Alice should have 0 BPT");
        assertEq(IERC20(liquidityPool).balanceOf(alice), 0, "Alice should have 0 BPT");
        assertEq(IERC20(swapPool).balanceOf(bob), 0, "Bob should have 0 BPT");
        assertEq(IERC20(liquidityPool).balanceOf(bob), 0, "Bob should have 0 BPT");

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        if (usdc.balanceOf(alice) <= defaultBalance) {
            // No amount out (trade too small, rounding ate the difference).
            // Dai balances are the same, so we just check that the USDC balances are better for Bob (direct swap).
            // There's no point in continuing the test in this case.
            assertGe(usdc.balanceOf(bob), usdc.balanceOf(alice), "Alice lost less than bob");
            return;
        }

        uint256 aliceAmountOut = usdc.balanceOf(alice) - defaultBalance;
        uint256 bobAmountOut = usdc.balanceOf(bob) - defaultBalance;
        uint256 bobToAliceRatio = bobAmountOut.divDown(aliceAmountOut);

        uint256 liquidityTaxPercentage = liquidityPercentageDelta.mulDown(swapFeePercentage);

        uint256 swapFee = amountOut.divUp(swapFeePercentage.complement()) - amountOut;

        // `bobAmountOut >= aliceAmountOut - swapFee * swapFeePercentageDelta - absoluteRoundingDelta`
        // Solve for `aliceAmountOut` to prevent underflows when `aliceAmountOut` is close to 0.
        assertGe(
            bobAmountOut + swapFee.mulDown(swapFeePercentageDelta) + absoluteRoundingDelta,
            aliceAmountOut,
            "Swap fee delta is too big"
        );

        assertGe(
            bobToAliceRatio,
            1e18 - (addLiquidity ? liquidityTaxPercentage : 0) - defectRoundingDelta,
            "Bob has too little USDC compared to Alice"
        );

        if (bobToAliceRatio < 1e18) {
            // Worst case: Alice got more than Bob.
            // The discount needs to be smaller than the swap fee percentage.
            uint256 discountPercentage = 1e18 - bobToAliceRatio;
            assertLt(discountPercentage, swapFeePercentage, "Discount percentage is larger than swap fee percentage");
        } else {
            // OK case: Bob got more than Alice.
            assertLe(
                bobToAliceRatio,
                1e18 + (addLiquidity ? 0 : liquidityTaxPercentage) + excessRoundingDelta,
                "Bob has too much USDC compared to Alice"
            );
        }
    }

    function addUnbalancedOnlyDai(uint256 daiAmountIn, uint256 swapFeePercentage) internal returns (uint256 amountOut) {
        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[daiIdx] = uint256(daiAmountIn);

        vm.startPrank(alice);
        router.addLiquidityUnbalanced(address(liquidityPool), amountsIn, 0, false, bytes(""));

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );
        vm.stopPrank();

        vm.prank(bob);
        amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[daiIdx],
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function addExactOutArbitraryBptOut(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage
    ) internal returns (uint256 amountOut) {
        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        vm.startPrank(alice);
        uint256 daiAmountIn = router.addLiquiditySingleTokenExactOut(
            address(liquidityPool),
            dai,
            MAX_UINT128,
            exactBptAmountOut,
            false,
            bytes("")
        );

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );
        vm.stopPrank();

        vm.prank(bob);
        amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[daiIdx],
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function removeExactInAllBptIn(
        uint256 exactBptAmount,
        uint256 swapFeePercentage
    ) internal returns (uint256 amountOut) {
        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        vm.startPrank(alice);
        router.addLiquidityProportional(
            address(liquidityPool),
            [MAX_UINT128, MAX_UINT128].toMemoryArray(),
            exactBptAmount,
            false,
            bytes("")
        );

        router.removeLiquiditySingleTokenExactIn(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            usdc,
            1,
            false,
            bytes("")
        );

        vm.stopPrank();

        vm.startPrank(bob);
        // Simulate the same outcome with a pure swap.
        amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            defaultBalance - dai.balanceOf(alice),
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function removeExactInArbitraryBptIn(
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage
    ) internal returns (uint256 amountOut) {
        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        // Add liquidity so we have something to remove.
        vm.prank(alice);
        router.addLiquidityProportional(
            address(liquidityPool),
            [MAX_UINT128, MAX_UINT128].toMemoryArray(),
            2 * maxAmount,
            false,
            bytes("")
        );

        // Cap exact amount in to the total BPT balance for Alice (can't exit without enough BPT).
        exactBptAmountIn = Math.min(IERC20(liquidityPool).balanceOf(alice), exactBptAmountIn);

        vm.startPrank(alice);
        router.removeLiquiditySingleTokenExactIn(address(liquidityPool), exactBptAmountIn, usdc, 1, false, bytes(""));

        // Remove remaining liquidity.
        router.removeLiquidityProportional(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        vm.startPrank(bob);
        // Simulate the same outcome with a pure swap.
        amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            defaultBalance - dai.balanceOf(alice),
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function removeExactOutAllUsdcAmountOut(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage
    ) internal returns (uint256 amountOut) {
        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        vm.startPrank(alice);
        uint256[] memory amountsIn = router.addLiquidityProportional(
            address(liquidityPool),
            [uint256(MAX_UINT128), MAX_UINT128].toMemoryArray(),
            exactBptAmountOut,
            false,
            bytes("")
        );

        (, uint256 usdcIndex) = getSortedIndexes(address(dai), address(usdc));
        router.removeLiquiditySingleTokenExactOut(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            usdc,
            amountsIn[usdcIndex],
            false,
            bytes("")
        );

        // Remove remaining liquidity.
        router.removeLiquidityProportional(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        vm.startPrank(bob);
        // Simulate the same outcome with a pure swap.
        amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            defaultBalance - dai.balanceOf(alice),
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function removeExactOutArbitraryAmountOut(
        uint256 exactAmountOut,
        uint256 swapFeePercentage
    ) internal returns (uint256 amountOut) {
        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        // Add liquidity so we have something to remove.
        uint256 currentTotalSupply = IERC20(liquidityPool).totalSupply();
        vm.prank(alice);
        router.addLiquidityProportional(
            address(liquidityPool),
            [MAX_UINT128, MAX_UINT128].toMemoryArray(),
            currentTotalSupply * 10,
            false,
            bytes("")
        );

        vm.startPrank(alice);
        router.removeLiquiditySingleTokenExactOut(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            usdc,
            exactAmountOut,
            false,
            bytes("")
        );

        // Remove remaining liquidity.
        router.removeLiquidityProportional(
            address(liquidityPool),
            IERC20(liquidityPool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        vm.startPrank(bob);
        // Simulate the same outcome with a pure swap.
        amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            defaultBalance - dai.balanceOf(alice),
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }
}
