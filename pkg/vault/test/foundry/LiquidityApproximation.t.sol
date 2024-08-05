// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    // Allows small roundingDelta to account for rounding.
    uint256 internal roundingDelta = 1e12;
    // The percentage delta of the swap fee, which is sufficiently large to compensate for
    // inaccuracies in liquidity approximations within the specified limits for these tests.
    uint256 internal liquidityPercentageDelta = 25e16; // 25%
    uint256 internal swapFeePercentageDelta = 20e16; // 20%
    uint256 internal maxSwapFeePercentage = 10e16; // 10%
    uint256 internal maxAmount = 3e8 * 1e18 - 1;

    uint256 internal daiIdx;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        approveForPool(IERC20(liquidityPool));
        approveForPool(IERC20(swapPool));

        (daiIdx, ) = getSortedIndexes(address(dai), address(usdc));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");
    }

    function createPool() internal virtual override returns (address) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        liquidityPool = _createPool(tokens, "liquidityPool");
        swapPool = _createPool(tokens, "swapPool");

        // NOTE: stores address in `pool` (unused in this test).
        return address(0);
    }

    function initPool() internal override {
        poolInitAmount = 1e9 * 1e18;

        vm.startPrank(lp);
        _initPool(swapPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(liquidityPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    /// Add

    function testAddLiquidityUnbalanced__Fuzz(uint256 daiAmountIn, uint256 swapFeePercentage) public {
        daiAmountIn = bound(daiAmountIn, 1e18, maxAmount);
        // Vary swap fee from 0% - 10%.
        swapFeePercentage = bound(swapFeePercentage, 0, maxSwapFeePercentage);

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
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[daiIdx],
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquidityUnbalancedNoSwapFee__Fuzz(uint256 daiAmountIn) public {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        daiAmountIn = bound(daiAmountIn, 1e18, maxAmount);

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
        router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[daiIdx],
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquiditySingleTokenExactOut__Fuzz(uint256 exactBptAmountOut, uint256 swapFeePercentage) public {
        exactBptAmountOut = bound(exactBptAmountOut, 1e18, maxAmount / 2 - 1);
        // Vary swap fee from 0% - 10%.
        swapFeePercentage = bound(swapFeePercentage, 0, maxSwapFeePercentage);

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
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[daiIdx],
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertLiquidityOperation(amountOut, swapFeePercentage, true);
    }

    function testAddLiquiditySingleTokenExactOutNoSwapFee__Fuzz(uint256 exactBptAmountOut) public {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        exactBptAmountOut = bound(exactBptAmountOut, 1e18, maxAmount / 2 - 1);

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
        router.swapSingleTokenExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[daiIdx],
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquidityProportionalAndRemoveExactIn__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage
    ) public {
        exactBptAmountOut = bound(exactBptAmountOut, 1e18, maxAmount / 2 - 1);

        // Vary swap fee from 0% - 10%.
        swapFeePercentage = bound(swapFeePercentage, 0, maxSwapFeePercentage);

        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        vm.startPrank(alice);
        router.addLiquidityProportional(
            address(liquidityPool),
            [MAX_UINT128, MAX_UINT128].toMemoryArray(),
            exactBptAmountOut,
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
        uint256 amountOut = router.swapSingleTokenExactIn(
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

        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testAddLiquidityProportionalAndRemoveExactInNoSwapFee__Fuzz(uint256 exactBptAmountOut) public {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        exactBptAmountOut = bound(exactBptAmountOut, 1e18, maxAmount / 2 - 1);

        vm.startPrank(alice);
        router.addLiquidityProportional(
            address(liquidityPool),
            [uint256(MAX_UINT128), MAX_UINT128].toMemoryArray(),
            exactBptAmountOut,
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
        router.swapSingleTokenExactIn(
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

        assertLiquidityOperationNoSwapFee();
    }

    function testAddLiquidityProportionalAndRemoveExactOut__Fuzz(
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage
    ) public {
        exactBptAmountOut = bound(exactBptAmountOut, 1e18, maxAmount / 2 - 1);

        // Vary swap fee from 0% - 10%.
        swapFeePercentage = bound(swapFeePercentage, 0, maxSwapFeePercentage);

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
        uint256 amountOut = router.swapSingleTokenExactIn(
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

        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testAddLiquidityProportionalAndRemoveExactOutNoSwapFee__Fuzz(uint256 exactBptAmountOut) public {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        exactBptAmountOut = bound(exactBptAmountOut, 1e18, maxAmount / 2 - 1);

        vm.startPrank(alice);
        uint256[] memory amountsIn = router.addLiquidityProportional(
            address(liquidityPool),
            [MAX_UINT128, MAX_UINT128].toMemoryArray(),
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
        router.swapSingleTokenExactIn(
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

        assertLiquidityOperationNoSwapFee();
    }

    /// Remove

    function testRemoveLiquiditySingleTokenExact__Fuzz(uint256 exactAmountOut, uint256 swapFeePercentage) public {
        exactAmountOut = bound(exactAmountOut, 1e18, maxAmount);
        // Vary swap fee from 0% - 10%.
        swapFeePercentage = bound(swapFeePercentage, 0, maxSwapFeePercentage);

        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        // Add liquidity so we have something to remove.
        vm.prank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(
            address(liquidityPool),
            [maxAmount, maxAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        vm.startPrank(alice);
        // Test removeLiquiditySingleTokenExactOut.
        router.removeLiquiditySingleTokenExactOut(
            address(liquidityPool),
            bptAmountOut,
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
        uint256 amountOut = router.swapSingleTokenExactIn(
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

        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactNoSwapFee__Fuzz(uint256 exactAmountOut) public {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        exactAmountOut = bound(exactAmountOut, 1e18, maxAmount);

        // Add liquidity so we have something to remove.
        vm.prank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(
            address(liquidityPool),
            [maxAmount, maxAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        vm.startPrank(alice);
        // Test removeLiquiditySingleTokenExactOut.
        router.removeLiquiditySingleTokenExactOut(
            address(liquidityPool),
            bptAmountOut,
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
        router.swapSingleTokenExactIn(
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

        assertLiquidityOperationNoSwapFee();
    }

    function testRemoveLiquiditySingleTokenExactIn__Fuzz(uint256 exactBptAmountIn, uint256 swapFeePercentage) public {
        exactBptAmountIn = bound(exactBptAmountIn, 1e18, maxAmount / 2 - 1);
        // Vary swap fee from 0% - 10%.
        swapFeePercentage = bound(swapFeePercentage, 0, maxSwapFeePercentage);

        _setSwapFeePercentage(address(liquidityPool), swapFeePercentage);
        _setSwapFeePercentage(address(swapPool), swapFeePercentage);

        // Add liquidity so we have something to remove.
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(liquidityPool),
            [maxAmount, maxAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        vm.startPrank(alice);
        // Test removeLiquiditySingleTokenExactIn.
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
        uint256 amountOut = router.swapSingleTokenExactIn(
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

        assertLiquidityOperation(amountOut, swapFeePercentage, false);
    }

    function testRemoveLiquiditySingleTokenExactInNoSwapFee__Fuzz(uint256 exactBptAmountIn) public {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        exactBptAmountIn = bound(exactBptAmountIn, 1e18, maxAmount / 2 - 1);

        // Add liquidity so we have something to remove.
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(liquidityPool),
            [maxAmount, maxAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        vm.startPrank(alice);
        // Test removeLiquiditySingleTokenExactIn.
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
        router.swapSingleTokenExactIn(
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

        assertLiquidityOperationNoSwapFee();
    }

    /// Utils

    function assertLiquidityOperationNoSwapFee() internal {
        vault.manuallySetSwapFee(liquidityPool, 0);
        vault.manuallySetSwapFee(swapPool, 0);

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        uint256 aliceAmountOut = usdc.balanceOf(alice) - defaultBalance;
        uint256 bobAmountOut = usdc.balanceOf(bob) - defaultBalance;
        uint256 bobToAliceRatio = bobAmountOut.divDown(aliceAmountOut);

        assertApproxEqAbs(aliceAmountOut, bobAmountOut, roundingDelta, "Swap fee delta is too big");

        assertGe(bobToAliceRatio, 1e18 - roundingDelta, "Bob has less USDC compare to Alice");
        assertLe(bobToAliceRatio, 1e18 + roundingDelta, "Bob has too much USDC compare to Alice");

        // Alice and Bob have no BPT tokens.
        assertEq(PoolMock(swapPool).balanceOf(alice), 0, "Alice should have 0 BPT");
        assertEq(PoolMock(liquidityPool).balanceOf(alice), 0, "Alice should have 0 BPT");
        assertEq(PoolMock(swapPool).balanceOf(bob), 0, "Bob should have 0 BPT");
        assertEq(PoolMock(liquidityPool).balanceOf(bob), 0, "Bob should have 0 BPT");
    }

    function assertLiquidityOperation(uint256 amountOut, uint256 swapFeePercentage, bool addLiquidity) internal view {
        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        uint256 aliceAmountOut = usdc.balanceOf(alice) - defaultBalance;
        uint256 bobAmountOut = usdc.balanceOf(bob) - defaultBalance;
        uint256 bobToAliceRatio = bobAmountOut.divDown(aliceAmountOut);

        uint256 liquidityTaxPercentage = liquidityPercentageDelta.mulDown(swapFeePercentage);

        uint256 swapFee = amountOut.divUp(swapFeePercentage.complement()) - amountOut;

        assertApproxEqAbs(
            aliceAmountOut,
            bobAmountOut,
            swapFee.mulDown(swapFeePercentageDelta) + roundingDelta,
            "Swap fee delta is too big"
        );

        assertGe(
            bobToAliceRatio,
            1e18 - (addLiquidity ? liquidityTaxPercentage : 0) - roundingDelta,
            "Bob has too little USDC compare to Alice"
        );
        assertLe(
            bobToAliceRatio,
            1e18 + (addLiquidity ? 0 : liquidityTaxPercentage) + roundingDelta,
            "Bob has too much USDC compare to Alice"
        );
    }
}
