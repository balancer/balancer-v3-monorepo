// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AmountInAboveMax,
    AmountOutBelowMin,
    BptAmountInAboveMax,
    BptAmountOutBelowMin,
    PoolNotInitialized
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultErrors.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityTest is BaseVaultTest {
    using ArrayHelpers for *;

    struct Balances {
        uint256[] userTokens;
        uint256 userBpt;
        uint256[] poolTokens;
    }

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /// Add

    function addLiquidityUnbalanced() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        snapStart("addLiquidityUnbalanced");
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, defaultAmount, false, bytes(""));
        snapEnd();

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, defaultAmount * 2, "Invalid amount of BPT");
    }

    function testAddLiquidityUnbalanced() public {
        assertAddLiquidity(addLiquidityUnbalanced);
    }

    function addLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        bptAmountOut = defaultAmount;
        vm.prank(alice);
        snapStart("addLiquiditySingleTokenExactOut");
        amountsIn = router.addLiquiditySingleTokenExactOut(
            address(pool),
            dai,
            defaultAmount,
            bptAmountOut,
            false,
            bytes("")
        );
        snapEnd();

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, defaultAmount, "Invalid amount of BPT");
    }

    function testAddLiquiditySingleTokenExactOut() public {
        assertAddLiquidity(addLiquiditySingleTokenExactOut);
    }

    function addLiquidityCustom() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        vm.prank(alice);
        (amountsIn, bptAmountOut, ) = router.addLiquidityCustom(
            address(pool),
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, defaultAmount);
    }

    function testAddLiquidityCustom() public {
        assertAddLiquidity(addLiquidityCustom);
    }

    function testAddLiquidityNotInitialized() public {
        pool = createPool();

        vm.expectRevert(abi.encodeWithSelector(PoolNotInitialized.selector, address(pool)));
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );
    }

    function testAddLiquidityBptAmountOutBelowMin() public {
        vm.expectRevert(
            abi.encodeWithSelector(BptAmountOutBelowMin.selector, 2 * defaultAmount, 2 * defaultAmount + 1)
        );
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            2 * defaultAmount + 1,
            false,
            bytes("")
        );
    }

    function testAddLiquidityAmountInAboveMax() public {
        uint256 bptAmountOut = defaultAmount;
        vm.expectRevert(
            abi.encodeWithSelector(AmountInAboveMax.selector, address(dai), defaultAmount, defaultAmount - 1)
        );
        vm.prank(alice);
        router.addLiquiditySingleTokenExactOut(
            address(pool),
            dai,
            defaultAmount - 1,
            2 * bptAmountOut,
            false,
            bytes("")
        );
    }

    /// Remove

    function removeLiquidityProportional() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        bptAmountIn = defaultAmount * 2;

        snapStart("removeLiquidityProportional");
        amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            false,
            bytes("")
        );
        snapEnd();

        // amountsOut are correct
        assertEq(amountsOut[0], defaultAmount);
        assertEq(amountsOut[1], defaultAmount);
    }

    function testRemoveLiquidityProportional() public {
        assertRemoveLiquidity(removeLiquidityProportional);
    }

    function removeLiquiditySingleTokenExactIn() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        bptAmountIn = defaultAmount * 2;

        snapStart("removeLiquiditySingleTokenExactIn");
        amountsOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptAmountIn,
            dai,
            defaultAmount,
            false,
            bytes("")
        );
        snapEnd();

        // amountsOut are correct
        assertEq(amountsOut[0], defaultAmount);
        assertEq(amountsOut[1], 0);
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactIn);
    }

    function removeLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        amountsOut = [defaultAmount * 2, 0].toMemoryArray();

        snapStart("removeLiquiditySingleTokenExactOut");
        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            2 * defaultAmount,
            dai,
            uint256(2 * defaultAmount),
            false,
            bytes("")
        );
        snapEnd();
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactOut);
    }

    function removeLiquidityCustom() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        (bptAmountIn, amountsOut, ) = router.removeLiquidityCustom(
            address(pool),
            defaultAmount * 2,
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            false,
            bytes("")
        );

        // amountsOut are correct
        assertEq(amountsOut[0], defaultAmount);
        assertEq(amountsOut[1], defaultAmount);
    }

    function testRemoveLiquidityCustom() public {
        assertRemoveLiquidity(removeLiquidityCustom);
    }

    function testRemoveLiquidityNotInitialized() public {
        vm.startPrank(alice);

        pool = createPool();

        vm.expectRevert(abi.encodeWithSelector(PoolNotInitialized.selector, address(pool)));
        router.removeLiquidityProportional(
            address(pool),
            defaultAmount,
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testRemoveLiquidityAmountOutBelowMin() public {
        vm.expectRevert(
            abi.encodeWithSelector(AmountOutBelowMin.selector, address(dai), defaultAmount, defaultAmount + 1)
        );
        vm.startPrank(alice);
        router.removeLiquidityProportional(
            address(pool),
            2 * defaultAmount,
            [uint256(defaultAmount + 1), uint256(defaultAmount)].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testRemoveLiquidityBptInAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(BptAmountInAboveMax.selector, defaultAmount, defaultAmount / 2 - 1));
        vm.startPrank(alice);
        router.removeLiquiditySingleTokenExactOut(
            address(pool),
            defaultAmount / 2 - 1, // Exit with only one token, so the expected BPT amount in is 1/2 of the total.
            dai,
            uint256(defaultAmount),
            false,
            bytes("")
        );
    }

    /// Utils

    function getBalances(address user) internal view returns (Balances memory balances) {
        balances.userTokens = new uint256[](2);

        balances.userTokens[0] = dai.balanceOf(user);
        balances.userTokens[1] = usdc.balanceOf(user);
        balances.userBpt = PoolMock(pool).balanceOf(user);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        balances.poolTokens = poolBalances;
    }

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
        assertEq(balancesBefore.userBpt, bptAmountIn, "Remove - User BPT balance before");
        assertEq(balancesAfter.userBpt, 0, "Remove - User BPT balance after");
    }
}
