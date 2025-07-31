// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { AggregatorRouter } from "@balancer-labs/v3-vault/contracts/AggregatorRouter.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { AggregatorBatchRouter } from "@balancer-labs/v3-vault/contracts/AggregatorBatchRouter.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BalancerContext, BalancerSwapLib } from "../../contracts/BalancerSwapLib.sol";
import { BalancerSwapLibMock } from "../../contracts/test/BalancerSwapLibMock.sol";

contract BalancerSwapLibTest is BaseVaultTest {
    using BalancerSwapLib for *;

    BalancerContext internal context;
    BalancerSwapLibMock internal balancerSwapLibMock;

    AggregatorRouter aggregatorRouter;
    AggregatorBatchRouter aggregatorBatchRouter;

    address internal wrappedPool;

    uint256 constant MAX_DELTA = 10;

    uint256 daiIdx;
    uint256 usdcIdx;
    uint256 waDaiIdx;
    uint256 waUsdcIdx;

    uint256 usdcBalanceIdx = 0;
    uint256 daiBalanceIdx = 1;
    uint256 waUsdcBalanceIdx = 2;
    uint256 waDaiBalanceIdx = 3;

    function setUp() public override {
        BaseVaultTest.setUp();

        deal(address(usdc), address(this), defaultAccountBalance());
        deal(address(dai), address(this), defaultAccountBalance());

        context = BalancerSwapLib.createContext(
            address(new AggregatorRouter(vault, "AggregatorRouter")),
            address(new AggregatorBatchRouter(vault, "AggregatorBatchRouter"))
        );

        balancerSwapLibMock = new BalancerSwapLibMock(
            address(context.aggregatorRouter),
            address(context.aggregatorBatchRouter)
        );

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        setUpWrappedPool();
    }

    function createHook() internal override returns (address) {
        HookFlags memory hookFlags;
        hookFlags.shouldCallBeforeSwap = true;
        return _createHook(hookFlags);
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

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    function testSwapExactIn() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, pool);

        uint256 amountIn = poolBalancesBefore[usdcIdx] / 3;

        vm.startPrank(alice);
        uint256 amountOut = context.buildSwapExactIn(pool, usdc, dai, amountIn, 0, MAX_UINT256).execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, pool);

        assertEq(
            balancesAfter.userTokens[usdcBalanceIdx],
            balancesBefore.userTokens[usdcBalanceIdx] - amountIn,
            "Wrong USDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[daiBalanceIdx],
            balancesBefore.userTokens[daiBalanceIdx] + amountOut,
            "Wrong DAI balance (alice)"
        );

        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + amountIn, "Wrong USDC balance (pool)");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] - amountOut, "Wrong DAI balance (pool)");
    }

    function testSwapExactInWithWrapTokenIn() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, wrappedPool);

        uint256 underlyingAmountIn = poolBalancesBefore[usdcIdx] / 3;
        uint256 poolAmountIn = _vaultPreviewDeposit(waUSDC, underlyingAmountIn);

        vm.startPrank(alice);
        uint256 amountOut = context
            .buildSwapExactIn(wrappedPool, waUSDC, waDAI, underlyingAmountIn, 0, MAX_UINT256)
            .wrapTokenIn()
            .execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, wrappedPool);

        assertEq(
            balancesAfter.userTokens[usdcBalanceIdx],
            balancesBefore.userTokens[usdcBalanceIdx] - underlyingAmountIn,
            "Wrong USDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[waDaiBalanceIdx],
            balancesBefore.userTokens[waDaiBalanceIdx] + amountOut,
            "Wrong waDAI balance (alice)"
        );

        assertEq(
            poolBalancesAfter[waUsdcIdx],
            poolBalancesBefore[waUsdcIdx] + poolAmountIn,
            "Wrong waUSDC balance (pool)"
        );
        assertEq(poolBalancesAfter[waDaiIdx], poolBalancesBefore[waDaiIdx] - amountOut, "Wrong waDAI balance (pool)");
    }

    function testSwapExactInWithUnwrapTokenOut() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, wrappedPool);

        uint256 poolAmountIn = poolBalancesBefore[waUsdcIdx] / 3;

        uint256 snapshot = vm.snapshot();
        vm.startPrank(address(0), address(0));
        uint256 poolAmountOut = context
            .buildSwapExactIn(wrappedPool, waUSDC, waDAI, poolAmountIn, 0, MAX_UINT256)
            .query(alice);
        vm.stopPrank();
        vm.revertTo(snapshot);

        vm.startPrank(alice);
        uint256 amountOut = context
            .buildSwapExactIn(wrappedPool, waUSDC, waDAI, poolAmountIn, 0, MAX_UINT256)
            .unwrapTokenOut()
            .execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, wrappedPool);

        assertEq(
            balancesAfter.userTokens[waUsdcBalanceIdx],
            balancesBefore.userTokens[waUsdcBalanceIdx] - poolAmountIn,
            "Wrong USDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[daiBalanceIdx],
            balancesBefore.userTokens[daiBalanceIdx] + amountOut,
            "Wrong DAI balance (alice)"
        );

        assertEq(
            poolBalancesAfter[waUsdcIdx],
            poolBalancesBefore[waUsdcIdx] + poolAmountIn,
            "Wrong waUSDC balance (pool)"
        );
        assertEq(
            poolBalancesAfter[waDaiIdx],
            poolBalancesBefore[waDaiIdx] - poolAmountOut,
            "Wrong waDAI balance (pool)"
        );
    }

    function testSwapExactInWithWrapAndUnwrapTokens() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, wrappedPool);

        uint256 underlyingAmountIn = poolBalancesBefore[usdcIdx] / 3;
        uint256 poolAmountIn = _vaultPreviewDeposit(waUSDC, underlyingAmountIn);

        uint256 snapshot = vm.snapshot();
        vm.startPrank(address(0), address(0));
        uint256 poolAmountOut = context
            .buildSwapExactIn(wrappedPool, waUSDC, waDAI, underlyingAmountIn, 0, MAX_UINT256)
            .wrapTokenIn()
            .query(alice);
        vm.stopPrank();
        vm.revertTo(snapshot);

        vm.startPrank(alice);
        uint256 amountOut = context
            .buildSwapExactIn(wrappedPool, waUSDC, waDAI, underlyingAmountIn, 0, MAX_UINT256)
            .wrapTokenIn()
            .unwrapTokenOut()
            .execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, wrappedPool);

        assertEq(
            balancesAfter.userTokens[usdcBalanceIdx],
            balancesBefore.userTokens[usdcBalanceIdx] - underlyingAmountIn,
            "Wrong USDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[daiBalanceIdx],
            balancesBefore.userTokens[daiBalanceIdx] + amountOut,
            "Wrong DAI balance (alice)"
        );

        assertEq(
            poolBalancesAfter[waUsdcIdx],
            poolBalancesBefore[waUsdcIdx] + poolAmountIn,
            "Wrong waUSDC balance (pool)"
        );
        assertEq(
            poolBalancesAfter[waDaiIdx],
            poolBalancesBefore[waDaiIdx] - poolAmountOut,
            "Wrong waDAI balance (pool)"
        );
    }

    function testSwapExactInWithUserData() public {
        uint256 amountIn = 1;

        bytes memory userData = bytes("test");

        vm.startPrank(alice);
        context.buildSwapExactIn(pool, usdc, dai, amountIn, 0, MAX_UINT256).withUserData(userData).execute();
        vm.stopPrank();

        assertEq(PoolHooksMock(poolHooksContract).lastSwapUserData(), userData, "Wrong user data in last swap");
    }

    function testSwapExactInRevertIfDeadlineExceeded() public {
        vm.prank(alice);
        usdc.transfer(address(balancerSwapLibMock), 1);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        balancerSwapLibMock.swapExactIn(pool, usdc, dai, 1, 0, block.timestamp - 1, bytes("test"));
    }

    function testSwapExactInRevertIfAmountOutLessThanMin() public {
        vm.prank(alice);
        usdc.transfer(address(balancerSwapLibMock), 100);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, 1, 2));
        balancerSwapLibMock.swapExactIn(pool, usdc, dai, 1, 2, MAX_UINT256, bytes("test"));
        vm.stopPrank();
    }

    // /***************************************************************************
    //                                Swap Exact Out
    // ***************************************************************************/

    function testSwapExactOut() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, pool);

        uint256 amountOut = poolBalancesBefore[daiIdx] / 3;

        vm.startPrank(alice);
        uint256 amountIn = context
            .buildSwapExactOut(pool, usdc, dai, amountOut, usdc.balanceOf(alice), MAX_UINT256)
            .execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, pool);

        assertEq(
            balancesAfter.userTokens[usdcBalanceIdx],
            balancesBefore.userTokens[usdcBalanceIdx] - amountIn,
            "Wrong USDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[daiBalanceIdx],
            balancesBefore.userTokens[daiBalanceIdx] + amountOut,
            "Wrong DAI balance (alice)"
        );

        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + amountIn, "Wrong USDC balance (pool)");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] - amountOut, "Wrong DAI balance (pool)");
    }

    function testSwapExactOutWithWrapTokenIn() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, wrappedPool);

        uint256 wrappedAmountOut = poolBalancesBefore[waDaiIdx] / 3;

        uint256 snapshot = vm.snapshot();
        vm.startPrank(address(0), address(0));
        uint256 wrappedAmountIn = context
            .buildSwapExactOut(wrappedPool, waUSDC, waDAI, wrappedAmountOut, usdc.balanceOf(alice), MAX_UINT256)
            .query(alice);
        vm.stopPrank();
        vm.revertTo(snapshot);

        vm.startPrank(alice);
        uint256 underlyingAmountIn = context
            .buildSwapExactOut(wrappedPool, waUSDC, waDAI, wrappedAmountOut, usdc.balanceOf(alice), MAX_UINT256)
            .wrapTokenIn()
            .execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, wrappedPool);

        assertEq(
            balancesAfter.userTokens[usdcBalanceIdx],
            balancesBefore.userTokens[usdcBalanceIdx] - underlyingAmountIn,
            "Wrong USDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[waDaiBalanceIdx],
            balancesBefore.userTokens[waDaiBalanceIdx] + wrappedAmountOut,
            "Wrong waDAI balance (alice)"
        );

        assertEq(
            poolBalancesAfter[waUsdcIdx],
            poolBalancesBefore[waUsdcIdx] + wrappedAmountIn,
            "Wrong waUSDC balance (pool)"
        );
        assertEq(
            poolBalancesAfter[waDaiIdx],
            poolBalancesBefore[waDaiIdx] - wrappedAmountOut,
            "Wrong waDAI balance (pool)"
        );
    }

    function testSwapExactOutWithUnwrapTokenOut() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, wrappedPool);

        uint256 underlyingAmountOut = poolBalancesBefore[waDaiIdx] / 3;
        uint256 wrappedAmountOut = _vaultPreviewWithdraw(waDAI, underlyingAmountOut);

        vm.startPrank(alice);
        uint256 amountIn = context
            .buildSwapExactOut(wrappedPool, waUSDC, waDAI, underlyingAmountOut, usdc.balanceOf(alice), MAX_UINT256)
            .unwrapTokenOut()
            .execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, wrappedPool);

        assertEq(
            balancesAfter.userTokens[waUsdcBalanceIdx],
            balancesBefore.userTokens[waUsdcBalanceIdx] - amountIn,
            "Wrong waUSDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[daiBalanceIdx],
            balancesBefore.userTokens[daiBalanceIdx] + underlyingAmountOut,
            "Wrong DAI balance (alice)"
        );

        assertEq(poolBalancesAfter[waUsdcIdx], poolBalancesBefore[waUsdcIdx] + amountIn, "Wrong waUSDC balance (pool)");
        assertEq(
            poolBalancesAfter[waDaiIdx],
            poolBalancesBefore[waDaiIdx] - wrappedAmountOut,
            "Wrong waDAI balance (pool)"
        );
    }

    function testSwapExactOutWithWrapAndUnwrapTokens() public {
        (Balances memory balancesBefore, uint256[] memory poolBalancesBefore) = _getBalances(alice, wrappedPool);

        uint256 underlyingAmountOut = poolBalancesBefore[waDaiIdx] / 3;
        uint256 wrappedAmountOut = _vaultPreviewWithdraw(waDAI, underlyingAmountOut);

        uint256 snapshot = vm.snapshot();
        vm.startPrank(address(0), address(0));
        uint256 wrappedAmountIn = context
            .buildSwapExactOut(wrappedPool, waUSDC, waDAI, underlyingAmountOut, usdc.balanceOf(alice), MAX_UINT256)
            .unwrapTokenOut()
            .query(alice);
        vm.stopPrank();
        vm.revertTo(snapshot);

        vm.startPrank(alice);
        uint256 underlyingAmountIn = context
            .buildSwapExactOut(wrappedPool, waUSDC, waDAI, underlyingAmountOut, usdc.balanceOf(alice), MAX_UINT256)
            .wrapTokenIn()
            .unwrapTokenOut()
            .execute();
        vm.stopPrank();

        (Balances memory balancesAfter, uint256[] memory poolBalancesAfter) = _getBalances(alice, wrappedPool);

        assertEq(
            balancesAfter.userTokens[usdcBalanceIdx],
            balancesBefore.userTokens[usdcBalanceIdx] - underlyingAmountIn,
            "Wrong USDC balance (alice)"
        );
        assertEq(
            balancesAfter.userTokens[daiBalanceIdx],
            balancesBefore.userTokens[daiBalanceIdx] + underlyingAmountOut,
            "Wrong DAI balance (alice)"
        );

        assertEq(
            poolBalancesAfter[waUsdcIdx],
            poolBalancesBefore[waUsdcIdx] + wrappedAmountIn,
            "Wrong waUSDC balance (pool)"
        );
        assertEq(
            poolBalancesAfter[waDaiIdx],
            poolBalancesBefore[waDaiIdx] - wrappedAmountOut,
            "Wrong waDAI balance (pool)"
        );
    }

    function testSwapExactOutWithUserData() public {
        console.log(vault.getHooksConfig(pool).shouldCallBeforeSwap);
        uint256 amountOut = 1;

        bytes memory userData = bytes("test");
        vm.startPrank(alice);
        context
            .buildSwapExactOut(pool, usdc, dai, amountOut, usdc.balanceOf(alice), MAX_UINT256)
            .withUserData(userData)
            .execute();
        vm.stopPrank();
    }

    function testSwapExactOutRevertIfDeadlineExceeded() public {
        vm.prank(alice);
        usdc.transfer(address(balancerSwapLibMock), 1);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        balancerSwapLibMock.swapExactOut(pool, usdc, dai, 1, 1, block.timestamp - 1, bytes("test"));
    }

    function testSwapExactOutRevertIfAmountOutLessThanMin() public {
        vm.prank(alice);
        usdc.transfer(address(balancerSwapLibMock), 1);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, 2, 1));
        balancerSwapLibMock.swapExactOut(pool, usdc, dai, 2, 1, MAX_UINT256, bytes("test"));
        vm.stopPrank();
    }

    // /***************************************************************************
    //                                Other Functions
    // ***************************************************************************/

    function _getBalances(
        address user,
        address pool
    ) internal view returns (Balances memory balances, uint256[] memory poolBalancesBefore) {
        IERC20[] memory tokensToTrack = new IERC20[](4);
        tokensToTrack[usdcBalanceIdx] = usdc;
        tokensToTrack[daiBalanceIdx] = dai;
        tokensToTrack[waUsdcBalanceIdx] = waUSDC;
        tokensToTrack[waDaiBalanceIdx] = waDAI;

        return (getBalances(user, tokensToTrack), vault.getCurrentLiveBalances(pool));
    }
}
