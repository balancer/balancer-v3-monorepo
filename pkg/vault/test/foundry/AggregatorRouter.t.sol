// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    PoolRoleAccounts,
    TokenConfig,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { RouterHooks } from "../../contracts/RouterHooks.sol";
import { AggregatorRouter } from "../../contracts/AggregatorRouter.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { SimpleEIP7702Contract } from "./utils/SimpleEIP7702Contract.sol";

contract AggregatorRouterTest is BaseVaultTest {
    using Address for address payable;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant MIN_SWAP_AMOUNT = 1e6;
    string constant version = "test";

    AggregatorRouter internal aggregatorRouter;
    SimpleEIP7702Contract internal delegatedContractCode;

    // Track the indices for the standard weth/usdc pool.
    uint256 internal wethIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        rateProvider = deployRateProviderMock();

        BaseVaultTest.setUp();
        aggregatorRouter = deployAggregatorRouter(IVault(address(vault)), weth, version);

        delegatedContractCode = new SimpleEIP7702Contract();
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, "pool");

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = rateProvider;
        rateProviders[1] = rateProvider;
        bool[] memory paysYieldFees = new bool[](2);
        paysYieldFees[0] = true;
        paysYieldFees[1] = true;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableAddLiquidityCustom = true;
        liquidityManagement.enableRemoveLiquidityCustom = true;
        liquidityManagement.enableDonation = true;

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        PoolFactoryMock(poolFactory).registerPool(
            newPool,
            vault.buildTokenConfig(
                [address(weth), address(usdc)].toMemoryArray().asIERC20(),
                rateProviders,
                paysYieldFees
            ),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        (wethIdx, usdcIdx) = getSortedIndexes(address(weth), address(usdc));

        poolArgs = abi.encode(vault, name, symbol);
    }

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    function testSwapExactIn__Fuzz(uint256 swapAmount) public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        swapAmount = bound(swapAmount, MIN_SWAP_AMOUNT, poolBalancesBefore[wethIdx]);

        vm.startPrank(alice);
        usdc.transfer(address(vault), swapAmount);

        uint256 outputTokenAmount = aggregatorRouter.swapSingleTokenExactIn(
            pool,
            usdc,
            weth,
            swapAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);

        assertEq(usdc.balanceOf(alice), defaultAccountBalance() - swapAmount, "Wrong USDC balance");
        assertEq(weth.balanceOf(alice), defaultAccountBalance() + outputTokenAmount, "Wrong WETH balance");
        assertEq(
            poolBalancesAfter[wethIdx],
            poolBalancesBefore[wethIdx] - outputTokenAmount,
            "Wrong WETH pool balance"
        );
        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + swapAmount, "Wrong USDC pool balance");
    }

    function testSwapExactInEthToUsdc() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 swapAmount = poolBalancesBefore[wethIdx] / 2;

        uint256 ethAliceBalanceBefore = alice.balance;

        vm.prank(alice);
        uint256 outputTokenAmount = aggregatorRouter.swapSingleTokenExactIn{ value: swapAmount }(
            pool,
            weth,
            usdc,
            swapAmount,
            0,
            MAX_UINT256,
            true,
            bytes("")
        );
        assertEq(alice.balance, ethAliceBalanceBefore - swapAmount, "Wrong ETH balance");

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);

        assertEq(usdc.balanceOf(alice), defaultAccountBalance() + outputTokenAmount, "Wrong USDC balance");
        assertEq(weth.balanceOf(alice), defaultAccountBalance(), "Wrong WETH balance");
        assertEq(poolBalancesAfter[wethIdx], poolBalancesBefore[wethIdx] + swapAmount, "Wrong WETH pool balance");
        assertEq(
            poolBalancesAfter[usdcIdx],
            poolBalancesBefore[usdcIdx] - outputTokenAmount,
            "Wrong USDC pool balance"
        );
    }

    function testSwapExactInUsdcToEth() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        uint256 swapAmount = poolBalancesBefore[usdcIdx] / 2;

        uint256 ethAliceBalanceBefore = alice.balance;

        vm.startPrank(alice);
        usdc.transfer(address(vault), swapAmount);

        uint256 outputTokenAmount = aggregatorRouter.swapSingleTokenExactIn(
            pool,
            usdc,
            weth,
            swapAmount,
            0,
            MAX_UINT256,
            true,
            bytes("")
        );
        vm.stopPrank();

        assertEq(alice.balance, ethAliceBalanceBefore + outputTokenAmount, "Wrong ETH balance");

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);

        assertEq(usdc.balanceOf(alice), defaultAccountBalance() - swapAmount, "Wrong USDC balance");
        assertEq(weth.balanceOf(alice), defaultAccountBalance(), "Wrong WETH balance");
        assertEq(
            poolBalancesAfter[wethIdx],
            poolBalancesBefore[wethIdx] - outputTokenAmount,
            "Wrong WETH pool balance"
        );
        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + swapAmount, "Wrong USDC pool balance");
    }

    function testQuerySwapExactIn() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        aggregatorRouter.querySwapSingleTokenExactIn(pool, usdc, weth, MIN_SWAP_AMOUNT, address(this), bytes(""));
    }

    function testSwapExactInMinAmountOut() public {
        vm.startPrank(alice);
        usdc.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT, DEFAULT_AMOUNT + 1));
        aggregatorRouter.swapSingleTokenExactIn(
            pool,
            usdc,
            weth,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT + 1,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testSwapExactInDeadline() public {
        vm.startPrank(alice);
        usdc.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        aggregatorRouter.swapSingleTokenExactIn(
            pool,
            usdc,
            weth,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            block.timestamp - 1,
            false,
            bytes("")
        );
    }

    function testSwapExactInWrongTransferAndNoBalanceInVault() public {
        // If the swap is ExactIn, the router assumes the sender sent exactAmountIn to the Vault. If the sender does not
        // send the correct amount, the swap will revert.

        uint256 exactAmountIn = poolInitAmount * 2;
        uint256 minAmountOut = poolInitAmount * 2;
        uint256 insufficientAmount = MIN_SWAP_AMOUNT;

        vm.startPrank(alice);
        weth.transfer(address(vault), insufficientAmount);

        // The operation is reverted because we’re trying to take more tokens out of the pool than it has in its balance.
        vm.expectRevert();
        aggregatorRouter.swapSingleTokenExactIn(
            pool,
            weth,
            usdc,
            exactAmountIn,
            minAmountOut,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapExactInWrongTransferAndBalanceInVault() public {
        // If the swap is ExactIn, the router assumes the sender sent exactAmountIn to the Vault. If the sender does not
        // send the correct amount, the swap will revert.

        uint256 exactAmountIn = DEFAULT_AMOUNT;
        uint256 partialTransfer = DEFAULT_AMOUNT / 2;

        vm.startPrank(alice);
        weth.transfer(address(vault), partialTransfer);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(weth)));
        aggregatorRouter.swapSingleTokenExactIn(pool, weth, usdc, exactAmountIn, 0, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testQuerySwapExactIn__Fuzz(uint256 swapAmountExactIn) public {
        swapAmountExactIn = bound(swapAmountExactIn, MIN_SWAP_AMOUNT, vault.getCurrentLiveBalances(pool)[wethIdx]);

        // First query the swap.
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 queryAmountOut = aggregatorRouter.querySwapSingleTokenExactIn(
            pool,
            weth,
            usdc,
            swapAmountExactIn,
            alice,
            bytes("")
        );
        // Restore the state before the query.
        vm.revertToState(snapshot);

        // Then execute the actual swap.
        vm.startPrank(alice);
        weth.transfer(address(vault), swapAmountExactIn);
        uint256 actualAmountOut = aggregatorRouter.swapSingleTokenExactIn(
            pool,
            weth,
            usdc,
            swapAmountExactIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        // The query and actual swap should return the same amount.
        assertEq(queryAmountOut, actualAmountOut, "Query amount differs from actual swap amount");
    }

    /***************************************************************************
                                   Swap Exact Out
    ***************************************************************************/

    function testSwapExactOut__Fuzz(uint256 swapAmountExactOut) public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);

        swapAmountExactOut = bound(swapAmountExactOut, MIN_SWAP_AMOUNT, poolBalancesBefore[wethIdx]);
        uint256 maxAmountIn = weth.balanceOf(alice);

        vm.startPrank(alice);
        weth.transfer(address(vault), maxAmountIn);

        uint256 swapAmountExactIn = aggregatorRouter.swapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            swapAmountExactOut,
            maxAmountIn,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        assertEq(weth.balanceOf(alice), defaultAccountBalance() - swapAmountExactIn, "Wrong WETH balance");
        assertEq(usdc.balanceOf(alice), defaultAccountBalance() + swapAmountExactOut, "Wrong USDC balance");
        assertEq(
            poolBalancesAfter[wethIdx],
            poolBalancesBefore[wethIdx] + swapAmountExactIn,
            "Wrong WETH pool balance"
        );
        assertEq(
            poolBalancesAfter[usdcIdx],
            poolBalancesBefore[usdcIdx] - swapAmountExactOut,
            "Wrong USDC pool balance"
        );
    }

    function testSwapExactOutEthToUsdc() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);

        uint256 ethAliceBalanceBefore = alice.balance;
        uint256 swapAmountExactOut = poolBalancesBefore[usdcIdx] / 2;
        uint256 maxAmountIn = ethAliceBalanceBefore;

        vm.prank(alice);
        uint256 swapAmountExactIn = aggregatorRouter.swapSingleTokenExactOut{ value: maxAmountIn }(
            pool,
            weth,
            usdc,
            swapAmountExactOut,
            maxAmountIn,
            MAX_UINT256,
            true,
            bytes("")
        );
        assertEq(alice.balance, ethAliceBalanceBefore - swapAmountExactIn, "Wrong ETH balance");

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        assertEq(weth.balanceOf(alice), defaultAccountBalance(), "Wrong WETH balance");
        assertEq(usdc.balanceOf(alice), defaultAccountBalance() + swapAmountExactOut, "Wrong USDC balance");
        assertEq(
            poolBalancesAfter[wethIdx],
            poolBalancesBefore[wethIdx] + swapAmountExactIn,
            "Wrong WETH pool balance"
        );
        assertEq(
            poolBalancesAfter[usdcIdx],
            poolBalancesBefore[usdcIdx] - swapAmountExactOut,
            "Wrong USDC pool balance"
        );
    }

    function testSwapExactOutUsdcToEth() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);

        uint256 swapAmountExactOut = poolBalancesBefore[wethIdx] / 2;
        uint256 maxAmountIn = usdc.balanceOf(alice);

        uint256 ethAliceBalanceBefore = alice.balance;
        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountIn);
        uint256 swapAmountExactIn = aggregatorRouter.swapSingleTokenExactOut(
            pool,
            usdc,
            weth,
            swapAmountExactOut,
            maxAmountIn,
            MAX_UINT256,
            true,
            bytes("")
        );
        vm.stopPrank();
        assertEq(alice.balance, ethAliceBalanceBefore + swapAmountExactOut, "Wrong ETH balance");

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        assertEq(weth.balanceOf(alice), defaultAccountBalance(), "Wrong WETH balance");
        assertEq(usdc.balanceOf(alice), defaultAccountBalance() - swapAmountExactIn, "Wrong USDC balance");
        assertEq(
            poolBalancesAfter[wethIdx],
            poolBalancesBefore[wethIdx] - swapAmountExactOut,
            "Wrong WETH pool balance"
        );
        assertEq(
            poolBalancesAfter[usdcIdx],
            poolBalancesBefore[usdcIdx] + swapAmountExactIn,
            "Wrong USDC pool balance"
        );
    }

    function testQuerySwapExactOut() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        aggregatorRouter.querySwapSingleTokenExactOut(pool, weth, usdc, MAX_UINT256, address(this), bytes(""));
    }

    function testSwapExactOutWithoutPayment() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(weth)));
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            MIN_SWAP_AMOUNT,
            MIN_SWAP_AMOUNT,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testSwapExactOutMaxAmountIn() public {
        vm.startPrank(alice);
        weth.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT + 1, DEFAULT_AMOUNT));
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            DEFAULT_AMOUNT + 1,
            DEFAULT_AMOUNT,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testSwapExactOutDeadline() public {
        vm.startPrank(alice);
        weth.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            block.timestamp - 1,
            false,
            bytes("")
        );
    }

    function testSwapExactOutWrongTransferAndNoBalanceInVault() public {
        // If the swap is ExactOut, the router assumes the sender sent maxAmountIn to the Vault. If the sender does not
        // send the correct amount, the swap will revert.

        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = poolInitAmount * 2;
        uint256 insufficientAmount = MIN_SWAP_AMOUNT;

        vm.startPrank(alice);
        weth.transfer(address(vault), insufficientAmount);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(weth)));
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            exactAmountOut,
            maxAmountIn,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapExactOutWrongTransferAndBalanceInVault() public {
        // If the swap is ExactOut, the router assumes the sender sent maxAmountIn to the Vault. If the sender does not
        // send the correct amount, the swap will revert.

        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = weth.balanceOf(alice);
        uint256 partialTransfer = maxAmountIn / 2;

        vm.startPrank(alice);
        weth.transfer(address(vault), partialTransfer);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(weth)));
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            exactAmountOut,
            maxAmountIn,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testQuerySwapExactOut__Fuzz(uint256 swapAmountExactOut) public {
        swapAmountExactOut = bound(swapAmountExactOut, MIN_SWAP_AMOUNT, vault.getCurrentLiveBalances(pool)[usdcIdx]);
        uint256 maxAmountIn = weth.balanceOf(alice);

        // First query the swap.
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 queryAmountIn = aggregatorRouter.querySwapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            swapAmountExactOut,
            alice,
            bytes("")
        );
        // Restore the state before the query.
        vm.revertToState(snapshot);

        // Then execute the actual swap.
        vm.startPrank(alice);
        weth.transfer(address(vault), maxAmountIn);
        uint256 actualAmountIn = aggregatorRouter.swapSingleTokenExactOut(
            pool,
            weth,
            usdc,
            swapAmountExactOut,
            maxAmountIn,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();

        // The query and actual swap should return the same amount.
        assertEq(queryAmountIn, actualAmountIn, "Query amount differs from actual swap amount");
    }

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    function testAddLiquidityProportional() public {
        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx];
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);
        weth.transfer(address(vault), maxAmountsIn[wethIdx]);

        uint256[] memory amountsIn = aggregatorRouter.addLiquidityProportional(
            pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );
        vm.stopPrank();

        assertGt(
            maxAmountsIn[wethIdx],
            amountsIn[wethIdx],
            "Max weth amount in should be greater than actual weth amount in"
        );
        assertGt(
            maxAmountsIn[usdcIdx],
            amountsIn[usdcIdx],
            "Max USDC amount in should be greater than actual USDC amount in"
        );

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), alice);
    }

    function testAddLiquidityProportionalWithEth() public {
        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 ethBalanceBefore = alice.balance;
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[wethIdx] = ethBalanceBefore;
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);

        uint256[] memory amountsIn = aggregatorRouter.addLiquidityProportional{ value: maxAmountsIn[wethIdx] }(
            pool,
            maxAmountsIn,
            exactBptAmountOut,
            true,
            bytes("")
        );
        vm.stopPrank();

        assertEq(alice.balance, ethBalanceBefore - amountsIn[wethIdx], "Wrong ETH balance");

        assertGt(
            maxAmountsIn[wethIdx],
            amountsIn[wethIdx],
            "Max weth amount in should be greater than actual weth amount in"
        );
        assertGt(
            maxAmountsIn[usdcIdx],
            amountsIn[usdcIdx],
            "Max USDC amount in should be greater than actual USDC amount in"
        );

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(
            balancesBefore,
            poolBalancesBefore,
            vaultBalancesDiff,
            int256(exactBptAmountOut),
            true,
            alice
        );
    }

    function testAddLiquidityProportionalRevertIfInsufficientPayment() public {
        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx];
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx] / 2);
        weth.transfer(address(vault), maxAmountsIn[wethIdx] / 2);

        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(usdc)));
        aggregatorRouter.addLiquidityProportional(pool, maxAmountsIn, exactBptAmountOut, false, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityUnbalanced() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx]);
        weth.transfer(address(vault), exactAmountsIn[wethIdx]);

        uint256 bptAmountOut = aggregatorRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, bytes(""));
        vm.stopPrank();

        assertGt(bptAmountOut, 0, "BPT amount out should be greater than zero for unbalanced liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(exactAmountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(exactAmountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(bptAmountOut), alice);
    }

    function testAddLiquidityUnbalancedWithEth() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 ethBalanceBefore = alice.balance;
        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[wethIdx] = ethBalanceBefore / 100;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx]);

        uint256 bptAmountOut = aggregatorRouter.addLiquidityUnbalanced{ value: exactAmountsIn[wethIdx] }(
            pool,
            exactAmountsIn,
            0,
            true,
            bytes("")
        );
        vm.stopPrank();

        assertEq(alice.balance, ethBalanceBefore - exactAmountsIn[wethIdx], "Wrong ETH balance");

        assertGt(bptAmountOut, 0, "BPT amount out should be greater than zero for unbalanced liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(exactAmountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(exactAmountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(bptAmountOut), true, alice);
    }

    function testAddLiquidityUnbalancedRevertIfInsufficientPayment() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx] / 2);
        weth.transfer(address(vault), exactAmountsIn[wethIdx] / 2);

        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(usdc)));
        aggregatorRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityProportionalWithERC7702() public {
        vm.signAndAttachDelegation(address(delegatedContractCode), aliceKey);

        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx];
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        SimpleEIP7702Contract simpleAliceContract = SimpleEIP7702Contract(alice);
        SimpleEIP7702Contract.Call[] memory calls = new SimpleEIP7702Contract.Call[](3);
        calls[0] = SimpleEIP7702Contract.Call({
            to: address(usdc),
            data: abi.encodeCall(IERC20.transfer, (address(vault), maxAmountsIn[usdcIdx])),
            value: 0
        });
        calls[1] = SimpleEIP7702Contract.Call({
            to: address(weth),
            data: abi.encodeCall(IERC20.transfer, (address(vault), maxAmountsIn[wethIdx])),
            value: 0
        });
        calls[2] = SimpleEIP7702Contract.Call({
            to: address(aggregatorRouter),
            data: abi.encodeCall(
                IRouter.addLiquidityProportional,
                (pool, maxAmountsIn, exactBptAmountOut, false, bytes(""))
            ),
            value: 0
        });

        bytes[] memory results = simpleAliceContract.execute(calls);
        uint256[] memory amountsIn = abi.decode(results[2], (uint256[]));

        assertGt(
            maxAmountsIn[wethIdx],
            amountsIn[wethIdx],
            "Max weth amount in should be greater than actual weth amount in"
        );
        assertGt(
            maxAmountsIn[usdcIdx],
            amountsIn[usdcIdx],
            "Max USDC amount in should be greater than actual USDC amount in"
        );

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), alice);
    }

    function testAddLiquiditySingleTokenExactOut() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;
        uint256 maxAmountIn = balancesBefore.aliceTokens[wethIdx];

        vm.startPrank(alice);
        weth.transfer(address(vault), maxAmountIn);

        uint256 amountIn = aggregatorRouter.addLiquiditySingleTokenExactOut(
            pool,
            weth,
            maxAmountIn,
            exactBptAmountOut,
            false,
            bytes("")
        );
        vm.stopPrank();

        assertGt(amountIn, 0, "Amount in should be greater than zero for single token exact out liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountIn);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), alice);
    }

    function testAddLiquiditySingleTokenExactOutWithEth() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 ethBalanceBefore = alice.balance;
        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;
        uint256 maxAmountIn = balancesBefore.aliceTokens[wethIdx];

        vm.startPrank(alice);

        uint256 amountIn = aggregatorRouter.addLiquiditySingleTokenExactOut{ value: maxAmountIn }(
            pool,
            weth,
            maxAmountIn,
            exactBptAmountOut,
            true,
            bytes("")
        );
        vm.stopPrank();
        assertEq(alice.balance, ethBalanceBefore - amountIn, "Wrong ETH balance");

        assertGt(amountIn, 0, "Amount in should be greater than zero for single token exact out liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountIn);
        _checkBalancesDiff(
            balancesBefore,
            poolBalancesBefore,
            vaultBalancesDiff,
            int256(exactBptAmountOut),
            true,
            alice
        );
    }

    function testDonate() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx] / 2;
        amountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 2;

        vm.startPrank(alice);
        weth.transfer(address(vault), amountsIn[wethIdx]);
        usdc.transfer(address(vault), amountsIn[usdcIdx]);

        aggregatorRouter.donate(pool, amountsIn, false, bytes(""));
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(0), alice);
    }

    function testDonateWithEth() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 ethBalanceBefore = alice.balance;
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx] / 2;
        amountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 2;

        vm.startPrank(alice);
        usdc.transfer(address(vault), amountsIn[usdcIdx]);

        aggregatorRouter.donate{ value: amountsIn[wethIdx] }(pool, amountsIn, true, bytes(""));
        vm.stopPrank();

        assertEq(alice.balance, ethBalanceBefore - amountsIn[wethIdx], "Wrong ETH balance");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(0), true, alice);
    }

    function testAddLiquidityCustom() public {
        uint256 minBptAmountOut = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx] / 2;
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 10;

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);
        weth.transfer(address(vault), maxAmountsIn[wethIdx]);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = aggregatorRouter.addLiquidityCustom(
            pool,
            maxAmountsIn,
            minBptAmountOut,
            false,
            bytes("")
        );
        vm.stopPrank();

        assertEq(maxAmountsIn[wethIdx], amountsIn[wethIdx], "Max weth amount in should match actual weth amount in");
        assertEq(maxAmountsIn[usdcIdx], amountsIn[usdcIdx], "Max USDC amount in should match actual USDC amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(bptAmountOut), alice);
    }

    function testAddLiquidityCustomWithEth() public {
        uint256 minBptAmountOut = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 ethBalanceBefore = alice.balance;
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[wethIdx] = ethBalanceBefore / 10;
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 10;

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = aggregatorRouter.addLiquidityCustom{
            value: maxAmountsIn[wethIdx]
        }(pool, maxAmountsIn, minBptAmountOut, true, bytes(""));
        vm.stopPrank();
        assertEq(alice.balance, ethBalanceBefore - amountsIn[wethIdx], "Wrong ETH balance");

        assertEq(maxAmountsIn[wethIdx], amountsIn[wethIdx], "Max weth amount in should match actual weth amount in");
        assertEq(maxAmountsIn[usdcIdx], amountsIn[usdcIdx], "Max USDC amount in should match actual USDC amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(bptAmountOut), true, alice);
    }

    /***************************************************************************
                                   Remove Liquidity
    ***************************************************************************/

    function testRemoveLiquidityProportional() public {
        uint256 bptAmountIn = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), bptAmountIn);

        uint256[] memory amountsOut = aggregatorRouter.removeLiquidityProportional(
            pool,
            bptAmountIn,
            new uint256[](2),
            false,
            bytes("")
        );
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), lp);
    }

    function testRemoveLiquidityProportionalWithEth() public {
        uint256 bptAmountIn = IERC20(pool).totalSupply() / 5;

        uint256 ethLpBalanceBefore = lp.balance;
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), bptAmountIn);

        uint256[] memory amountsOut = aggregatorRouter.removeLiquidityProportional(
            pool,
            bptAmountIn,
            new uint256[](2),
            true,
            bytes("")
        );
        vm.stopPrank();
        assertEq(lp.balance, ethLpBalanceBefore + amountsOut[wethIdx], "Wrong ETH balance");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), true, lp);
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        uint256 exactBptAmountIn = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), exactBptAmountIn);

        uint256 amountOut = aggregatorRouter.removeLiquiditySingleTokenExactIn(
            pool,
            exactBptAmountIn,
            weth,
            1,
            false,
            bytes("")
        );
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountOut);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(exactBptAmountIn), lp);
    }

    function testRemoveLiquiditySingleTokenExactInWithEth() public {
        uint256 exactBptAmountIn = IERC20(pool).totalSupply() / 5;

        uint256 ethLpBalanceBefore = lp.balance;
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), exactBptAmountIn);

        uint256 amountOut = aggregatorRouter.removeLiquiditySingleTokenExactIn(
            pool,
            exactBptAmountIn,
            weth,
            1,
            true,
            bytes("")
        );
        vm.stopPrank();

        assertEq(lp.balance, ethLpBalanceBefore + amountOut, "Wrong ETH balance");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountOut);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(exactBptAmountIn), true, lp);
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 maxBptAmountIn = IERC20(pool).totalSupply();

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), maxBptAmountIn);

        uint256 exactAmountOut = balancesBefore.vaultTokens[wethIdx] / 2;

        uint256 bptAmountIn = aggregatorRouter.removeLiquiditySingleTokenExactOut(
            pool,
            maxBptAmountIn,
            weth,
            exactAmountOut,
            false,
            bytes("")
        );
        vm.stopPrank();

        assertLe(bptAmountIn, maxBptAmountIn, "BPT amount in should be less than or equal to max BPT amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(exactAmountOut);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), lp);
    }

    function testRemoveLiquiditySingleTokenExactOutWithEth() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 ethLpBalanceBefore = lp.balance;
        uint256 maxBptAmountIn = IERC20(pool).totalSupply();

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), maxBptAmountIn);

        uint256 exactAmountOut = balancesBefore.vaultTokens[wethIdx] / 2;

        uint256 bptAmountIn = aggregatorRouter.removeLiquiditySingleTokenExactOut(
            pool,
            maxBptAmountIn,
            weth,
            exactAmountOut,
            true,
            bytes("")
        );
        vm.stopPrank();

        assertEq(lp.balance, ethLpBalanceBefore + exactAmountOut, "Wrong ETH balance");

        assertLe(bptAmountIn, maxBptAmountIn, "BPT amount in should be less than or equal to max BPT amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(exactAmountOut);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), true, lp);
    }

    function removeLiquidityCustom() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 maxBptAmountIn = IERC20(pool).totalSupply();
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[wethIdx] = balancesBefore.lpTokens[wethIdx];
        minAmountsOut[usdcIdx] = balancesBefore.lpTokens[usdcIdx];

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), maxBptAmountIn);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = aggregatorRouter.removeLiquidityCustom(
            pool,
            maxBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );
        vm.stopPrank();

        assertLe(bptAmountIn, maxBptAmountIn, "BPT amount in should be less than or equal to max BPT amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), lp);
    }

    function removeLiquidityCustomWithEth() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 ethBalanceBefore = lp.balance;
        uint256 maxBptAmountIn = IERC20(pool).totalSupply();
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[wethIdx] = ethBalanceBefore;
        minAmountsOut[usdcIdx] = balancesBefore.lpTokens[usdcIdx];

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), maxBptAmountIn);
        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = aggregatorRouter.removeLiquidityCustom(
            pool,
            maxBptAmountIn,
            minAmountsOut,
            true,
            bytes("")
        );
        vm.stopPrank();
        assertEq(
            lp.balance,
            alice.balance + amountsOut[wethIdx],
            "Wrong ETH balance after removing liquidity with ETH"
        );

        assertLe(bptAmountIn, maxBptAmountIn, "BPT amount in should be less than or equal to max BPT amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), lp);
    }

    function testRemoveLiquidityRecovery() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 exactBptAmountIn = IERC20(pool).balanceOf(lp);

        vm.startPrank(lp);
        vault.manualEnableRecoveryMode(pool);
        IERC20(pool).approve(address(aggregatorRouter), exactBptAmountIn);

        uint256[] memory amountsOut = aggregatorRouter.removeLiquidityRecovery(
            pool,
            exactBptAmountIn,
            new uint256[](2)
        );

        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(exactBptAmountIn), lp);
    }

    /***************************************************************************
                                Other Router Functions
    ***************************************************************************/

    function testRouterVersion() public view {
        assertEq(aggregatorRouter.version(), version, "Router version mismatch");
    }

    function _checkBalancesDiff(
        BaseVaultTest.Balances memory balancesBefore,
        uint256[] memory poolBalancesBefore,
        int256[] memory vaultBalancesDiff,
        int256 bptAmountDiff,
        address user
    ) public view {
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, bptAmountDiff, false, user);
    }

    function _checkBalancesDiff(
        BaseVaultTest.Balances memory balancesBefore,
        uint256[] memory poolBalancesBefore,
        int256[] memory vaultBalancesDiff,
        int256 bptAmountDiff,
        bool wethIsEth,
        address user
    ) public view {
        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

        if (user == alice) {
            assertEq(
                balancesAfter.aliceTokens[wethIdx],
                uint256(
                    int256(balancesBefore.aliceTokens[wethIdx]) - (wethIsEth ? int256(0) : vaultBalancesDiff[wethIdx])
                ),
                "Wrong WETH balance (alice)"
            );
            assertEq(
                balancesAfter.aliceTokens[usdcIdx],
                uint256(int256(balancesBefore.aliceTokens[usdcIdx]) - vaultBalancesDiff[usdcIdx]),
                "Wrong USDC balance (alice)"
            );
            assertEq(
                balancesAfter.aliceBpt,
                uint256(int256(balancesBefore.aliceBpt) + bptAmountDiff),
                "Wrong BPT balance (alice)"
            );
        } else if (user == lp) {
            assertEq(
                balancesAfter.lpTokens[wethIdx],
                uint256(
                    int256(balancesBefore.lpTokens[wethIdx]) - (wethIsEth ? int256(0) : vaultBalancesDiff[wethIdx])
                ),
                "Wrong WETH balance (lp)"
            );
            assertEq(
                balancesAfter.lpTokens[usdcIdx],
                uint256(int256(balancesBefore.lpTokens[usdcIdx]) - vaultBalancesDiff[usdcIdx]),
                "Wrong USDC balance (lp)"
            );
            assertEq(
                balancesAfter.lpBpt,
                uint256(int256(balancesBefore.lpBpt) + bptAmountDiff),
                "Wrong BPT balance (lp)"
            );
        } else {
            revert("Unknown user for balance check");
        }

        assertEq(
            balancesAfter.vaultTokens[wethIdx],
            uint256(int256(balancesBefore.vaultTokens[wethIdx]) + vaultBalancesDiff[wethIdx]),
            "Wrong WETH balance (vault)"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            uint256(int256(balancesBefore.vaultTokens[usdcIdx]) + vaultBalancesDiff[usdcIdx]),
            "Wrong USDC balance (vault)"
        );

        assertEq(
            poolBalancesAfter[wethIdx],
            uint256(int256(poolBalancesBefore[wethIdx]) + vaultBalancesDiff[wethIdx]),
            "Wrong WETH pool balance"
        );
        assertEq(
            poolBalancesAfter[usdcIdx],
            uint256(int256(poolBalancesBefore[usdcIdx]) + vaultBalancesDiff[usdcIdx]),
            "Wrong USDC pool balance"
        );
    }
}
