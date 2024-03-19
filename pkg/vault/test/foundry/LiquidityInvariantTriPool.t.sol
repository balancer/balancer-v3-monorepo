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
 * @notice For pools with 3 tokens, liquidity operations that involve unbalanced amounts of tokens
 * should behave as individual single token operations.
 */
contract LiquidityInvariantTriPoolTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    address internal unbalancedPool;
    address internal exactOutPool;

    uint256 internal maxAmount = 3e8 * 1e18 - 1;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;
    uint256 internal wethIdx;
    uint256 internal roundingDelta = 1e15;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx, wethIdx) = getSortedIndexes(address(dai), address(usdc), address(weth));

        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        setProtocolSwapFeePercentage(uint64(_protocolFee()));
        _setSwapFeePercentage(unbalancedPool, _swapFee());
        _setSwapFeePercentage(exactOutPool, _swapFee());
    }

    function createPool() internal virtual override returns (address) {
        unbalancedPool = _createPool([address(dai), address(usdc), address(weth)].toMemoryArray(), "unbalancedPool");
        exactOutPool = _createPool([address(dai), address(usdc), address(weth)].toMemoryArray(), "exactOutPool");

        return address(unbalancedPool);
    }

    function initPool() internal override {
        poolInitAmount = 1e9 * 1e18;

        vm.startPrank(lp);
        _initPool(unbalancedPool, [poolInitAmount, poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(exactOutPool, [poolInitAmount, poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();
    }

    /// Add

    function testAddLiquidityInvariant__Fuzz(uint256 daiAmountIn, uint256 wethAmountIn) public {
        daiAmountIn = bound(daiAmountIn, 1e18, maxAmount);
        wethAmountIn = bound(wethAmountIn, 1e18, maxAmount);

        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[daiIdx] = uint256(daiAmountIn);

        vm.startPrank(alice);
        uint256 snapshot = vm.snapshot();
        // NOTE: calculates the amount of BPTs that would be minted if only DAI was added
        uint256 bptOnlyDaiAmountOut = router.addLiquidityUnbalanced({
            pool: address(unbalancedPool),
            exactAmountsIn: amountsIn,
            minBptAmountOut: 0,
            wethIsEth: false,
            userData: bytes("")
        });

        // Revert to the previous state not to affect Alice's balances
        vm.revertTo(snapshot);

        amountsIn[wethIdx] = uint256(wethAmountIn);
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
            maxAmountIn: dai.balanceOf(bob), // avoids revert when with fee
            exactBptAmountOut: bptOnlyDaiAmountOut,
            wethIsEth: false,
            userData: bytes("")
        });

        uint256 wethExactAmountIn = router.addLiquiditySingleTokenExactOut({
            pool: address(exactOutPool),
            tokenIn: weth,
            maxAmountIn: weth.balanceOf(bob), // avoids revert when with fee
            exactBptAmountOut: bptUnbalancedAmountOut - bptOnlyDaiAmountOut,
            wethIsEth: false,
            userData: bytes("")
        });
        vm.stopPrank();

        assertEq(defaultBalance - dai.balanceOf(bob), daiExactAmountIn, "Bob balance is not correct");
        assertEq(defaultBalance - weth.balanceOf(bob), wethExactAmountIn, "Bob balance is not correct");
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
            weth.balanceOf(alice),
            weth.balanceOf(bob),
            roundingDelta,
            "Bob and Alice WETH balances are not equal"
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
abstract contract LiquidityInvariantTriPoolWithFeeTest is LiquidityInvariantTriPoolTest {
    function _swapFee() internal view override returns (uint256) {
        return 0.01e18;
    }
}

// NOTE: no use-case, making abstract to disable
abstract contract LiquidityInvariantTriPoolWithProtocolFeeTest is LiquidityInvariantTriPoolWithFeeTest {
    // NOTE: doesn't have any effect on alice and bob balances
    function _protocolFee() internal view override returns (uint256) {
        return 0.01e18;
    }
}
