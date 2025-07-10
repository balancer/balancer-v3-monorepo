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
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseRouter } from "../../contracts/BaseRouter.sol";
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

        PoolFactoryMock(poolFactory).registerTestPool(
            newPool,
            vault.buildTokenConfig(
                [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                rateProviders,
                paysYieldFees
            ),
            poolHooksContract,
            lp
        );
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        poolArgs = abi.encode(vault, name, symbol);
    }

    /************************************
                Swap - EXACT IN
    ************************************/

    function testSwapExactIn__Fuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, MIN_SWAP_AMOUNT, vault.getPoolData(address(pool)).balancesLiveScaled18[daiIdx]);

        vm.startPrank(alice);
        usdc.transfer(address(vault), swapAmount);

        uint256 outputTokenAmount = aggregatorRouter.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            swapAmount,
            0,
            MAX_UINT256,
            bytes("")
        );
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), defaultAccountBalance() - swapAmount, "Wrong USDC balance");
        assertEq(dai.balanceOf(alice), defaultAccountBalance() + outputTokenAmount, "Wrong DAI balance");
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
            address(pool),
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
            address(pool),
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
        vm.expectRevert();
        aggregatorRouter.swapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            exactAmountIn,
            minAmountOut,
            MAX_UINT256,
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
        dai.transfer(address(vault), partialTransfer);
        vm.expectRevert(abi.encodeWithSelector(BaseRouter.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactIn(address(pool), dai, usdc, exactAmountIn, 0, MAX_UINT256, bytes(""));
        vm.stopPrank();
    }

    function testQuerySwapExactIn__Fuzz(uint256 swapAmountExactIn) public {
        swapAmountExactIn = bound(
            swapAmountExactIn,
            MIN_SWAP_AMOUNT,
            vault.getPoolData(address(pool)).balancesLiveScaled18[daiIdx]
        );

        // First query the swap.
        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 queryAmountOut = aggregatorRouter.querySwapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            swapAmountExactIn,
            alice,
            bytes("")
        );
        // Restore the state before the query.
        vm.revertTo(snapshot);

        // Then execute the actual swap.
        vm.startPrank(alice);
        dai.transfer(address(vault), swapAmountExactIn);
        uint256 actualAmountOut = aggregatorRouter.swapSingleTokenExactIn(
            address(pool),
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

    /************************************
                Swap - EXACT OUT
    ************************************/

    function testSwapExactOut__Fuzz(uint256 swapAmountExactOut) public {
        swapAmountExactOut = bound(
            swapAmountExactOut,
            MIN_SWAP_AMOUNT,
            vault.getPoolData(address(pool)).balancesLiveScaled18[daiIdx]
        );
        uint256 maxAmountIn = dai.balanceOf(alice);

        vm.startPrank(alice);
        dai.transfer(address(vault), maxAmountIn);

        uint256 swapAmountExactIn = aggregatorRouter.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            swapAmountExactOut,
            maxAmountIn,
            MAX_UINT256,
            bytes("")
        );
        vm.stopPrank();

        assertEq(dai.balanceOf(alice), defaultAccountBalance() - swapAmountExactIn, "Wrong DAI balance");
        assertEq(usdc.balanceOf(alice), defaultAccountBalance() + swapAmountExactOut, "Wrong USDC balance");
    }

    function testQuerySwapExactOut() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        aggregatorRouter.querySwapSingleTokenExactOut(pool, dai, usdc, MAX_UINT256, address(this), bytes(""));
    }

    function testSwapExactOutWithoutPayment() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BaseRouter.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactOut(
            address(pool),
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
            address(pool),
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
            address(pool),
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
        vm.expectRevert(abi.encodeWithSelector(BaseRouter.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            exactAmountOut,
            maxAmountIn,
            MAX_UINT256,
            bytes("")
        );
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
        vm.expectRevert(abi.encodeWithSelector(BaseRouter.InsufficientPayment.selector, address(dai)));
        aggregatorRouter.swapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            exactAmountOut,
            maxAmountIn,
            MAX_UINT256,
            bytes("")
        );
        vm.stopPrank();
    }

    function testQuerySwapExactOut__Fuzz(uint256 swapAmountExactOut) public {
        swapAmountExactOut = bound(
            swapAmountExactOut,
            MIN_SWAP_AMOUNT,
            vault.getPoolData(address(pool)).balancesLiveScaled18[usdcIdx]
        );
        uint256 maxAmountIn = dai.balanceOf(alice);

        // First query the swap.
        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 queryAmountIn = aggregatorRouter.querySwapSingleTokenExactOut(
            address(pool),
            dai,
            usdc,
            swapAmountExactOut,
            alice,
            bytes("")
        );
        // Restore the state before the query.
        vm.revertTo(snapshot);

        // Then execute the actual swap.
        vm.startPrank(alice);
        dai.transfer(address(vault), maxAmountIn);
        uint256 actualAmountIn = aggregatorRouter.swapSingleTokenExactOut(
            address(pool),
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

    function testRouterVersion() public view {
        assertEq(aggregatorRouter.version(), version, "Router version mismatch");
    }

    function testSendEth() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(IAggregatorRouter.CannotReceiveEth.selector);
        payable(aggregatorRouter).sendValue(address(this).balance);
    }

    /************************************
                Add Liquidity
    ************************************/
    function testAddLiquidityProportional() public {
        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

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

        _checkAddLiquidityProportional(balancesBefore, exactBptAmountOut, amountsIn, maxAmountsIn);
    }

    function _checkAddLiquidityProportional(
        BaseVaultTest.Balances memory balancesBefore,
        uint256 exactBptAmountOut,
        uint256[] memory amountsIn,
        uint256[] memory maxAmountsIn
    ) internal view {
        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

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

        assertEq(
            balancesAfter.aliceTokens[daiIdx],
            balancesBefore.aliceTokens[daiIdx] - amountsIn[daiIdx],
            "Wrong DAI balance (alice) after proportional liquidity"
        );
        assertEq(
            balancesAfter.aliceTokens[usdcIdx],
            balancesBefore.aliceTokens[usdcIdx] - amountsIn[usdcIdx],
            "Wrong USDC balance (alice) after proportional liquidity"
        );
        assertEq(
            balancesAfter.aliceBpt,
            balancesBefore.aliceBpt + exactBptAmountOut,
            "Wrong BPT balance (alice) after proportional liquidity"
        );

        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + amountsIn[daiIdx],
            "Wrong DAI balance (vault) after proportional liquidity"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] + amountsIn[usdcIdx],
            "Wrong USDC balance (vault) after proportional liquidity"
        );
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

        vm.expectRevert(abi.encodeWithSelector(BaseRouter.InsufficientPayment.selector, address(usdc)));
        aggregatorRouter.addLiquidityProportional(pool, maxAmountsIn, exactBptAmountOut, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityUnbalanced() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx]);
        dai.transfer(address(vault), exactAmountsIn[daiIdx]);

        uint256 bptAmountOut = aggregatorRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, bytes(""));
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

        assertGt(bptAmountOut, 0, "BPT amount out should be greater than zero for unbalanced liquidity");

        assertEq(
            balancesAfter.aliceTokens[daiIdx],
            balancesBefore.aliceTokens[daiIdx] - exactAmountsIn[daiIdx],
            "Wrong DAI balance (alice) after unbalanced liquidity"
        );
        assertEq(
            balancesAfter.aliceTokens[usdcIdx],
            balancesBefore.aliceTokens[usdcIdx] - exactAmountsIn[usdcIdx],
            "Wrong USDC balance (alice) after unbalanced liquidity"
        );
        assertEq(
            balancesAfter.aliceBpt,
            balancesBefore.aliceBpt + bptAmountOut,
            "Wrong BPT balance (alice) after unbalanced liquidity"
        );

        assertEq(
            balancesAfter.vaultTokens[daiIdx],
            balancesBefore.vaultTokens[daiIdx] + exactAmountsIn[daiIdx],
            "Wrong DAI balance (vault) after unbalanced liquidity"
        );
        assertEq(
            balancesAfter.vaultTokens[usdcIdx],
            balancesBefore.vaultTokens[usdcIdx] + exactAmountsIn[usdcIdx],
            "Wrong USDC balance (vault) after unbalanced liquidity"
        );
    }

    function testAddLiquidityUnbalancedRevertIfInsufficientPayment() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[daiIdx] = balancesBefore.aliceTokens[daiIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx] / 2);
        dai.transfer(address(vault), exactAmountsIn[daiIdx] / 2);

        vm.expectRevert(abi.encodeWithSelector(BaseRouter.InsufficientPayment.selector, address(usdc)));
        aggregatorRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityProportionalWithERC7702() public {
        vm.signAndAttachDelegation(address(delegatedContractCode), aliceKey);

        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

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

        _checkAddLiquidityProportional(balancesBefore, exactBptAmountOut, amountsIn, maxAmountsIn);
    }
}
