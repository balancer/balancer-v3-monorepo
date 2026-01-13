// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

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

import { RouterMock } from "../../contracts/test/RouterMock.sol";
import { RouterHooks } from "../../contracts/RouterHooks.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { SimpleEIP7702Contract } from "./utils/SimpleEIP7702Contract.sol";

contract PrepaidRouterTest is BaseVaultTest {
    using Address for address payable;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant MIN_SWAP_AMOUNT = 1e6;
    string constant version = "Mock Router v1";

    SimpleEIP7702Contract internal delegatedContractCode;

    // Track the indices for the standard weth/usdc pool.
    uint256 internal wethIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        rateProvider = deployRateProviderMock();

        BaseVaultTest.setUp();
        prepaidRouter = deployRouterMock(IVault(address(vault)), weth, IPermit2(address(0)));

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

    function testSwapExactIn() public {
        _testSwapExactIn(usdcIdx, wethIdx, false);
    }

    function testSwapExactInEthToUsdc() public {
        _testSwapExactIn(wethIdx, usdcIdx, true);
    }

    function testSwapExactInUsdcToEth() public {
        _testSwapExactIn(usdcIdx, wethIdx, true);
    }

    function _testSwapExactIn(uint256 tokenInIdx, uint256 tokenOutIdx, bool wethIsEth) internal {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        bool isEthTokenIn = wethIsEth && tokenInIdx == wethIdx;
        bool isEthTokenOut = wethIsEth && tokenOutIdx == wethIdx;
        uint256 amountIn = balancesBefore.poolTokens[tokenInIdx] / 2;

        vm.startPrank(alice);
        if (isEthTokenIn == false) {
            tokens[tokenInIdx].transfer(address(vault), amountIn);
        }

        uint256 amountOut = prepaidRouter.swapSingleTokenExactIn{ value: isEthTokenIn ? amountIn : 0 }(
            pool,
            tokens[tokenInIdx],
            tokens[tokenOutIdx],
            amountIn,
            0,
            MAX_UINT256,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();

        // Check alice balances after the swap
        BaseVaultTest.Balances memory balanceAfter = getBalances(alice);
        if (isEthTokenIn) {
            assertEq(balanceAfter.aliceEth, balancesBefore.aliceEth - amountIn, "Wrong ETH balance (alice)");

            assertEq(
                balanceAfter.aliceTokens[tokenInIdx],
                balancesBefore.aliceTokens[tokenInIdx],
                "Wrong TokenIn balance (alice)"
            );
            assertEq(
                balanceAfter.aliceTokens[tokenOutIdx],
                balancesBefore.aliceTokens[tokenOutIdx] + amountOut,
                "Wrong TokenOut balance (alice)"
            );
        } else if (isEthTokenOut) {
            assertEq(balanceAfter.aliceEth, balancesBefore.aliceEth + amountOut, "Wrong ETH balance (alice)");

            assertEq(
                balanceAfter.aliceTokens[tokenInIdx],
                balancesBefore.aliceTokens[tokenInIdx] - amountIn,
                "Wrong TokenIn balance (alice)"
            );
            assertEq(
                balanceAfter.aliceTokens[tokenOutIdx],
                balancesBefore.aliceTokens[tokenOutIdx],
                "Wrong TokenOut balance (alice)"
            );
        } else {
            assertEq(
                balanceAfter.aliceTokens[tokenInIdx],
                balancesBefore.aliceTokens[tokenInIdx] - amountIn,
                "Wrong TokenIn balance (alice)"
            );
            assertEq(
                balanceAfter.aliceTokens[tokenOutIdx],
                balancesBefore.aliceTokens[tokenOutIdx] + amountOut,
                "Wrong TokenOut balance (alice)"
            );
        }

        // Check pool balances after the swap
        assertEq(
            balanceAfter.poolTokens[tokenInIdx],
            balancesBefore.poolTokens[tokenInIdx] + amountIn,
            "Wrong TokenIn pool balance"
        );
        assertEq(
            balanceAfter.poolTokens[tokenOutIdx],
            balancesBefore.poolTokens[tokenOutIdx] - amountOut,
            "Wrong TokenOut pool balance"
        );
    }

    function testQuerySwapExactIn() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        prepaidRouter.querySwapSingleTokenExactIn(pool, usdc, weth, MIN_SWAP_AMOUNT, address(this), bytes(""));
    }

    function testSwapExactInMinAmountOut() public {
        vm.startPrank(alice);
        usdc.transfer(address(vault), DEFAULT_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SwapLimit.selector, DEFAULT_AMOUNT, DEFAULT_AMOUNT + 1));
        prepaidRouter.swapSingleTokenExactIn(
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
        prepaidRouter.swapSingleTokenExactIn(
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
        prepaidRouter.swapSingleTokenExactIn(
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
        prepaidRouter.swapSingleTokenExactIn(pool, weth, usdc, exactAmountIn, 0, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testQuerySwapExactIn__Fuzz(uint256 swapAmountExactIn) public {
        swapAmountExactIn = bound(swapAmountExactIn, MIN_SWAP_AMOUNT, vault.getCurrentLiveBalances(pool)[wethIdx]);

        // First query the swap.
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 queryAmountOut = prepaidRouter.querySwapSingleTokenExactIn(
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
        uint256 actualAmountOut = prepaidRouter.swapSingleTokenExactIn(
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

    function testSwapExactOut() public {
        _testSwapExactOut(usdcIdx, wethIdx, false);
    }

    function testSwapExactOutEthToUsdc() public {
        _testSwapExactOut(wethIdx, usdcIdx, true);
    }

    function testSwapExactOutUsdcToEth() public {
        _testSwapExactOut(usdcIdx, wethIdx, true);
    }

    // This silliness required to avoid stack-too-deep.
    enum EthToken {
        NEITHER,
        TOKEN_IN,
        TOKEN_OUT
    }

    function _testSwapExactOut(uint256 tokenInIdx, uint256 tokenOutIdx, bool wethIsEth) internal {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        EthToken ethToken;
        if (wethIsEth && tokenInIdx == wethIdx) {
            ethToken = EthToken.TOKEN_IN;
        } else if (wethIsEth && tokenOutIdx == wethIdx) {
            ethToken = EthToken.TOKEN_OUT;
        }

        uint256 amountOut = balancesBefore.poolTokens[tokenOutIdx] / 2;
        uint256 maxAmountIn = wethIsEth && tokenInIdx == wethIdx
            ? balancesBefore.aliceEth / 2
            : balancesBefore.aliceTokens[tokenInIdx] / 2;

        vm.startPrank(alice);
        if (ethToken != EthToken.TOKEN_IN) {
            tokens[tokenInIdx].transfer(address(vault), maxAmountIn);
        }

        uint256 amountIn = prepaidRouter.swapSingleTokenExactOut{
            value: wethIsEth && tokenInIdx == wethIdx ? maxAmountIn : 0
        }(pool, tokens[tokenInIdx], tokens[tokenOutIdx], amountOut, maxAmountIn, MAX_UINT256, wethIsEth, bytes(""));
        vm.stopPrank();

        // Check alice balances after the swap
        BaseVaultTest.Balances memory balanceAfter = getBalances(alice);
        if (ethToken == EthToken.TOKEN_IN) {
            assertEq(balanceAfter.aliceEth, balancesBefore.aliceEth - amountIn, "Wrong ETH balance (alice)");

            assertEq(
                balanceAfter.aliceTokens[tokenInIdx],
                balancesBefore.aliceTokens[tokenInIdx],
                "Wrong TokenIn balance (alice)"
            );
            assertEq(
                balanceAfter.aliceTokens[tokenOutIdx],
                balancesBefore.aliceTokens[tokenOutIdx] + amountOut,
                "Wrong TokenOut balance (alice)"
            );
        } else if (ethToken == EthToken.TOKEN_OUT) {
            assertEq(balanceAfter.aliceEth, balancesBefore.aliceEth + amountOut, "Wrong ETH balance (alice)");

            assertEq(
                balanceAfter.aliceTokens[tokenInIdx],
                balancesBefore.aliceTokens[tokenInIdx] - amountIn,
                "Wrong TokenIn balance (alice)"
            );
            assertEq(
                balanceAfter.aliceTokens[tokenOutIdx],
                balancesBefore.aliceTokens[tokenOutIdx],
                "Wrong TokenOut balance (alice)"
            );
        } else {
            assertEq(
                balanceAfter.aliceTokens[tokenInIdx],
                balancesBefore.aliceTokens[tokenInIdx] - amountIn,
                "Wrong TokenIn balance (alice)"
            );
            assertEq(
                balanceAfter.aliceTokens[tokenOutIdx],
                balancesBefore.aliceTokens[tokenOutIdx] + amountOut,
                "Wrong TokenOut balance (alice)"
            );
        }

        // Check pool balances after the swap
        assertEq(
            balanceAfter.poolTokens[tokenInIdx],
            balancesBefore.poolTokens[tokenInIdx] + amountIn,
            "Wrong TokenIn pool balance"
        );
        assertEq(
            balanceAfter.poolTokens[tokenOutIdx],
            balancesBefore.poolTokens[tokenOutIdx] - amountOut,
            "Wrong TokenOut pool balance"
        );
    }

    function testQuerySwapExactOut() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        prepaidRouter.querySwapSingleTokenExactOut(pool, weth, usdc, MAX_UINT256, address(this), bytes(""));
    }

    function testSwapExactOutWithoutPayment() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(weth)));
        prepaidRouter.swapSingleTokenExactOut(
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
        prepaidRouter.swapSingleTokenExactOut(
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
        prepaidRouter.swapSingleTokenExactOut(
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
        prepaidRouter.swapSingleTokenExactOut(
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
        prepaidRouter.swapSingleTokenExactOut(
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
        uint256 queryAmountIn = prepaidRouter.querySwapSingleTokenExactOut(
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
        uint256 actualAmountIn = prepaidRouter.swapSingleTokenExactOut(
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
        _testAddLiquidityProportional(false);
    }

    function testAddLiquidityProportionalWithEth() public {
        _testAddLiquidityProportional(true);
    }

    function _testAddLiquidityProportional(bool wethIsEth) internal {
        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);

        maxAmountsIn[wethIdx] = wethIsEth ? balancesBefore.aliceEth : balancesBefore.aliceTokens[wethIdx];
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx];

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);
        if (wethIsEth == false) {
            weth.transfer(address(vault), maxAmountsIn[wethIdx]);
        }

        uint256[] memory amountsIn = prepaidRouter.addLiquidityProportional{
            value: wethIsEth ? maxAmountsIn[wethIdx] : 0
        }(pool, maxAmountsIn, exactBptAmountOut, wethIsEth, bytes(""));
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
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), wethIsEth, alice);
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

        // WETH is checked first due to token sorting, so it will be the one that fails.
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(weth)));
        prepaidRouter.addLiquidityProportional(pool, maxAmountsIn, exactBptAmountOut, false, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityUnbalanced() public {
        _testAddLiquidityUnbalanced(false);
    }

    function testAddLiquidityUnbalancedWithEth() public {
        _testAddLiquidityUnbalanced(true);
    }

    function _testAddLiquidityUnbalanced(bool wethIsEth) internal {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[wethIdx] = wethIsEth ? balancesBefore.aliceEth / 100 : balancesBefore.aliceTokens[wethIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx]);
        if (wethIsEth == false) {
            weth.transfer(address(vault), exactAmountsIn[wethIdx]);
        }

        uint256 bptAmountOut = prepaidRouter.addLiquidityUnbalanced{ value: wethIsEth ? exactAmountsIn[wethIdx] : 0 }(
            pool,
            exactAmountsIn,
            0,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();

        assertGt(bptAmountOut, 0, "BPT amount out should be greater than zero for unbalanced liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(exactAmountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(exactAmountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, int256(bptAmountOut), wethIsEth, alice);
    }

    function testAddLiquidityUnbalancedRevertIfInsufficientPayment() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[wethIdx] = balancesBefore.aliceTokens[wethIdx] / 2;
        exactAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 3;

        vm.startPrank(alice);
        usdc.transfer(address(vault), exactAmountsIn[usdcIdx] / 2);
        weth.transfer(address(vault), exactAmountsIn[wethIdx] / 2);

        // WETH is checked first due to token sorting, so it will be the one that fails.
        vm.expectRevert(abi.encodeWithSelector(RouterHooks.InsufficientPayment.selector, address(weth)));
        prepaidRouter.addLiquidityUnbalanced(pool, exactAmountsIn, 0, false, bytes(""));
        vm.stopPrank();
    }

    function testAddLiquidityProportionalWithERC7702() public {
        vm.signAndAttachDelegation(address(delegatedContractCode), aliceKey);

        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;

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
            to: address(prepaidRouter),
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
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), alice);
    }

    function testAddLiquiditySingleTokenExactOut() public {
        _testAddLiquiditySingleTokenExactOut(false);
    }

    function testAddLiquiditySingleTokenExactOutWithEth() public {
        _testAddLiquiditySingleTokenExactOut(true);
    }

    function _testAddLiquiditySingleTokenExactOut(bool wethIsEth) internal {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 exactBptAmountOut = IERC20(pool).totalSupply() / 5;
        uint256 maxAmountIn = wethIsEth ? balancesBefore.aliceEth : balancesBefore.aliceTokens[wethIdx];

        vm.startPrank(alice);
        if (wethIsEth == false) {
            weth.transfer(address(vault), maxAmountIn);
        }

        uint256 amountIn = prepaidRouter.addLiquiditySingleTokenExactOut{ value: wethIsEth ? maxAmountIn : 0 }(
            pool,
            weth,
            maxAmountIn,
            exactBptAmountOut,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();

        assertGt(amountIn, 0, "Amount in should be greater than zero for single token exact out liquidity");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountIn);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, int256(exactBptAmountOut), wethIsEth, alice);
    }

    function testDonate() public {
        _testDonate(false);
    }

    function testDonateWithEth() public {
        _testDonate(true);
    }

    function _testDonate(bool wethIsEth) internal {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[wethIdx] = wethIsEth ? balancesBefore.aliceEth / 2 : balancesBefore.aliceTokens[wethIdx] / 2;
        amountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 2;

        vm.startPrank(alice);
        usdc.transfer(address(vault), amountsIn[usdcIdx]);
        if (wethIsEth == false) {
            weth.transfer(address(vault), amountsIn[wethIdx]);
        }

        prepaidRouter.donate{ value: wethIsEth ? amountsIn[wethIdx] : 0 }(pool, amountsIn, wethIsEth, bytes(""));
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, int256(0), wethIsEth, alice);
    }

    function testAddLiquidityCustom() public {
        _testAddLiquidityCustom(false);
    }

    function testAddLiquidityCustomWithEth() public {
        _testAddLiquidityCustom(true);
    }

    function _testAddLiquidityCustom(bool wethIsEth) internal {
        uint256 minBptAmountOut = IERC20(pool).totalSupply() / 5;

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[wethIdx] = wethIsEth ? balancesBefore.aliceEth / 10 : balancesBefore.aliceTokens[wethIdx] / 2;
        maxAmountsIn[usdcIdx] = balancesBefore.aliceTokens[usdcIdx] / 10;

        vm.startPrank(alice);
        usdc.transfer(address(vault), maxAmountsIn[usdcIdx]);
        if (wethIsEth == false) {
            weth.transfer(address(vault), maxAmountsIn[wethIdx]);
        }

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = prepaidRouter.addLiquidityCustom{
            value: wethIsEth ? maxAmountsIn[wethIdx] : 0
        }(pool, maxAmountsIn, minBptAmountOut, wethIsEth, bytes(""));
        vm.stopPrank();

        assertEq(maxAmountsIn[wethIdx], amountsIn[wethIdx], "Max weth amount in should match actual weth amount in");
        assertEq(maxAmountsIn[usdcIdx], amountsIn[usdcIdx], "Max USDC amount in should match actual USDC amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = int256(amountsIn[wethIdx]);
        vaultBalancesDiff[usdcIdx] = int256(amountsIn[usdcIdx]);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, int256(bptAmountOut), wethIsEth, alice);
    }

    /***************************************************************************
                                   Remove Liquidity
    ***************************************************************************/

    function testRemoveLiquidityProportional() public {
        _testRemoveLiquidityProportional(false);
    }

    function testRemoveLiquidityProportionalWithEth() public {
        _testRemoveLiquidityProportional(true);
    }

    function _testRemoveLiquidityProportional(bool wethIsEth) internal {
        uint256 bptAmountIn = IERC20(pool).totalSupply() / 5;

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        vm.startPrank(lp);
        IERC20(pool).approve(address(prepaidRouter), bptAmountIn);

        uint256[] memory amountsOut = prepaidRouter.removeLiquidityProportional(
            pool,
            bptAmountIn,
            new uint256[](2),
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, -int256(bptAmountIn), wethIsEth, lp);
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        _testRemoveLiquiditySingleTokenExactIn(false);
    }

    function testRemoveLiquiditySingleTokenExactInWithEth() public {
        _testRemoveLiquiditySingleTokenExactIn(true);
    }

    function _testRemoveLiquiditySingleTokenExactIn(bool wethIsEth) internal {
        uint256 exactBptAmountIn = IERC20(pool).totalSupply() / 5;

        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        vm.startPrank(lp);
        IERC20(pool).approve(address(prepaidRouter), exactBptAmountIn);

        uint256 amountOut = prepaidRouter.removeLiquiditySingleTokenExactIn(
            pool,
            exactBptAmountIn,
            weth,
            1,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountOut);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, -int256(exactBptAmountIn), wethIsEth, lp);
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        _testRemoveLiquiditySingleTokenExactOut(false);
    }

    function testRemoveLiquiditySingleTokenExactOutWithEth() public {
        _testRemoveLiquiditySingleTokenExactOut(true);
    }

    function _testRemoveLiquiditySingleTokenExactOut(bool wethIsEth) internal {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);
        uint256 maxBptAmountIn = IERC20(pool).totalSupply();

        vm.startPrank(lp);
        IERC20(pool).approve(address(prepaidRouter), maxBptAmountIn);

        uint256 exactAmountOut = balancesBefore.vaultTokens[wethIdx] / 2;

        uint256 bptAmountIn = prepaidRouter.removeLiquiditySingleTokenExactOut(
            pool,
            maxBptAmountIn,
            weth,
            exactAmountOut,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();

        assertLe(bptAmountIn, maxBptAmountIn, "BPT amount in should be less than or equal to max BPT amount in");

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(exactAmountOut);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, -int256(bptAmountIn), wethIsEth, lp);
    }

    function removeLiquidityCustom() public {
        _removeLiquidityCustom(false);
    }

    function removeLiquidityCustomWithEth() public {
        _removeLiquidityCustom(true);
    }

    function _removeLiquidityCustom(bool wethIsEth) internal {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 exactBptAmountIn = IERC20(pool).totalSupply();
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[wethIdx] = wethIsEth ? balancesBefore.aliceEth / 100 : balancesBefore.lpTokens[wethIdx];
        minAmountsOut[usdcIdx] = balancesBefore.lpTokens[usdcIdx];

        vm.startPrank(lp);
        IERC20(pool).approve(address(prepaidRouter), exactBptAmountIn);

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = prepaidRouter.removeLiquidityCustom(
            pool,
            exactBptAmountIn,
            minAmountsOut,
            wethIsEth,
            bytes("")
        );
        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, -int256(bptAmountIn), wethIsEth, lp);
    }

    function testRemoveLiquidityRecovery() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(alice);

        uint256 exactBptAmountIn = IERC20(pool).balanceOf(lp);

        vm.startPrank(lp);
        vault.manualEnableRecoveryMode(pool);
        IERC20(pool).approve(address(prepaidRouter), exactBptAmountIn);

        uint256[] memory amountsOut = prepaidRouter.removeLiquidityRecovery(pool, exactBptAmountIn, new uint256[](2));

        vm.stopPrank();

        int256[] memory vaultBalancesDiff = new int256[](2);
        vaultBalancesDiff[wethIdx] = -int256(amountsOut[wethIdx]);
        vaultBalancesDiff[usdcIdx] = -int256(amountsOut[usdcIdx]);
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, -int256(exactBptAmountIn), lp);
    }

    /***************************************************************************
                                Other Router Functions
    ***************************************************************************/

    function testRouterVersion() public view {
        assertEq(prepaidRouter.version(), version, "Router version mismatch");
    }

    function _checkBalancesDiff(
        BaseVaultTest.Balances memory balancesBefore,
        int256[] memory vaultBalancesDiff,
        int256 bptAmountDiff,
        address user
    ) public view {
        _checkBalancesDiff(balancesBefore, vaultBalancesDiff, bptAmountDiff, false, user);
    }

    function _checkBalancesDiff(
        BaseVaultTest.Balances memory balancesBefore,
        int256[] memory vaultBalancesDiff,
        int256 bptAmountDiff,
        bool wethIsEth,
        address user
    ) internal view {
        BaseVaultTest.Balances memory balancesAfter = getBalances(alice);

        if (user == alice) {
            _checkAliceBalances(balancesBefore, balancesAfter, vaultBalancesDiff, bptAmountDiff, wethIsEth);
        } else if (user == lp) {
            _checkLpBalances(balancesBefore, balancesAfter, vaultBalancesDiff, bptAmountDiff, wethIsEth);
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
            balancesAfter.poolTokens[wethIdx],
            uint256(int256(balancesBefore.poolTokens[wethIdx]) + vaultBalancesDiff[wethIdx]),
            "Wrong WETH pool balance"
        );
        assertEq(
            balancesAfter.poolTokens[usdcIdx],
            uint256(int256(balancesBefore.poolTokens[usdcIdx]) + vaultBalancesDiff[usdcIdx]),
            "Wrong USDC pool balance"
        );
    }

    function _checkAliceBalances(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        int256[] memory vaultBalancesDiff,
        int256 bptAmountDiff,
        bool wethIsEth
    ) internal view {
        if (wethIsEth) {
            assertEq(
                balancesAfter.aliceEth,
                uint256(int256(balancesBefore.aliceEth) - vaultBalancesDiff[wethIdx]),
                "Wrong ETH balance (alice)"
            );

            assertEq(
                balancesAfter.aliceTokens[wethIdx],
                balancesBefore.aliceTokens[wethIdx],
                "Wrong WETH balance (alice)"
            );
        } else {
            assertEq(balancesAfter.aliceEth, balancesBefore.aliceEth, "Wrong ETH balance (alice)");

            assertEq(
                balancesAfter.aliceTokens[wethIdx],
                uint256(int256(balancesBefore.aliceTokens[wethIdx]) - vaultBalancesDiff[wethIdx]),
                "Wrong WETH balance (alice)"
            );
        }
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
    }

    function _checkLpBalances(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        int256[] memory vaultBalancesDiff,
        int256 bptAmountDiff,
        bool wethIsEth
    ) internal view {
        if (wethIsEth) {
            assertEq(
                balancesAfter.lpEth,
                uint256(int256(balancesBefore.lpEth) - vaultBalancesDiff[wethIdx]),
                "Wrong ETH balance (lp)"
            );

            assertEq(balancesAfter.lpTokens[wethIdx], balancesBefore.lpTokens[wethIdx], "Wrong WETH balance (lp)");
        } else {
            assertEq(balancesAfter.lpEth, balancesBefore.lpEth, "Wrong ETH balance (lp)");

            assertEq(
                balancesAfter.lpTokens[wethIdx],
                uint256(int256(balancesBefore.lpTokens[wethIdx]) - vaultBalancesDiff[wethIdx]),
                "Wrong WETH balance (lp)"
            );
        }
        assertEq(
            balancesAfter.lpTokens[usdcIdx],
            uint256(int256(balancesBefore.lpTokens[usdcIdx]) - vaultBalancesDiff[usdcIdx]),
            "Wrong USDC balance (lp)"
        );
        assertEq(balancesAfter.lpBpt, uint256(int256(balancesBefore.lpBpt) + bptAmountDiff), "Wrong BPT balance (lp)");
    }
}
