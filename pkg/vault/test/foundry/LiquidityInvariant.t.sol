// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Liquidity operations that involve a single token should behave as a special case
 * of the unbalanced proportional operation, where the amount of one of the tokens is zero.
 * To ensure this, we analize the results of two different but equivalent operations: 
 * - addLiquidityUnbalanced vs addLiquiditySingleTokenExactOut
 * - removeLiquiditySingleTokenExactIn vs removeLiquiditySingleTokenExactOut
 * - removeLiquidityProportional vs removeLiquiditySingleTokenExactOut
 */
contract LiquidityInvariantTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    address internal unbalancedPool;
    address internal exactOutPool;

    uint256 internal maxAmount = 3e8 * 1e18 - 1;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;
    uint256 internal roundingDelta = 1e15;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        setProtocolSwapFeePercentage(uint64(_protocolFee()));
        _setSwapFeePercentage(unbalancedPool, _swapFee());
        _setSwapFeePercentage(exactOutPool, _swapFee());
    }

    function createPool() internal virtual override returns (address) {
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        unbalancedPool = _createPool(tokens, "unbalancedPool");
        exactOutPool = _createPool(tokens, "exactOutPool");

        // NOTE: stores address in `pool` (unused in this test)
        return address(0xdead);
    }

    function initPool() internal override {
        poolInitAmount = 1e9 * 1e18;

        vm.startPrank(lp);
        _initPool(unbalancedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(exactOutPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    /// Add

    function testAddLiquidityInvariant__Fuzz(uint256 daiAmountIn) public {
        daiAmountIn = bound(daiAmountIn, 1e18, maxAmount);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[daiIdx] = uint256(daiAmountIn);

        vm.startPrank(alice);
        uint256 bptUnbalancedAmountOut = router.addLiquidityUnbalanced({
            pool: address(unbalancedPool),
            exactAmountsIn: amountsIn,
            minBptAmountOut: 0,
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 daiExactAmountIn = router.addLiquiditySingleTokenExactOut({
            pool: address(exactOutPool),
            tokenIn: dai,
            maxAmountIn: dai.balanceOf(bob), // avoids revert when fee
            exactBptAmountOut: bptUnbalancedAmountOut,
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        assertEq(defaultBalance - dai.balanceOf(bob), daiExactAmountIn, "Bob DAI balance is not correct");
        assertApproxEqAbs(
            dai.balanceOf(alice),
            dai.balanceOf(bob),
            roundingDelta,
            "Bob and Alice DAI balances are not equal"
        );
        assertApproxEqAbs(
            usdc.balanceOf(alice),
            usdc.balanceOf(bob),
            roundingDelta,
            "Bob and Alice USDC balances are not equal"
        );
        assertApproxEqAbs(
            IERC20(unbalancedPool).balanceOf(alice),
            IERC20(exactOutPool).balanceOf(bob),
            roundingDelta,
            "Bob and Alice BPT balances are not equal"
        );
    }

    /// Remove

    // TODO: test is failing with `BptAmountInAboveMax` on bob's 2nd tx for the weighted pool 50-50 no-fee case
    function testRemoveLiquidityInvariant__Fuzz(uint256 bptAmountIn) public {
        uint256 bptTotalSupply = IERC20(unbalancedPool).totalSupply();
        bptAmountIn = bound(bptAmountIn, bptTotalSupply / 30, bptTotalSupply / 20);

        vm.startPrank(lp);
        IERC20(exactOutPool).transfer(alice, bptAmountIn);
        IERC20(unbalancedPool).transfer(bob, bptAmountIn);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 daiOutExactIn = router.removeLiquiditySingleTokenExactIn({
            pool: address(exactOutPool),
            exactBptAmountIn: bptAmountIn,
            tokenOut: dai,
            minAmountOut: 1, // NOTE: reverts with AllZeroInputs() if 0
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bptInExactOut = router.removeLiquiditySingleTokenExactOut({
            pool: address(unbalancedPool),
            maxBptAmountIn: bptAmountIn,
            tokenOut: dai,
            exactAmountOut: daiOutExactIn,
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        assertEq(dai.balanceOf(bob) - defaultBalance, daiOutExactIn, "Bob DAI balance is not correct");
        assertApproxEqAbs(
            dai.balanceOf(alice),
            dai.balanceOf(bob),
            roundingDelta,
            "Bob and Alice DAI balances are not equal"
        );
        assertApproxEqAbs(
            usdc.balanceOf(alice),
            usdc.balanceOf(bob),
            roundingDelta,
            "Bob and Alice USDC balances are not equal"
        );
        assertApproxEqAbs(
            IERC20(unbalancedPool).balanceOf(alice),
            IERC20(exactOutPool).balanceOf(bob),
            roundingDelta,
            "Bob and Alice BPT balances are not equal"
        );
    }

    // TODO: test is failing with `BptAmountInAboveMax` on bob's 2nd tx for the weighted pool 50-50 no-fee case
    function testRemoveLiquidityProportionalInvariant__Fuzz(uint256 bptAmountIn) public {
        uint256 bptTotalSupply = IERC20(unbalancedPool).totalSupply();
        bptAmountIn = bound(bptAmountIn, bptTotalSupply / 30, bptTotalSupply / 20);

        vm.startPrank(lp);
        IERC20(exactOutPool).transfer(alice, bptAmountIn);
        IERC20(unbalancedPool).transfer(bob, bptAmountIn);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256[] memory tokensOut = router.removeLiquidityProportional({
            pool: address(exactOutPool),
            exactBptAmountIn: bptAmountIn,
            minAmountsOut: [uint256(1), 1].toMemoryArray(), // NOTE: reverts with AllZeroInputs() if 0
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bptDaiOut = router.removeLiquiditySingleTokenExactOut({
            pool: address(unbalancedPool),
            maxBptAmountIn: bptAmountIn,
            tokenOut: dai,
            exactAmountOut: tokensOut[daiIdx],
            wethIsEth: false,
            userData: bytes("")
        });

        uint256 bptWethOut = router.removeLiquiditySingleTokenExactOut({
            pool: address(unbalancedPool),
            maxBptAmountIn: IERC20(unbalancedPool).balanceOf(bob),
            tokenOut: usdc,
            exactAmountOut: tokensOut[usdcIdx],
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        assertEq(dai.balanceOf(bob) - defaultBalance, tokensOut[daiIdx], "Bob DAI balance is not correct");
        assertEq(usdc.balanceOf(bob) - defaultBalance, tokensOut[usdcIdx], "Bob USDC balance is not correct");
        assertApproxEqAbs(
            dai.balanceOf(alice),
            dai.balanceOf(bob),
            roundingDelta,
            "Bob and Alice DAI balances are not equal"
        );
        assertApproxEqAbs(
            usdc.balanceOf(alice),
            usdc.balanceOf(bob),
            roundingDelta,
            "Bob and Alice USDC balances are not equal"
        );
        assertApproxEqAbs(
            IERC20(unbalancedPool).balanceOf(alice),
            IERC20(exactOutPool).balanceOf(bob),
            roundingDelta,
            "Bob and Alice BPT balances are not equal"
        );
    }

    function _swapFee() internal view virtual returns (uint256) {
        return 0;
    }

    function _protocolFee() internal view virtual returns (uint256) {
        return 0;
    }
}

// TODO: test is failing, making abstract to disable until expectations are set
abstract contract LiquidityInvariantWithFeeTest is LiquidityInvariantTest {
    function _swapFee() internal view override returns (uint256) {
        return 0.01e18;
    }
}

// NOTE: no use-case, making abstract to disable
abstract contract LiquidityInvariantWithProtocolFeeTest is LiquidityInvariantWithFeeTest {
    // NOTE: doesn't have any effect on alice and bob balances
    function _protocolFee() internal view override returns (uint256) {
        return 0.01e18;
    }
}
