// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { MinTokenBalanceLib } from "@balancer-labs/v3-vault/contracts/lib/MinTokenBalanceLib.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPoolTest } from "./WeightedPool.t.sol";

contract WeightedPoolMinBalanceTest is WeightedPoolTest {
    using ArrayHelpers for *;

    // 1.2x the 1e6 minimum
    uint256 constant NEAR_MIN_BALANCE = 1.2e6;

    uint256 constant SWAP_TEST_BALANCE_HIGH = 3e6;
    uint256 constant SWAP_TEST_BALANCE_LOW = 1.2e6;
    uint256 constant TINY_TEST_SWAP_AMOUNT = 0.05e6;

    function setUp() public override {
        super.setUp();
    }

    function testBeforeSwapMinimumBalanceChecks() public {
        address smallPool = _createVeryLowLiquidityPool();
        uint256 bptToBurn = IERC20(smallPool).balanceOf(lp);

        uint256[] memory minAmountsOut = new uint256[](2);
        IERC20(smallPool).approve(address(router), MAX_UINT256);

        // Remove liquidity proportional from a tiny asymmetric pool, in order to go below the minimum in one token.
        vm.startPrank(lp);
        IERC20(smallPool).approve(address(router), MAX_UINT256);
        router.removeLiquidityProportional(smallPool, bptToBurn, minAmountsOut, false, bytes(""));

        // Exact values are really hard to calculate; just check that it's the correct error.
        vm.expectPartialRevert(MinTokenBalanceLib.TokenBalanceBelowMin.selector);
        router.swapSingleTokenExactIn(smallPool, poolTokens[0], poolTokens[1], 1, 0, MAX_UINT256, false, bytes(""));

        // Reverse the token order and ensure it still triggers.
        vm.expectPartialRevert(MinTokenBalanceLib.TokenBalanceBelowMin.selector);
        router.swapSingleTokenExactIn(smallPool, poolTokens[1], poolTokens[0], 1, 0, MAX_UINT256, false, bytes(""));

        vm.stopPrank();
    }

    function testAfterSwapMinimumBalanceCheckExactIn() public {
        address swapPool = _createSwapTestPool();

        vm.startPrank(lp);

        // Small test swap to show tokenIn is valid (not reverting on "before" check)
        router.swapSingleTokenExactIn(
            swapPool,
            poolTokens[0], // USDC in
            poolTokens[1], // DAI out
            TINY_TEST_SWAP_AMOUNT,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        // Main swap reverts on "after" check - would push tokenOut below minimum
        vm.expectPartialRevert(MinTokenBalanceLib.TokenBalanceBelowMin.selector);
        router.swapSingleTokenExactIn(
            swapPool,
            poolTokens[0], // USDC in
            poolTokens[1], // DAI out
            0.8e6,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        // Opposite direction swap succeeds - tokenIn still passes the "before" check
        // Since tokenIn is valid "before,"" the main swap's revert must be from the "after" check
        router.swapSingleTokenExactIn(
            swapPool,
            poolTokens[1], // DAI in
            poolTokens[0], // USDC out
            TINY_TEST_SWAP_AMOUNT,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        vm.stopPrank();
    }

    function testAfterSwapMinimumBalanceCheckExactOut() public {
        address swapPool = _createSwapTestPool();

        vm.startPrank(lp);

        // Small test swap to show tokenIn is valid (not reverting on "before" check)
        router.swapSingleTokenExactOut(
            swapPool,
            poolTokens[0], // USDC in
            poolTokens[1], // DAI out
            TINY_TEST_SWAP_AMOUNT, // small exact amountOut
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        // Main swap reverts on "after" check: would push tokenOut below minimum
        // DAI balance is ~1.15e6 after test swap; requesting 0.2e6 leaves ~0.95e6 < 1e6
        vm.expectPartialRevert(MinTokenBalanceLib.TokenBalanceBelowMin.selector);
        router.swapSingleTokenExactOut(
            swapPool,
            poolTokens[0], // USDC in
            poolTokens[1], // DAI out
            0.2e6, // exact amountOut that pushes it below min
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        // Opposite direction swap succeeds: tokenIn (now DAI) still passes the "before" check
        // Since tokenIn is valid "before," the main swap's revert must be from the "after" check
        router.swapSingleTokenExactOut(
            swapPool,
            poolTokens[1], // DAI in
            poolTokens[0], // USDC out
            TINY_TEST_SWAP_AMOUNT, // small exact amountOut
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        vm.stopPrank();
    }

    // Triggers computeInvariant check
    function testAddLiquidityUnbalancedBelowMin() public {
        address smallPool = _createVeryLowLiquidityPool();
        uint256 bptToBurn = IERC20(smallPool).balanceOf(lp);

        vm.startPrank(lp);
        IERC20(smallPool).approve(address(router), MAX_UINT256);

        // Drain the pool - asymmetric init means one token ends up below minimum
        uint256[] memory minAmountsOut = new uint256[](2);
        router.removeLiquidityProportional(smallPool, bptToBurn, minAmountsOut, false, bytes(""));

        // Add small amount to avoid hitting invariant ratio limit first
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 1e6;

        vm.expectPartialRevert(MinTokenBalanceLib.TokenBalanceBelowMin.selector);
        router.addLiquidityUnbalanced(smallPool, amountsIn, 0, false, bytes(""));

        vm.stopPrank();
    }

    // Triggers computeBalance check
    function testRemoveLiquiditySingleTokenExactInBelowMin() public {
        address smallPool = _createVeryLowLiquidityPool();
        uint256 lpBpt = IERC20(smallPool).balanceOf(lp);

        vm.startPrank(lp);
        IERC20(smallPool).approve(address(router), MAX_UINT256);

        // Tiny withdrawal to prove the pool is initially in a valid state
        router.removeLiquiditySingleTokenExactIn(smallPool, 10, poolTokens[1], 1, false, bytes(""));

        // Burn enough BPT to push single token below min via computeBalance
        // This is single-token removal, so all value comes from one token
        vm.expectPartialRevert(MinTokenBalanceLib.TokenBalanceBelowMin.selector);
        router.removeLiquiditySingleTokenExactIn(
            smallPool,
            lpBpt / 2, // Burn half of LP's BPT, taking it all from one token
            poolTokens[1], // The token with lower starting balance
            1,
            false,
            bytes("")
        );

        vm.stopPrank();
    }

    function testRemoveLiquiditySingleTokenExactOutBelowMin() public {
        address smallPool = _createVeryLowLiquidityPool();

        vm.startPrank(lp);
        IERC20(smallPool).approve(address(router), MAX_UINT256);

        // Tiny removal first to prove pool starts valid
        router.removeLiquiditySingleTokenExactOut(
            smallPool,
            MAX_UINT256, // maxBptAmountIn
            poolTokens[0], // tokenOut: high balance token has room
            10, // exactAmountOut
            false,
            bytes("")
        );

        // Request exact amount out that would push the low token below minimum
        // Token 1 starts at ~1e6 + 100, requesting more than 100 would push below 1e6
        vm.expectPartialRevert(MinTokenBalanceLib.TokenBalanceBelowMin.selector);
        router.removeLiquiditySingleTokenExactOut(
            smallPool,
            MAX_UINT256, // maxBptAmountIn
            poolTokens[1], // tokenOut: the low balance token
            150, // exactAmountOut: more than the 100 buffer
            false,
            bytes("")
        );

        vm.stopPrank();
    }

    function _createVeryLowLiquidityPool() internal returns (address) {
        string memory name = "Small Pool";
        string memory symbol = "SMOL";

        weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        PoolRoleAccounts memory roleAccounts;

        address newPool = WeightedPoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(poolTokens),
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            address(0),
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );

        vm.startPrank(lp);
        _initPool(newPool, [NEAR_MIN_BALANCE, MinTokenBalanceLib.ABSOLUTE_MIN_TOKEN_BALANCE + 100].toMemoryArray(), 0);
        vm.stopPrank();

        return newPool;
    }

    function _createSwapTestPool() internal returns (address) {
        string memory name = "Swap Test Pool";
        string memory symbol = "SWPTEST";

        weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        PoolRoleAccounts memory roleAccounts;

        address newPool = WeightedPoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(poolTokens),
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            address(0),
            false,
            false,
            ONE_BYTES32
        );

        vm.startPrank(lp);
        _initPool(newPool, [SWAP_TEST_BALANCE_HIGH, SWAP_TEST_BALANCE_LOW].toMemoryArray(), 0);
        vm.stopPrank();

        return newPool;
    }
}
