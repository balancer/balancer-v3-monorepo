// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { AggregatorRouter } from "../../contracts/AggregatorRouter.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AggregatorRouterTest is BaseVaultTest {
    using Address for address payable;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant MIN_SWAP_AMOUNT = 1e6;
    string constant version = "test";

    AggregatorRouter internal aggregatorRouter;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        rateProvider = deployRateProviderMock();

        BaseVaultTest.setUp();
        aggregatorRouter = deployAggregatorRouter(IVault(address(vault)), version);
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

    function testGetVault() public view {
        assertNotEq(address(vault), address(0), "Vault not set");
        assertEq(address(aggregatorRouter.getVault()), address(vault), "Wrong vault");
    }

    /************************************
                  EXACT IN
    ************************************/

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
        vm.expectRevert(IAggregatorRouter.SwapInsufficientPayment.selector);
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
        uint256 minAmountOut = dai.balanceOf(alice);
        uint256 partialTransfer = DEFAULT_AMOUNT / 2;

        vm.startPrank(alice);
        dai.transfer(address(vault), partialTransfer);
        vm.expectRevert(IAggregatorRouter.SwapInsufficientPayment.selector);
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

    /************************************
                  EXACT OUT
    ************************************/

    function testQuerySwapExactOut() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        aggregatorRouter.querySwapSingleTokenExactOut(pool, dai, usdc, MAX_UINT256, address(this), bytes(""));
    }

    function testSwapExactOutWithoutPayment() public {
        vm.prank(alice);
        vm.expectRevert(IAggregatorRouter.SwapInsufficientPayment.selector);
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
        vm.expectRevert(IAggregatorRouter.SwapInsufficientPayment.selector);
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
        vm.expectRevert(IAggregatorRouter.SwapInsufficientPayment.selector);
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

    function testRouterVersion() public view {
        assertEq(aggregatorRouter.version(), version, "Router version mismatch");
    }

    function testSendEth() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(IAggregatorRouter.CannotReceiveEth.selector);
        payable(aggregatorRouter).sendValue(address(this).balance);
    }
}
