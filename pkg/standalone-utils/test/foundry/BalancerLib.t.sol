// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { AggregatorRouter } from "@balancer-labs/v3-vault/contracts/AggregatorRouter.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { AggregatorBatchRouter } from "@balancer-labs/v3-vault/contracts/AggregatorBatchRouter.sol";

import { Context, BalancerLib } from "../../contracts/BalancerLib.sol";

contract BalancerLibTest is BaseVaultTest {
    using BalancerLib for Context;

    Context internal context;

    AggregatorRouter aggregatorRouter;
    AggregatorBatchRouter aggregatorBatchRouter;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        BaseVaultTest.setUp();

        deal(address(usdc), address(this), defaultAccountBalance());
        deal(address(dai), address(this), defaultAccountBalance());

        context = BalancerLib.createContext(
            address(new AggregatorRouter(vault, "AggregatorRouter")),
            address(new AggregatorBatchRouter(vault, "AggregatorBatchRouter"))
        );

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testSwapExactIn() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 amountIn = poolBalancesBefore[usdcIdx] / 3;

        uint256 amountOut = context.swapSingleTokenExactIn(pool, usdc, dai, amountIn, 0, MAX_UINT256);

        _checkSwapResult(poolBalancesBefore, amountIn, amountOut);
    }

    function testSwapExactInWithUserData() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 amountIn = poolBalancesBefore[usdcIdx] / 3;

        uint256 amountOut = context.swapSingleTokenExactIn(pool, usdc, dai, amountIn, 0, MAX_UINT256, bytes("0x1234"));

        _checkSwapResult(poolBalancesBefore, amountIn, amountOut);
    }

    function testSwapExactOut() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);

        uint256 amountOut = poolBalancesBefore[daiIdx] / 3;

        uint256 amountIn = context.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            amountOut,
            dai.balanceOf(alice),
            MAX_UINT256
        );

        _checkSwapResult(poolBalancesBefore, amountIn, amountOut);
    }

    function testSwapExactOutWithUserData() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);

        uint256 amountOut = poolBalancesBefore[daiIdx] / 3;

        uint256 amountIn = context.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            amountOut,
            dai.balanceOf(alice),
            MAX_UINT256,
            bytes("0x1234")
        );

        _checkSwapResult(poolBalancesBefore, amountIn, amountOut);
    }

    function _checkSwapResult(uint256[] memory poolBalancesBefore, uint256 amountIn, uint256 amountOut) internal view {
        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);

        assertEq(usdc.balanceOf(address(this)), defaultAccountBalance() - amountIn, "Wrong USDC balance");
        assertEq(dai.balanceOf(address(this)), defaultAccountBalance() + amountOut, "Wrong DAI balance");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] - amountOut, "Wrong DAI pool balance");
        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + amountIn, "Wrong USDC pool balance");
    }
}
