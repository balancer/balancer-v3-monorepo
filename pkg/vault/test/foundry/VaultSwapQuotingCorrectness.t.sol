// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Swap Quoting correctness tests for the Vault/Router integration.
 * @dev High-signal: uses Router quoting to compute the required/expected amounts, then checks that limit enforcement
 * reverts with the correct Vault error selector.
 */
contract VaultSwapQuotingCorrectnessTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testExactInMinAmountOutTooHigh__Fuzz(uint256 rawAmountIn) public {
        (IERC20[] memory poolTokens, , , ) = vault.getPoolTokenInfo(pool);
        IERC20 tokenIn = poolTokens[0];
        IERC20 tokenOut = poolTokens[1];

        // Keep within reasonable bounds to avoid unrelated limit/pathological cases.
        uint256 amountIn = bound(rawAmountIn, 1, poolInitAmount / 10);

        // Quote the expected amountOut (quoteAndRevert flow, no state changes).
        _prankStaticCall();
        uint256 quotedOut = router.querySwapSingleTokenExactInAndRevert(pool, tokenIn, tokenOut, amountIn, bytes(""));
        vm.assume(quotedOut > 0);
        vm.assume(quotedOut < type(uint256).max);

        // Too-high min should revert. For swaps, this is expressed as a SwapLimit error (not AmountOutBelowMin).
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, quotedOut, quotedOut + 1));
        router.swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            amountIn,
            quotedOut + 1,
            type(uint256).max,
            false,
            bytes("")
        );

        // Exact min should succeed.
        vm.prank(alice);
        uint256 out = router.swapSingleTokenExactIn(
            pool,
            tokenIn,
            tokenOut,
            amountIn,
            quotedOut,
            type(uint256).max,
            false,
            bytes("")
        );
        assertEq(out, quotedOut, "quote (andRevert) and execution must match exactly");
    }

    function testExactOutMaxAmountInTooLow__Fuzz(uint256 rawAmountOut) public {
        (IERC20[] memory poolTokens, , , ) = vault.getPoolTokenInfo(pool);
        IERC20 tokenIn = poolTokens[0];
        IERC20 tokenOut = poolTokens[1];

        uint256 amountOut = bound(rawAmountOut, 1, poolInitAmount / 10);

        _prankStaticCall();
        uint256 quotedIn = router.querySwapSingleTokenExactOut(pool, tokenIn, tokenOut, amountOut, alice, bytes(""));
        vm.assume(quotedIn > 0);

        // Too-low max should revert. For swaps, this is expressed as a SwapLimit error (not AmountInAboveMax).
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, quotedIn, quotedIn - 1));
        router.swapSingleTokenExactOut(
            pool,
            tokenIn,
            tokenOut,
            amountOut,
            quotedIn - 1,
            type(uint256).max,
            false,
            bytes("")
        );

        // Exact max should succeed.
        vm.prank(alice);
        uint256 inUsed = router.swapSingleTokenExactOut(
            pool,
            tokenIn,
            tokenOut,
            amountOut,
            quotedIn,
            type(uint256).max,
            false,
            bytes("")
        );
        assertEq(inUsed, quotedIn, "quote and execution must match exactly");
    }
}
