// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

contract UnbalancedLiquidityBounds is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /// @dev Proportional add is not affected by min / max invariant ratio.
    function testAddLiquidityProportionalInvariantRatio__Fuzz(
        uint256 bptAmountOut,
        uint256 initialBalance1,
        uint256 initialBalance2
    ) public {
        bptAmountOut = bound(bptAmountOut, FixedPoint.ONE, defaultAmount * 100);
        initialBalance1 = bound(initialBalance1, FixedPoint.ONE, defaultAmount * 100);
        initialBalance2 = bound(initialBalance2, FixedPoint.ONE, defaultAmount * 100);
        uint256[] memory initialBalances = [initialBalance1, initialBalance2].toMemoryArray();
        // This will unbalance the pool; adding liquidity will result in different proportions being added on each run.
        vault.manualSetPoolBalances(pool, initialBalances, initialBalances);

        uint256[] memory maxAmountsIn = [defaultBalance, defaultBalance].toMemoryArray();

        // Strict invariant ratio
        PoolMock(pool).setMinimumInvariantRatio(FixedPoint.ONE);
        PoolMock(pool).setMaximumInvariantRatio(FixedPoint.ONE);

        // Does not affect invariant ratio; does not revert.
        vm.prank(alice);
        router.addLiquidityProportional(pool, maxAmountsIn, bptAmountOut, false, bytes(""));
    }

    /// @dev Unbalanced add; new invariant exceeds the invariant ratio limits.
    function testAddLiquidityUnbalancedAboveMaxInvariantRatio() public {
        uint256 minBptAmountOut = defaultAmount;
        uint256 maxInvariantRatio = FixedPoint.ONE * 2;

        // Reasonable invariant ratio
        PoolMock(pool).setMaximumInvariantRatio(maxInvariantRatio);
        // Pool balances are [defaultAmount, defaultAmount]; invariant is `2 * defaultAmount`.
        // Adding `[8, 10] defaultAmount` will make the new invariant `20 * defaultAmount` (10x ratio).
        uint256[] memory amountsIn = [defaultAmount * 8, defaultAmount * 10].toMemoryArray();

        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioAboveMax.selector, 10 * FixedPoint.ONE, maxInvariantRatio)
        );
        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsIn, minBptAmountOut, false, bytes(""));
    }

    /// @dev Unbalanced add (single token exact out); new invariant exceeds the invariant ratio limits.
    function testAddLiquiditySingleTokenExactOutAboveMaxInvariantRatio() public {
        // Current BPT supply should be `defaultAmount * 2`. Adding 10 `defaultAmount` will bring the total supply to
        // `12 * defaultAmount`, so the invariant ratio (new / old) will be FP(6).
        uint256 bptAmountOut = defaultAmount * 10;
        uint256 maxInvariantRatio = FixedPoint.ONE * 2;
        uint256 maxAmountIn = defaultBalance;

        // Reasonable invariant ratio
        PoolMock(pool).setMaximumInvariantRatio(maxInvariantRatio);

        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioAboveMax.selector, 6 * FixedPoint.ONE, maxInvariantRatio)
        );
        vm.prank(alice);
        router.addLiquiditySingleTokenExactOut(pool, dai, maxAmountIn, bptAmountOut, false, bytes(""));
    }

    /// @dev Proportional remove is not affected by min / max invariant ratio.
    function testRemoveLiquidityProportionalInvariantRatio__Fuzz(uint256 bptAmountIn) public {
        bptAmountIn = bound(bptAmountIn, FixedPoint.ONE, IERC20(pool).balanceOf(lp));
        uint256[] memory minAmountsOut = [uint256(0), uint256(0)].toMemoryArray();

        // Strict invariant ratio
        PoolMock(pool).setMinimumInvariantRatio(FixedPoint.ONE);
        PoolMock(pool).setMaximumInvariantRatio(FixedPoint.ONE);

        vm.prank(lp);
        router.removeLiquidityProportional(pool, bptAmountIn, minAmountsOut, false, bytes(""));
    }

    /// @dev Recovery remove is not affected by min / max invariant ratio.
    function testRemoveLiquidityRecoveryInvariantRatio__Fuzz(uint256 bptAmountIn) public {
        bptAmountIn = bound(bptAmountIn, FixedPoint.ONE, IERC20(pool).balanceOf(lp));

        // Strict invariant ratio
        PoolMock(pool).setMinimumInvariantRatio(FixedPoint.ONE);
        PoolMock(pool).setMaximumInvariantRatio(FixedPoint.ONE);

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        vm.prank(lp);
        router.removeLiquidityRecovery(pool, bptAmountIn);
    }

    /// @dev Unbalanced remove (single token exact in); new invariant is smaller than allowed.
    function testRemoveLiquiditySingleTokenExactInBelowMinInvariantRatio() public {
        // BPT total supply is `2 * defaultAmount`, so removing `defaultAmount` will cut the invariant in half.
        uint256 bptAmountIn = defaultAmount;
        uint256 minAmountOut = 1;
        uint256 minInvariantRatio = FixedPoint.ONE.mulDown(0.8e18);

        PoolMock(pool).setMinimumInvariantRatio(minInvariantRatio);

        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioBelowMin.selector, FixedPoint.ONE / 2, minInvariantRatio)
        );
        vm.prank(lp);
        router.removeLiquiditySingleTokenExactIn(pool, bptAmountIn, dai, minAmountOut, false, bytes(""));
    }

    /// @dev Unbalanced remove (single token exact out); new invariant is smaller than allowed.
    function testRemoveLiquiditySingleTokenExactOutBelowMinInvariantRatio() public {
        // Token balances are [defaultAmount, defaultAmount], so removing `defaultAmount` from one of the tokens will
        // cut the sum of the balances (i.e. the invariant) by half.
        uint256 amountOut = defaultAmount;
        uint256 maxBptAmountIn = IERC20(pool).balanceOf(lp);
        uint256 minInvariantRatio = FixedPoint.ONE.mulDown(0.8e18);

        PoolMock(pool).setMinimumInvariantRatio(minInvariantRatio);

        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioBelowMin.selector, FixedPoint.ONE / 2, minInvariantRatio)
        );

        vm.prank(lp);
        router.removeLiquiditySingleTokenExactOut(pool, maxBptAmountIn, dai, amountOut, false, bytes(""));
    }
}
