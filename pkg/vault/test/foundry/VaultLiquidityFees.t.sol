// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityWithFeesTest is BaseVaultTest {
    using ArrayHelpers for *;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        setSwapFeePercentage(swapFeePercentage);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    /// Add

    function addLiquidityUnbalanced() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        amountsIn = new uint256[](2);

        amountsIn[daiIdx] = defaultAmount;

        // expectedBptAmountOut = defaultAmount - defaultAmount * 1% / 2
        uint256 expectedBptAmountOut = (defaultAmount * 995) / 1000;

        vm.prank(alice);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, expectedBptAmountOut, false, bytes(""));

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, expectedBptAmountOut, "Invalid amount of BPT");
    }

    function testAddLiquidityUnbalanced() public {
        assertAddLiquidity(addLiquidityUnbalanced);
    }

    function addLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        bptAmountOut = defaultAmount;

        vm.prank(alice);
        uint256 amountIn = router.addLiquiditySingleTokenExactOut(
            address(pool),
            dai,
            // amount + (amount / ( 100% - swapFee%)) / 2 + 1
            defaultAmount + (defaultAmount / 99) / 2 + 1,
            bptAmountOut,
            false,
            bytes("")
        );

        (amountsIn, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountIn);

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, defaultAmount, "Invalid amount of BPT");
    }

    function testAddLiquiditySingleTokenExactOut() public {
        assertAddLiquidity(addLiquiditySingleTokenExactOut);
    }

    /// Remove

    function removeLiquiditySingleTokenExactIn() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        bptAmountIn = defaultAmount * 2;

        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptAmountIn,
            dai,
            defaultAmount,
            false,
            bytes("")
        );

        (amountsOut, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountOut);

        // amountsOut are correct
        // 2 * amount - (amount * swapFee%)
        assertEq(amountsOut[daiIdx], defaultAmount * 2 - defaultAmount / 100, "Wrong AmountOut[DAI]");
        assertEq(amountsOut[usdcIdx], 0, "AmountOut[USDC] > 0");
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactIn);
    }

    function removeLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        amountsOut = new uint256[](2);

        amountsOut[daiIdx] = defaultAmount;

        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            2 * defaultAmount,
            dai,
            uint256(defaultAmount),
            false,
            bytes("")
        );
        // amount + (amount / ( 100% - swapFee%)) / 2 + 1
        assertEq(bptAmountIn, defaultAmount + (defaultAmount / 99) / 2 + 1, "Wrong bptAmountIn");
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactOut);
    }

    /// Utils

    function assertAddLiquidity(function() returns (uint256[] memory, uint256) testFunc) internal {
        Balances memory balancesBefore = getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut) = testFunc();

        Balances memory balancesAfter = getBalances(alice);

        // Tokens are transferred from the user to the vault
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] - amountsIn[0],
            "Add - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] - amountsIn[1],
            "Add - User balance: token 1"
        );

        // Tokens are now in the vault / pool
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] + amountsIn[0],
            "Add - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] + amountsIn[1],
            "Add - Pool balance: token 1"
        );

        // User now has BPT
        assertEq(balancesBefore.userBpt, 0, "Add - User BPT balance before");
        assertEq(balancesAfter.userBpt, bptAmountOut, "Add - User BPT balance after");
    }

    function assertRemoveLiquidity(function() returns (uint256[] memory, uint256) testFunc) internal {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        Balances memory balancesBefore = getBalances(alice);

        (uint256[] memory amountsOut, uint256 bptAmountIn) = testFunc();

        vm.stopPrank();

        Balances memory balancesAfter = getBalances(alice);

        // Tokens are transferred back to user
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] + amountsOut[0],
            "Remove - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] + amountsOut[1],
            "Remove - User balance: token 1"
        );

        // Tokens are no longer in the vault / pool
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] - amountsOut[0],
            "Remove - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] - amountsOut[1],
            "Remove - Pool balance: token 1"
        );

        // User has burnt the correct amount of BPT
        assertEq(balancesBefore.userBpt - balancesAfter.userBpt, bptAmountIn, "Wrong amount of BPT burned");
    }
}
