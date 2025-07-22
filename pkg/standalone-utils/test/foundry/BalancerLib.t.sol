// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { AggregatorRouter } from "@balancer-labs/v3-vault/contracts/AggregatorRouter.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { AggregatorBatchRouter } from "@balancer-labs/v3-vault/contracts/AggregatorBatchRouter.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { Context, BalancerLib } from "../../contracts/BalancerLib.sol";

contract BalancerLibTest is BaseVaultTest {
    using BalancerLib for Context;

    Context internal context;

    AggregatorRouter aggregatorRouter;
    AggregatorBatchRouter aggregatorBatchRouter;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    address internal wrappedPool;
    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    uint256 constant MAX_DELTA = 10;

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

    function setUpWrappedPool() internal {
        // 1. TokenConfig for waDAI and waUSDC
        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);

        // 2. Create PoolMock
        string memory name = "waDAI/waUSDC Pool";
        string memory symbol = "WAWA";
        wrappedPool = address(new PoolMock(IVault(address(vault)), name, symbol));
        vm.label(wrappedPool, name);
        PoolFactoryMock(poolFactory).registerTestPool(wrappedPool, tokenConfig, poolHooksContract, lp);

        // 3. Initialize buffers for waDAI and waUSDC
        vm.startPrank(lp);
        bufferRouter.initializeBuffer(waDAI, poolInitAmount, 0, 0);
        bufferRouter.initializeBuffer(waUSDC, poolInitAmount, 0, 0);
        vm.stopPrank();

        // 4. Initialize the pool with liquidity
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[waDaiIdx] = poolInitAmount;
        amountsIn[waUsdcIdx] = poolInitAmount;
        vm.startPrank(lp);
        _initPool(wrappedPool, amountsIn, poolInitAmount);
        vm.stopPrank();
    }

    function testSwapExactIn() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 amountIn = poolBalancesBefore[usdcIdx] / 3;

        uint256 amountOut = context.swapSingleTokenExactIn(pool, usdc, dai, amountIn, 0, MAX_UINT256);

        _checkSwapResult(poolBalancesBefore, amountIn, amountOut);
    }

    function testSwapExactInWithUserData() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 underlyingAmountIn = poolBalancesBefore[usdcIdx] / 3;
        uint256 amountIn = _vaultPreviewDeposit(waUSDC, underlyingAmountIn);

        uint256 amountOut = context.swapSingleTokenExactIn(pool, usdc, dai, amountIn, 0, MAX_UINT256, bytes("test"));

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
            bytes("test")
        );

        _checkSwapResult(poolBalancesBefore, amountIn, amountOut);
    }

    function testSwapExactInWithWrappedTokens() public {
        setUpWrappedPool();

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(wrappedPool);

        uint256 underlyingAmountIn = poolBalancesBefore[waUsdcIdx] / 3;
        uint256 poolAmountIn = _vaultPreviewDeposit(waUSDC, underlyingAmountIn);

        uint256 underlyingAmountOut = context.swapSingleTokenExactIn(
            wrappedPool,
            usdc,
            dai,
            underlyingAmountIn,
            0,
            MAX_UINT256,
            waUSDC,
            waDAI
        );

        uint256 poolAmountOut = _vaultPreviewDeposit(waDAI, underlyingAmountOut);
        _checkWrappedSwapResult(
            poolBalancesBefore,
            underlyingAmountIn,
            underlyingAmountOut,
            poolAmountIn,
            poolAmountOut
        );
    }

    function testSwapExactInWithWrappedTokensWithUserData() public {
        setUpWrappedPool();

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(wrappedPool);

        uint256 underlyingAmountIn = poolBalancesBefore[waUsdcIdx] / 3;
        uint256 poolAmountIn = _vaultPreviewDeposit(waUSDC, underlyingAmountIn);

        uint256 underlyingAmountOut = context.swapSingleTokenExactIn(
            wrappedPool,
            usdc,
            dai,
            underlyingAmountIn,
            0,
            MAX_UINT256,
            waUSDC,
            waDAI,
            bytes("test")
        );

        uint256 poolAmountOut = _vaultPreviewDeposit(waDAI, underlyingAmountOut);
        _checkWrappedSwapResult(
            poolBalancesBefore,
            underlyingAmountIn,
            underlyingAmountOut,
            poolAmountIn,
            poolAmountOut
        );
    }

    function testSwapExactOutWithWrappedTokens() public {
        setUpWrappedPool();
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(wrappedPool);

        uint256 underlyingAmountOut = poolBalancesBefore[waDaiIdx] / 3;
        uint256 poolAmountOut = _vaultPreviewDeposit(waDAI, underlyingAmountOut);

        uint256 underlyingAmountIn = context.swapSingleTokenExactOut(
            wrappedPool,
            usdc,
            dai,
            underlyingAmountOut,
            usdc.balanceOf(address(this)),
            MAX_UINT256,
            waUSDC,
            waDAI
        );
        uint256 poolAmountIn = _vaultPreviewDeposit(waUSDC, underlyingAmountIn);

        _checkWrappedSwapResult(
            poolBalancesBefore,
            underlyingAmountIn,
            underlyingAmountOut,
            poolAmountIn,
            poolAmountOut
        );
    }

    function testSwapExactOutWithWrappedTokensWithUserData() public {
        setUpWrappedPool();
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(wrappedPool);

        uint256 underlyingAmountOut = poolBalancesBefore[waDaiIdx] / 3;
        uint256 poolAmountOut = _vaultPreviewDeposit(waDAI, underlyingAmountOut);

        uint256 underlyingAmountIn = context.swapSingleTokenExactOut(
            wrappedPool,
            usdc,
            dai,
            underlyingAmountOut,
            usdc.balanceOf(address(this)),
            MAX_UINT256,
            waUSDC,
            waDAI,
            bytes("test")
        );
        uint256 poolAmountIn = _vaultPreviewDeposit(waUSDC, underlyingAmountIn);

        _checkWrappedSwapResult(
            poolBalancesBefore,
            underlyingAmountIn,
            underlyingAmountOut,
            poolAmountIn,
            poolAmountOut
        );
    }

    function _checkSwapResult(uint256[] memory poolBalancesBefore, uint256 amountIn, uint256 amountOut) internal view {
        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);

        assertEq(usdc.balanceOf(address(this)), defaultAccountBalance() - amountIn, "Wrong USDC balance");
        assertEq(dai.balanceOf(address(this)), defaultAccountBalance() + amountOut, "Wrong DAI balance");

        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + amountIn, "Wrong USDC pool balance");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] - amountOut, "Wrong DAI pool balance");
    }

    function _checkWrappedSwapResult(
        uint256[] memory poolBalancesBefore,
        uint256 underlyingAmountIn,
        uint256 underlyingAmountOut,
        uint256 poolAmountIn,
        uint256 poolAmountOut
    ) internal view {
        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(wrappedPool);

        assertEq(usdc.balanceOf(address(this)), defaultAccountBalance() - underlyingAmountIn, "Wrong USDC balance");
        assertEq(dai.balanceOf(address(this)), defaultAccountBalance() + underlyingAmountOut, "Wrong DAI balance");
        assertEq(
            poolBalancesAfter[waUsdcIdx],
            poolBalancesBefore[waUsdcIdx] + poolAmountIn,
            "Wrong wUSDC pool balance"
        );
        assertApproxEqAbs(
            poolBalancesAfter[waDaiIdx],
            poolBalancesBefore[waDaiIdx] - poolAmountOut,
            MAX_DELTA,
            "Wrong wDAI pool balance"
        );
    }
}
