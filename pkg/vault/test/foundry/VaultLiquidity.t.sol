// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

import { VaultUtils } from "./utils/VaultUtils.sol";

contract VaultLiquidityTest is VaultUtils {
    using ArrayHelpers for *;

    struct Balances {
        uint256[] userTokens;
        uint256 userBpt;
        uint256[] poolTokens;
    }

    function setUp() public virtual override {
        VaultUtils.setUp();
    }

    /// Add

    function addLiquidityUnbalanced() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        vm.prank(alice);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, defaultAmount, false, bytes(""));

        // should mint correct amount of BPT tokens
        assertEq(bptAmountOut, defaultAmount * 2, "Invalid amount of BPT");
    }

    function testAddLiquidityUnbalanced() public {
        assertAddLiquidity(addLiquidityUnbalanced);
    }

    function addLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        bptAmountOut = defaultAmount;
        vm.prank(alice);
        amountsIn = router.addLiquiditySingleTokenExactOut(
            address(pool),
            0,
            defaultAmount,
            bptAmountOut,
            false,
            bytes("")
        );

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
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(pool)));
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );
    }

    /// Remove

    function removeLiquidityProportional() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        bptAmountIn = defaultAmount * 2;

        amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            false,
            bytes("")
        );

        // amountsOut are correct
        assertEq(amountsOut[0], defaultAmount);
        assertEq(amountsOut[1], defaultAmount);
    }

    function testRemoveLiquidityProportional() public {
        assertRemoveLiquidity(removeLiquidityProportional);
    }

    function removeLiquiditySingleTokenExactIn() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        bptAmountIn = defaultAmount * 2;

        amountsOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptAmountIn,
            0,
            defaultAmount,
            false,
            bytes("")
        );

        // amountsOut are correct
        assertEq(amountsOut[0], defaultAmount);
        assertEq(amountsOut[1], 0);
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactIn);
    }

    function removeLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        amountsOut = [defaultAmount * 2, 0].toMemoryArray();

        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            defaultAmount,
            0,
            uint256(2 * defaultAmount),
            false,
            bytes("")
        );
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

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        vm.expectRevert(abi.encodeWithSelector(IVault.PoolNotInitialized.selector, address(pool)));
        router.removeLiquidityProportional(
            address(pool),
            defaultAmount,
            [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray(),
            false,
            bytes("")
        );
    }

    // Utils

    function getBalances(address user) internal view returns (Balances memory balances) {
        balances.userTokens = new uint256[](2);

        balances.userTokens[0] = dai.balanceOf(user);
        balances.userTokens[1] = usdc.balanceOf(user);
        balances.userBpt = pool.balanceOf(user);

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
