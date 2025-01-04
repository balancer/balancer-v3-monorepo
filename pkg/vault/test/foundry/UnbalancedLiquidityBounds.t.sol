// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMockFlexibleInvariantRatio } from "../../contracts/test/PoolMockFlexibleInvariantRatio.sol";
import { BasePoolMath } from "../../contracts/BasePoolMath.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract UnbalancedLiquidityBounds is BaseVaultTest {
    using FixedPoint for uint256;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    // Create a pool with flexible invariant ratio bounds.
    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        newPool = address(deployPoolMockFlexibleInvariantRatio(IVault(address(vault)), "", ""));
        vm.label(newPool, label);

        PoolFactoryMock(poolFactory).registerTestPool(
            newPool,
            vault.buildTokenConfig(tokens.asIERC20()),
            poolHooksContract,
            lp
        );

        poolArgs = abi.encode(vault, "", "");
    }

    /// @dev Proportional add is not affected by min / max invariant ratio.
    function testAddLiquidityProportionalInvariantRatio__Fuzz(
        uint256 bptAmountOut,
        uint256 initialBalance1,
        uint256 initialBalance2
    ) public {
        bptAmountOut = bound(bptAmountOut, FixedPoint.ONE, DEFAULT_AMOUNT * 100);
        initialBalance1 = bound(initialBalance1, FixedPoint.ONE, DEFAULT_AMOUNT * 100);
        initialBalance2 = bound(initialBalance2, FixedPoint.ONE, DEFAULT_AMOUNT * 100);
        uint256[] memory initialBalances = [initialBalance1, initialBalance2].toMemoryArray();
        // This will unbalance the pool; adding liquidity will result in different proportions being added on each run.
        vault.manualSetPoolBalances(pool, initialBalances, initialBalances);

        uint256[] memory maxAmountsIn = [defaultAccountBalance(), defaultAccountBalance()].toMemoryArray();

        // Strict invariant ratio
        PoolMockFlexibleInvariantRatio(pool).setMinimumInvariantRatio(FixedPoint.ONE);
        PoolMockFlexibleInvariantRatio(pool).setMaximumInvariantRatio(FixedPoint.ONE);

        // Does not affect invariant ratio; does not revert.
        vm.prank(alice);
        router.addLiquidityProportional(pool, maxAmountsIn, bptAmountOut, false, bytes(""));
    }

    /// @dev Unbalanced add; new invariant exceeds the invariant ratio limits.
    function testAddLiquidityUnbalancedAboveMaxInvariantRatio() public {
        uint256 minBptAmountOut = DEFAULT_AMOUNT;
        uint256 maxInvariantRatio = FixedPoint.ONE * 2; // 200%

        // Reasonable invariant ratio.
        PoolMockFlexibleInvariantRatio(pool).setMaximumInvariantRatio(maxInvariantRatio);
        // Pool balances are [DEFAULT_AMOUNT, DEFAULT_AMOUNT]; invariant is `2 * DEFAULT_AMOUNT`.
        // Adding `[8, 10] DEFAULT_AMOUNT` will make the new invariant `20 * DEFAULT_AMOUNT` (10x ratio).
        uint256[] memory amountsIn = [DEFAULT_AMOUNT * 8, DEFAULT_AMOUNT * 10].toMemoryArray();

        // New invariant ratio has rounding errors favoring the vault.
        vm.expectRevert(
            abi.encodeWithSelector(
                BasePoolMath.InvariantRatioAboveMax.selector,
                10 * FixedPoint.ONE - 1,
                maxInvariantRatio
            )
        );
        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsIn, minBptAmountOut, false, bytes(""));
    }

    /// @dev Unbalanced add (single token exact out); new invariant exceeds the invariant ratio limits.
    function testAddLiquiditySingleTokenExactOutAboveMaxInvariantRatio() public {
        // Current BPT supply should be `DEFAULT_AMOUNT * 2`. Adding 10 `DEFAULT_AMOUNT` will bring the total supply to
        // `12 * DEFAULT_AMOUNT`, so the invariant ratio (new / old) will be FP(6).
        uint256 bptAmountOut = DEFAULT_AMOUNT * 10;
        uint256 maxInvariantRatio = FixedPoint.ONE * 2;
        uint256 maxAmountIn = defaultAccountBalance();

        // Reasonable invariant ratio
        PoolMockFlexibleInvariantRatio(pool).setMaximumInvariantRatio(maxInvariantRatio);

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
        PoolMockFlexibleInvariantRatio(pool).setMinimumInvariantRatio(FixedPoint.ONE);
        PoolMockFlexibleInvariantRatio(pool).setMaximumInvariantRatio(FixedPoint.ONE);

        vm.prank(lp);
        router.removeLiquidityProportional(pool, bptAmountIn, minAmountsOut, false, bytes(""));
    }

    /// @dev Recovery remove is not affected by min / max invariant ratio.
    function testRemoveLiquidityRecoveryInvariantRatio__Fuzz(uint256 bptAmountIn) public {
        bptAmountIn = bound(bptAmountIn, FixedPoint.ONE, IERC20(pool).balanceOf(lp));

        // Strict invariant ratio
        PoolMockFlexibleInvariantRatio(pool).setMinimumInvariantRatio(FixedPoint.ONE);
        PoolMockFlexibleInvariantRatio(pool).setMaximumInvariantRatio(FixedPoint.ONE);

        // Put pool in recovery mode.
        vault.manualEnableRecoveryMode(pool);

        vm.prank(lp);
        router.removeLiquidityRecovery(pool, bptAmountIn, new uint256[](2));
    }

    /// @dev Unbalanced remove (single token exact in); new invariant is smaller than allowed.
    function testRemoveLiquiditySingleTokenExactInBelowMinInvariantRatio() public {
        // BPT total supply is `2 * DEFAULT_AMOUNT`, so removing `DEFAULT_AMOUNT` will cut the invariant in half.
        uint256 bptAmountIn = DEFAULT_AMOUNT;
        uint256 minAmountOut = 1;
        uint256 minInvariantRatio = FixedPoint.ONE.mulDown(0.8e18);

        PoolMockFlexibleInvariantRatio(pool).setMinimumInvariantRatio(minInvariantRatio);

        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioBelowMin.selector, FixedPoint.ONE / 2, minInvariantRatio)
        );
        vm.prank(lp);
        router.removeLiquiditySingleTokenExactIn(pool, bptAmountIn, dai, minAmountOut, false, bytes(""));
    }

    /// @dev Unbalanced remove (single token exact out); new invariant is smaller than allowed.
    function testRemoveLiquiditySingleTokenExactOutBelowMinInvariantRatio() public {
        // Token balances are [DEFAULT_AMOUNT, DEFAULT_AMOUNT], so removing `DEFAULT_AMOUNT` from one of the tokens will
        // cut the sum of the balances (i.e. the invariant) by half.
        uint256 amountOut = DEFAULT_AMOUNT_ROUND_DOWN;
        uint256 maxBptAmountIn = IERC20(pool).balanceOf(lp);
        uint256 minInvariantRatio = FixedPoint.ONE.mulDown(0.8e18);

        PoolMockFlexibleInvariantRatio(pool).setMinimumInvariantRatio(minInvariantRatio);

        vm.expectRevert(
            abi.encodeWithSelector(BasePoolMath.InvariantRatioBelowMin.selector, FixedPoint.ONE / 2, minInvariantRatio)
        );

        vm.prank(lp);
        router.removeLiquiditySingleTokenExactOut(pool, maxBptAmountIn, dai, amountOut, false, bytes(""));
    }
}
