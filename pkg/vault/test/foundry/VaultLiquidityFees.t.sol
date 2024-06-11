// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityWithFeesTest is BaseVaultTest {
    using ArrayHelpers for *;
    using PoolConfigLib for PoolConfig;

    uint64 poolCreatorFeePercentage = 5e17; // 50%

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        setSwapFeePercentage(swapFeePercentage);
        vault.manualSetAggregateSwapFeePercentage(
            pool,
            _getAggregateFeePercentage(protocolSwapFeePercentage, poolCreatorFeePercentage)
        );

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testPrerequisites() public {
        assertTrue(swapFeePercentage > 0);
        assertTrue(protocolSwapFeePercentage > 0);
        assertTrue(poolCreatorFeePercentage > 0);

        PoolConfig memory config = vault.getPoolConfig(address(pool));

        assertEq(config.getStaticSwapFeePercentage(), swapFeePercentage);
        assertEq(
            config.getAggregateSwapFeePercentage(),
            _getAggregateFeePercentage(protocolSwapFeePercentage, poolCreatorFeePercentage)
        );
    }

    /// Add

    function addLiquidityUnbalanced()
        public
        returns (
            uint256[] memory amountsIn,
            uint256 bptAmountOut,
            uint256[] memory protocolSwapFees,
            uint256[] memory poolCreatorFees
        )
    {
        amountsIn = new uint256[](2);
        protocolSwapFees = new uint256[](2);
        poolCreatorFees = new uint256[](2);

        amountsIn[daiIdx] = defaultAmount;

        uint256 swapFeeAmount = defaultAmount / 200;

        // protocol swap fee = (defaultAmount * 1% / 2 ) * 50%
        protocolSwapFees[daiIdx] = swapFeeAmount / 2;
        poolCreatorFees[daiIdx] = (swapFeeAmount - protocolSwapFees[daiIdx]) / 2;

        // expectedBptAmountOut = defaultAmount - defaultAmount * 1% / 2
        uint256 expectedBptAmountOut = (defaultAmount * 995) / 1000;

        vm.prank(alice);
        snapStart("routerAddLiquidityUnbalancedWithCreatorFee");
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, expectedBptAmountOut, false, bytes(""));
        snapEnd();
        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, expectedBptAmountOut, "Invalid amount of BPT");
    }

    function testAddLiquidityUnbalanced() public {
        assertAddLiquidity(addLiquidityUnbalanced);
    }

    function addLiquiditySingleTokenExactOut()
        public
        returns (
            uint256[] memory amountsIn,
            uint256 bptAmountOut,
            uint256[] memory protocolSwapFees,
            uint256[] memory poolCreatorFees
        )
    {
        bptAmountOut = defaultAmount;

        protocolSwapFees = new uint256[](2);
        poolCreatorFees = new uint256[](2);

        uint256 swapFeeAmount = uint256((defaultAmount / 99) / 2);

        // protocol swap fee = (defaultAmount / 99% / 2 ) * 50% + 1
        protocolSwapFees[daiIdx] = swapFeeAmount / 2 + 1; // mulUp
        poolCreatorFees[daiIdx] = (swapFeeAmount - protocolSwapFees[daiIdx]) / 2 + 1; // mulUp

        vm.prank(alice);
        snapStart("routerAddLiquiditySingleTokenExactOutWithCreatorFee");
        uint256 amountIn = router.addLiquiditySingleTokenExactOut(
            address(pool),
            dai,
            // amount + (amount / ( 100% - swapFee%)) / 2 + 1
            defaultAmount + (defaultAmount / 99) / 2 + 1,
            bptAmountOut,
            false,
            bytes("")
        );
        snapEnd();

        (amountsIn, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountIn);

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, defaultAmount, "Invalid amount of BPT");
    }

    function testAddLiquiditySingleTokenExactOut() public {
        assertAddLiquidity(addLiquiditySingleTokenExactOut);
    }

    /// Remove

    function removeLiquiditySingleTokenExactIn()
        public
        returns (
            uint256[] memory amountsOut,
            uint256 bptAmountIn,
            uint256[] memory protocolSwapFees,
            uint256[] memory poolCreatorFees
        )
    {
        bptAmountIn = defaultAmount * 2;

        protocolSwapFees = new uint256[](2);
        poolCreatorFees = new uint256[](2);

        uint256 swapFeeAmount = defaultAmount / 100;

        // protocol swap fee = 2 * (defaultAmount * 1% / 2 ) * 50%
        protocolSwapFees[daiIdx] = swapFeeAmount / 2;
        poolCreatorFees[daiIdx] = (swapFeeAmount - protocolSwapFees[daiIdx]) / 2;

        snapStart("routerRemoveLiquiditySingleTokenExactInWithCreatorFee");
        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptAmountIn,
            dai,
            defaultAmount,
            false,
            bytes("")
        );
        snapEnd();

        (amountsOut, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountOut);

        // amountsOut are correct
        // 2 * amount - (amount * swapFee%)
        assertEq(amountsOut[daiIdx], defaultAmount * 2 - defaultAmount / 100, "Wrong AmountOut[DAI]");
        assertEq(amountsOut[usdcIdx], 0, "AmountOut[USDC] > 0");
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactIn);
    }

    function removeLiquiditySingleTokenExactOut()
        public
        returns (
            uint256[] memory amountsOut,
            uint256 bptAmountIn,
            uint256[] memory protocolSwapFees,
            uint256[] memory poolCreatorFees
        )
    {
        amountsOut = new uint256[](2);
        protocolSwapFees = new uint256[](2);
        poolCreatorFees = new uint256[](2);

        amountsOut[daiIdx] = defaultAmount;

        uint256 swapFeeAmount = uint256((defaultAmount / 99) / 2);

        // protocol swap fee = (defaultAmount / 99% / 2 ) * 50% + 1
        protocolSwapFees[daiIdx] = swapFeeAmount / 2 + 1; // mulUp
        poolCreatorFees[daiIdx] = (swapFeeAmount - protocolSwapFees[daiIdx]) / 2 + 1; // mulUp

        snapStart("routerRemoveLiquiditySingleTokenExactOutWithCreatorFee");
        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            2 * defaultAmount,
            dai,
            uint256(defaultAmount),
            false,
            bytes("")
        );
        snapEnd();

        // amount + (amount / ( 100% - swapFee%)) / 2 + 1
        assertEq(bptAmountIn, defaultAmount + (defaultAmount / 99) / 2 + 1, "Wrong bptAmountIn");
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactOut);
    }

    /// Utils

    function assertAddLiquidity(
        function() returns (uint256[] memory, uint256, uint256[] memory, uint256[] memory) testFunc
    ) internal {
        Balances memory balancesBefore = getBalances(alice);

        (
            uint256[] memory amountsIn,
            uint256 bptAmountOut,
            uint256[] memory protocolSwapFees,
            uint256[] memory poolCreatorFees
        ) = testFunc();

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
            balancesBefore.poolTokens[0] + amountsIn[0] - protocolSwapFees[0] - poolCreatorFees[0],
            "Add - Pool balance: token 0"
        );

        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] + amountsIn[1] - protocolSwapFees[1] - poolCreatorFees[1],
            "Add - Pool balance: token 1"
        );

        // Protocol + creator fees are charged
        assertEq(
            protocolSwapFees[daiIdx] + poolCreatorFees[daiIdx],
            vault.manualGetAggregateSwapFeeAmount(pool, dai),
            "Aggregate fee amount is wrong"
        );
        assertEq(
            protocolSwapFees[usdcIdx] + poolCreatorFees[usdcIdx],
            vault.manualGetAggregateSwapFeeAmount(pool, usdc),
            "Aggregate fee amount is wrong"
        );

        // Pool creator fees are charged if protocol fees are charged.
        if (protocolSwapFees[0] > 0) {
            assertTrue(poolCreatorFees[0] > 0);
        }

        if (protocolSwapFees[1] > 0) {
            assertTrue(poolCreatorFees[1] > 0);
        }

        // User now has BPT
        assertEq(balancesBefore.userBpt, 0, "Add - User BPT balance before");
        assertEq(balancesAfter.userBpt, bptAmountOut, "Add - User BPT balance after");
    }

    function assertRemoveLiquidity(
        function() returns (uint256[] memory, uint256, uint256[] memory, uint256[] memory) testFunc
    ) internal {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        Balances memory balancesBefore = getBalances(alice);

        (
            uint256[] memory amountsOut,
            uint256 bptAmountIn,
            uint256[] memory protocolSwapFees,
            uint256[] memory poolCreatorFees
        ) = testFunc();

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
            balancesBefore.poolTokens[0] - amountsOut[0] - protocolSwapFees[0] - poolCreatorFees[0],
            "Remove - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] - amountsOut[1] - protocolSwapFees[1] - poolCreatorFees[1],
            "Remove - Pool balance: token 1"
        );

        // Pool creator fees are charged if protocol fees are charged.
        if (protocolSwapFees[0] > 0) {
            assertTrue(poolCreatorFees[0] > 0);
        }

        if (protocolSwapFees[1] > 0) {
            assertTrue(poolCreatorFees[1] > 0);
        }

        // User has burnt the correct amount of BPT
        assertEq(balancesBefore.userBpt - balancesAfter.userBpt, bptAmountIn, "Wrong amount of BPT burned");
    }
}
