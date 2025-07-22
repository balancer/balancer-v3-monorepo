// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
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

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        rateProvider = deployRateProviderMock();

        BaseVaultTest.setUp();
        aggregatorRouter = deployAggregatorRouter(IVault(address(vault)), version);

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
                [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                rateProviders,
                paysYieldFees
            ),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        poolArgs = abi.encode(vault, name, symbol);
    }

    /***************************************************************************
                                   Swap Exact In
    ***************************************************************************/

    function testSwapExactIn__Fuzz(uint256 swapAmount) public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        swapAmount = bound(swapAmount, MIN_SWAP_AMOUNT, poolBalancesBefore[daiIdx]);

        vm.startPrank(alice);
        usdc.transfer(address(vault), swapAmount);

        uint256 outputTokenAmount = aggregatorRouter.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            swapAmount,
            0,
            MAX_UINT256,
            bytes("")
        );
        vm.stopPrank();

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);

        assertEq(usdc.balanceOf(alice), defaultAccountBalance() - swapAmount, "Wrong USDC balance");
        assertEq(dai.balanceOf(alice), defaultAccountBalance() + outputTokenAmount, "Wrong DAI balance");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] - outputTokenAmount, "Wrong DAI pool balance");
        assertEq(poolBalancesAfter[usdcIdx], poolBalancesBefore[usdcIdx] + swapAmount, "Wrong USDC pool balance");
    }

    function testQuerySwapExactIn() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        aggregatorRouter.querySwapSingleTokenExactIn(pool, usdc, dai, MIN_SWAP_AMOUNT, address(this), bytes(""));
    }

    function testSwapExactInMinAmountOut() public {
        vm.startPrank(alice);
        usdc.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT, DEFAULT_AMOUNT + 1));
        aggregatorRouter.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT + 1,
            MAX_UINT256,
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
            dai,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            block.timestamp - 1,
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
        dai.transfer(address(vault), insufficientAmount);

        // The operation is reverted because we’re trying to take more tokens out of the pool than it has in its balance.
        vm.expectRevert();
        aggregatorRouter.swapSingleTokenExactIn(pool, dai, usdc, exactAmountIn, minAmountOut, MAX_UINT256, bytes(""));
        vm.stopPrank();
    }

    function testSwapExactInWrongTransferAndBalanceInVault() public {
        // If the swap is ExactIn, the router assumes the sender sent exactAmountIn to the Vault. If the sender does not
        // send the correct amount, the swap will revert.

        uint256 exactAmountIn = DEFAULT_AMOUNT;
        uint256 partialTransfer = DEFAULT_AMOUNT / 2;

        vm.startPrank(alice);
        dai.transfer(address(vault), partialTransfer);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactIn(pool, dai, usdc, exactAmountIn, 0, MAX_UINT256, bytes(""));
        vm.stopPrank();
    }

    function testQuerySwapExactIn__Fuzz(uint256 swapAmountExactIn) public {
        swapAmountExactIn = bound(swapAmountExactIn, MIN_SWAP_AMOUNT, vault.getCurrentLiveBalances(pool)[daiIdx]);

        // First query the swap.
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 queryAmountOut = aggregatorRouter.querySwapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            swapAmountExactIn,
            alice,
            bytes("")
        );
        // Restore the state before the query.
        vm.revertToState(snapshot);

        // Then execute the actual swap.
        vm.startPrank(alice);
        dai.transfer(address(vault), swapAmountExactIn);
        uint256 actualAmountOut = aggregatorRouter.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            swapAmountExactIn,
            0,
            MAX_UINT256,
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

        swapAmountExactOut = bound(swapAmountExactOut, MIN_SWAP_AMOUNT, poolBalancesBefore[daiIdx]);
        uint256 maxAmountIn = dai.balanceOf(alice);

        vm.startPrank(alice);
        dai.transfer(address(vault), maxAmountIn);

        uint256 swapAmountExactIn = aggregatorRouter.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            swapAmountExactOut,
            maxAmountIn,
            MAX_UINT256,
            bytes("")
        );
        vm.stopPrank();

        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        assertEq(dai.balanceOf(alice), defaultAccountBalance() - swapAmountExactIn, "Wrong DAI balance");
        assertEq(usdc.balanceOf(alice), defaultAccountBalance() + swapAmountExactOut, "Wrong USDC balance");
        assertEq(poolBalancesAfter[daiIdx], poolBalancesBefore[daiIdx] + swapAmountExactIn, "Wrong DAI pool balance");
        assertEq(
            poolBalancesAfter[usdcIdx],
            poolBalancesBefore[usdcIdx] - swapAmountExactOut,
            "Wrong USDC pool balance"
        );
    }

    function testQuerySwapExactOut() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        aggregatorRouter.querySwapSingleTokenExactOut(pool, dai, usdc, MAX_UINT256, address(this), bytes(""));
    }

    function testSwapExactOutWithoutPayment() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            MIN_SWAP_AMOUNT,
            MIN_SWAP_AMOUNT,
            MAX_UINT256,
            bytes("")
        );
    }

    function testSwapExactOutMaxAmountIn() public {
        vm.startPrank(alice);
        dai.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT + 1, DEFAULT_AMOUNT));
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            DEFAULT_AMOUNT + 1,
            DEFAULT_AMOUNT,
            MAX_UINT256,
            bytes("")
        );
    }

    function testSwapExactOutDeadline() public {
        vm.startPrank(alice);
        dai.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(ISenderGuard.SwapDeadline.selector);
        aggregatorRouter.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            block.timestamp - 1,
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
        dai.transfer(address(vault), insufficientAmount);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactOut(pool, dai, usdc, exactAmountOut, maxAmountIn, MAX_UINT256, bytes(""));
        vm.stopPrank();
    }

    function testSwapExactOutWrongTransferAndBalanceInVault() public {
        // If the swap is ExactOut, the router assumes the sender sent maxAmountIn to the Vault. If the sender does not
        // send the correct amount, the swap will revert.

        uint256 exactAmountOut = MIN_SWAP_AMOUNT;
        uint256 maxAmountIn = dai.balanceOf(alice);
        uint256 partialTransfer = maxAmountIn / 2;

        vm.startPrank(alice);
        dai.transfer(address(vault), partialTransfer);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactOut(pool, dai, usdc, exactAmountOut, maxAmountIn, MAX_UINT256, bytes(""));
        vm.stopPrank();
    }

    function testQuerySwapExactOut__Fuzz(uint256 swapAmountExactOut) public {
        swapAmountExactOut = bound(swapAmountExactOut, MIN_SWAP_AMOUNT, vault.getCurrentLiveBalances(pool)[usdcIdx]);
        uint256 maxAmountIn = dai.balanceOf(alice);

        // First query the swap.
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 queryAmountIn = aggregatorRouter.querySwapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            swapAmountExactOut,
            alice,
            bytes("")
        );
        // Restore the state before the query.
        vm.revertToState(snapshot);

        // Then execute the actual swap.
        vm.startPrank(alice);
        dai.transfer(address(vault), maxAmountIn);
        uint256 actualAmountIn = aggregatorRouter.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            swapAmountExactOut,
            maxAmountIn,
            MAX_UINT256,
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
        maxAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx];
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);
        dai.transfer(address(vault), maxAmountsIn[daiIdx]);

        uint256[] memory amountsIn = aggregatorRouter.addLiquidityProportional(
            pool,
            maxAmountsIn,
            exactBptAmountOut,
            bytes("")
        );
        vm.stopPrank();

        assertGt(
            maxAmountsIn[daiIdx],
            amountsIn[daiIdx],
            "Max DAI amount in should be greater than actual DAI amount in"
        );
        assertGt(
            maxAmountsIn[usdcIdx],
            amountsIn[usdcIdx],
            "Max USDC amount in should be greater than actual USDC amount in"
        );

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = int256(amountsIn[daiIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), alice);
    }

    function testAddLiquidityProportionalRevertIfInsufficientPayment() public {
        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx];
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx] / 2);
        dai.transfer(address(vault), maxAmountsIn[daiIdx] / 2);

        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(usdc)));
        aggregatorRouter.addLiquidityProportional(pool, maxAmountsIn, exactBptAmountOut, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityUnbalanced() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx]);
        dai.transfer(address(vault), exactAmountsIn[daiIdx]);

        uint256 bptAmountOut = aggregatorRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, bytes(""));
        vm.stopPrank();

        assertGt(bptAmountOut, 0, "BPT amount out should be greater than zero for unbalanced liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = int256(exactAmountsIn[daiIdx]);
        vaultBalancesDiff[usdcIdx] = int256(exactAmountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(bptAmountOut), alice);
    }

    function testAddLiquidityUnbalancedRevertIfInsufficientPayment() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx] / 2);
        dai.transfer(address(vault), exactAmountsIn[daiIdx] / 2);

        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(usdc)));
        aggregatorRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityProportionalWithERC7702() public {
        vm.signAndAttachDelegation(address(delegatedContractCode), aliceKey);

        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx];
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        SimpleEIP7702Contract simpleAliceContract = SimpleEIP7702Contract(alice);
        SimpleEIP7702Contract.Call[] memory calls = new SimpleEIP7702Contract.Call[](3);
        calls[0] = SimpleEIP7702Contract.Call({
            to: address(usdc),
            data: abi.encodeCall(IERC20.transfer, (address(vault), maxAmountsIn[usdcIdx])),
            value: 0
        });
        calls[1] = SimpleEIP7702Contract.Call({
            to: address(dai),
            data: abi.encodeCall(IERC20.transfer, (address(vault), maxAmountsIn[daiIdx])),
            value: 0
        });
        calls[2] = SimpleEIP7702Contract.Call({
            to: address(aggregatorRouter),
            data: abi.encodeCall(
                IAggregatorRouter.addLiquidityProportional,
                (pool, maxAmountsIn, exactBptAmountOut, bytes(""))
            ),
            value: 0
        });

        bytes[] memory results = simpleAliceContract.execute(calls);
        uint256[] memory amountsIn = abi.decode(results[2], (uint256[]));

        assertGt(
            maxAmountsIn[daiIdx],
            amountsIn[daiIdx],
            "Max DAI amount in should be greater than actual DAI amount in"
        );
        assertGt(
            maxAmountsIn[usdcIdx],
            amountsIn[usdcIdx],
            "Max USDC amount in should be greater than actual USDC amount in"
        );

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = int256(amountsIn[daiIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), alice);
    }

    function testAddLiquiditySingleTokenExactOut() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;
        uint256 maxAmountIn = balancesBefore.aliceTokens[daiIdx];

        vm.startPrank(alice);
        dai.transfer(address(vault), maxAmountIn);

        uint256 amountIn = aggregatorRouter.addLiquiditySingleTokenExactOut(
            pool,
            dai,
            maxAmountIn,
            exactBptAmountOut,
            bytes("")
        );
        vm.stopPrank();

        assertGt(amountIn, 0, "Amount in should be greater than zero for single token exact out liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = int256(amountIn);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), alice);
    }

    function testDonate() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx] / 2;
        amountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 2;

        vm.startPrank(alice);
        dai.transfer(address(vault), amountsIn[daiIdx]);
        usdc.transfer(address(vault), amountsIn[usdcIdx]);

        aggregatorRouter.donate(pool, amountsIn, bytes(""));
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = int256(amountsIn[daiIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(0), alice);
    }

    function testAddLiquidityCustom() public {
        uint256 minBptAmountOut = IERC20(pool).totalSupply() / 5;

        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx] / 2;
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 10;

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);
        dai.transfer(address(vault), maxAmountsIn[daiIdx]);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = aggregatorRouter.addLiquidityCustom(
            pool,
            maxAmountsIn,
            minBptAmountOut,
            bytes("")
        );
        vm.stopPrank();

        assertEq(maxAmountsIn[daiIdx], amountsIn[daiIdx], "Max DAI amount in should match actual DAI amount in");
        assertEq(maxAmountsIn[usdcIdx], amountsIn[usdcIdx], "Max USDC amount in should match actual USDC amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = int256(amountsIn[daiIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, int256(bptAmountOut), alice);
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
            bytes("")
        );
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = -int256(amountsOut[daiIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), lp);
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
            dai,
            1,
            bytes("")
        );
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = -int256(amountOut);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(exactBptAmountIn), lp);
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 maxBptAmountIn = IERC20(pool).totalSupply();

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), maxBptAmountIn);

        uint256 exactAmountOut = balancesBefore.vaultTokens[daiIdx] / 2;

        uint256 bptAmountIn = aggregatorRouter.removeLiquiditySingleTokenExactOut(
            pool,
            maxBptAmountIn,
            dai,
            exactAmountOut,
            bytes("")
        );
        vm.stopPrank();

        assertLe(bptAmountIn, maxBptAmountIn, "BPT amount in should be less than or equal to max BPT amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = -int256(exactAmountOut);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(bptAmountIn), lp);
    }

    function removeLiquidityCustom() public {
        uint256[] memory poolBalancesBefore = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 maxBptAmountIn = IERC20(pool).totalSupply();
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[daiIdx] = balancesBefore.lpTokens[daiIdx];
        minAmountsOut[usdcIdx] = balancesBefore.lpTokens[usdcIdx];

        vm.startPrank(lp);
        IERC20(pool).approve(address(aggregatorRouter), maxBptAmountIn);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = aggregatorRouter.removeLiquidityCustom(
            pool,
            maxBptAmountIn,
            minAmountsOut,
            bytes("")
        );
        vm.stopPrank();

        assertLe(bptAmountIn, maxBptAmountIn, "BPT amount in should be less than or equal to max BPT amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[daiIdx] = -int256(amountsOut[daiIdx]);
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
        vaultBalancesDiff[daiIdx] = -int256(amountsOut[daiIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, poolBalancesBefore, vaultBalancesDiff, -int256(exactBptAmountIn), lp);
    }

    /***************************************************************************
                                Other Router Functions
    ***************************************************************************/

    function testRouterVersion() public view {
        assertEq(aggregatorRouter.version(), version, "Router version mismatch");
    }

    function testSendEth() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(IAggregatorRouter.CannotReceiveEth.selector);
        payable(aggregatorRouter).sendValue(address(this).balance);
    }

    function _checkBalancesDiff(
        BaseVaultTest.Balances memory balancesBefore,
        uint256[] memory poolBalancesBefore,
        int256[] memory vaultBalancesDiff,
        int256 bptAmountDiff,
        address user
    ) public view {
        uint256[] memory poolBalancesAfter = vault.getCurrentLiveBalances(pool);
        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

        if (user == alice) {
            assertEq(
                balancesAfter.aliceTokens[daiIdx],
                uint256(int256(balancesBefore.aliceTokens[daiIdx]) - vaultBalancesDiff[daiIdx]),
                "Wrong DAI balance (alice)"
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
                balancesAfter.lpTokens[daiIdx],
                uint256(int256(balancesBefore.lpTokens[daiIdx]) - vaultBalancesDiff[daiIdx]),
                "Wrong DAI balance (lp)"
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
            balancesAfter.vaultTokens[daiIdx],
            uint256(int256(balancesBefore.vaultTokens[daiIdx]) + vaultBalancesDiff[daiIdx]),
            "Wrong DAI balance (vault)"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            uint256(int256(balancesBefore.vaultTokens[usdcIdx]) + vaultBalancesDiff[usdcIdx]),
            "Wrong USDC balance (vault)"
        );

        assertEq(
            poolBalancesAfter[daiIdx],
            uint256(int256(poolBalancesBefore[daiIdx]) + vaultBalancesDiff[daiIdx]),
            "Wrong DAI pool balance"
        );
        assertEq(
            poolBalancesAfter[usdcIdx],
            uint256(int256(poolBalancesBefore[usdcIdx]) + vaultBalancesDiff[usdcIdx]),
            "Wrong USDC pool balance"
        );
    }
}
