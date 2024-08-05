// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityWithFeesTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    // `BaseVaultTest` defines the `protocolSwapFeePercentage`.
    uint64 poolCreatorFeePercentage = 50e16; // 50%
    uint256 aggregateSwapFeePercentage; // Computed in `setUp`.

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        setSwapFeePercentage(swapFeePercentage);
        aggregateSwapFeePercentage = feeController.computeAggregateFeePercentage(
            protocolSwapFeePercentage,
            poolCreatorFeePercentage
        );
        vault.manualSetAggregateSwapFeePercentage(pool, aggregateSwapFeePercentage);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testPrerequisites() public view {
        assertTrue(swapFeePercentage > 0);
        assertTrue(protocolSwapFeePercentage > 0);
        assertTrue(poolCreatorFeePercentage > 0);

        PoolConfig memory config = vault.getPoolConfig(pool);

        assertEq(config.staticSwapFeePercentage, swapFeePercentage);
        assertEq(
            config.aggregateSwapFeePercentage,
            feeController.computeAggregateFeePercentage(protocolSwapFeePercentage, poolCreatorFeePercentage)
        );
    }

    /// Add

    function addLiquidityUnbalanced()
        public
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, uint256[] memory aggregateSwapFees)
    {
        amountsIn = new uint256[](2);
        aggregateSwapFees = new uint256[](2);

        amountsIn[daiIdx] = defaultAmount;

        uint256 swapFeeAmount = defaultAmount / 200;
        aggregateSwapFees[daiIdx] = swapFeeAmount.mulUp(aggregateSwapFeePercentage);

        // expectedBptAmountOut = defaultAmount - defaultAmount * 1% / 2
        uint256 expectedBptAmountOut = (defaultAmount * 995) / 1000;

        vm.prank(alice);
        bptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, expectedBptAmountOut, false, bytes(""));

        // Should mint correct amount of BPT tokens.
        assertEq(bptAmountOut, expectedBptAmountOut, "Invalid amount of BPT");
    }

    function testAddLiquidityUnbalanced() public {
        assertAddLiquidity(addLiquidityUnbalanced);
    }

    function addLiquiditySingleTokenExactOut()
        public
        returns (uint256[] memory amountsIn, uint256 bptAmountOut, uint256[] memory aggregateSwapFees)
    {
        bptAmountOut = defaultAmount;

        aggregateSwapFees = new uint256[](2);
        uint256 swapFeeAmount = uint256((defaultAmount / 99) / 2) + 1;
        aggregateSwapFees[daiIdx] = swapFeeAmount.mulUp(aggregateSwapFeePercentage);

        vm.prank(alice);
        uint256 amountIn = router.addLiquiditySingleTokenExactOut(
            pool,
            dai,
            // amount + (amount / ( 100% - swapFee%)) / 2 + 1
            defaultAmount + (defaultAmount / 99) / 2 + 1,
            bptAmountOut,
            false,
            bytes("")
        );

        (amountsIn, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountIn);

        // Should mint correct amount of BPT tokens.
        assertEq(bptAmountOut, defaultAmount, "Invalid amount of BPT");
    }

    function testAddLiquiditySingleTokenExactOut() public {
        assertAddLiquidity(addLiquiditySingleTokenExactOut);
    }

    /// Remove

    function removeLiquiditySingleTokenExactIn()
        public
        returns (uint256[] memory amountsOut, uint256 bptAmountIn, uint256[] memory aggregateSwapFees)
    {
        bptAmountIn = defaultAmount * 2;

        aggregateSwapFees = new uint256[](2);
        uint256 swapFeeAmount = defaultAmount / 100;
        aggregateSwapFees[daiIdx] = swapFeeAmount.mulUp(aggregateSwapFeePercentage);

        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            pool,
            bptAmountIn,
            dai,
            defaultAmount,
            false,
            bytes("")
        );

        (amountsOut, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountOut);

        // Ensure `amountsOut` are correct.
        // 2 * amount - (amount * swapFee%).
        assertEq(amountsOut[daiIdx], defaultAmount * 2 - defaultAmount / 100, "Wrong AmountOut[DAI]");
        assertEq(amountsOut[usdcIdx], 0, "AmountOut[USDC] > 0");
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactIn);
    }

    function removeLiquiditySingleTokenExactOut()
        public
        returns (uint256[] memory amountsOut, uint256 bptAmountIn, uint256[] memory aggregateSwapFees)
    {
        amountsOut = new uint256[](2);
        aggregateSwapFees = new uint256[](2);

        amountsOut[daiIdx] = defaultAmount;
        uint256 swapFeeAmount = uint256((defaultAmount / 99) / 2) + 1;
        aggregateSwapFees[daiIdx] = swapFeeAmount.mulUp(aggregateSwapFeePercentage);

        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            pool,
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

    function assertAddLiquidity(function() returns (uint256[] memory, uint256, uint256[] memory) testFunc) internal {
        Balances memory balancesBefore = getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut, uint256[] memory aggregateSwapFees) = testFunc();

        Balances memory balancesAfter = getBalances(alice);

        // Tokens are transferred from the user to the vault.
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

        // Tokens are now in the vault / pool.
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] + amountsIn[0] - aggregateSwapFees[0],
            "Add - Pool balance: token 0"
        );

        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] + amountsIn[1] - aggregateSwapFees[1],
            "Add - Pool balance: token 1"
        );

        // Protocol + creator fees are charged.
        assertEq(
            aggregateSwapFees[daiIdx],
            vault.manualGetAggregateSwapFeeAmount(pool, dai),
            "Aggregate fee amount is wrong"
        );
        assertEq(
            aggregateSwapFees[usdcIdx],
            vault.manualGetAggregateSwapFeeAmount(pool, usdc),
            "Aggregate fee amount is wrong"
        );

        // User now has BPT.
        assertEq(balancesBefore.userBpt, 0, "Add - User BPT balance before");
        assertEq(balancesAfter.userBpt, bptAmountOut, "Add - User BPT balance after");
    }

    function assertRemoveLiquidity(function() returns (uint256[] memory, uint256, uint256[] memory) testFunc) internal {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            pool,
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        Balances memory balancesBefore = getBalances(alice);

        (uint256[] memory amountsOut, uint256 bptAmountIn, uint256[] memory aggregateSwapFees) = testFunc();

        vm.stopPrank();

        Balances memory balancesAfter = getBalances(alice);

        // Tokens are transferred back to user.
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

        // Tokens are no longer in the vault / pool.
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] - amountsOut[0] - aggregateSwapFees[0],
            "Remove - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] - amountsOut[1] - aggregateSwapFees[1],
            "Remove - Pool balance: token 1"
        );

        // User has burnt the correct amount of BPT.
        assertEq(balancesBefore.userBpt - balancesAfter.userBpt, bptAmountIn, "Wrong amount of BPT burned");
    }
}
