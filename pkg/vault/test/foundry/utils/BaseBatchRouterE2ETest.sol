// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./BaseVaultTest.sol";

contract BaseBatchRouterE2ETest is BaseVaultTest {
    using ArrayHelpers for *;
    using EnumerableMap for *;

    struct UniversalSwapPath {
        IERC20 tokenIn;
        SwapPathStep[] steps;
        uint256 givenAmount;
        uint256 limit;
    }

    uint256 constant DEFAULT_TEST_AMOUNT = 1e18;

    uint256 constant ADD_LIQUIDITY_ROUNDING_ERROR = 2;
    uint256 constant REMOVE_LIQUIDITY_ROUNDING_ERROR = 4e4;

    uint256 constant REMOVE_LIQUIDITY_DELTA = 4e5;
    uint256 constant WRAPPED_TOKEN_AMOUNT = 1e6 * 1e18;

    mapping(address => bool) internal ignoreVaultChangesForTokens;

    // We store tokens and pools in separate structures to make it more expressive when using the required pool.
    IERC20[] private _tokens;
    mapping(address => mapping(address => address)) private _pools;

    uint256[] private _expectedPathAmounts;
    EnumerableMap.AddressToUintMap private _expectedAmounts;

    // Data for comparing operation results.
    mapping(address => int256) private _vaultTokenBalancesDiff;
    mapping(address => int256) private _aliceTokenBalancesDiff;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _createTokens();
        _deployPools();
    }

    /***************************************************************************
                                Private functions
    ***************************************************************************/

    function _createTokens() private {
        _tokens.push(dai);
        _tokens.push(usdc);
        _tokens.push(weth);

        vm.startPrank(lp);
        bufferRouter.initializeBuffer(waDAI, defaultAccountBalance() / 2, 0, 0);
        _tokens.push(waDAI);

        bufferRouter.initializeBuffer(waUSDC, defaultAccountBalance() / 2, 0, 0);
        _tokens.push(waUSDC);

        vm.stopPrank();
    }

    function _deployPools() internal {
        // Create test pools
        address poolWethDai = _createPoolAndSet(address(weth), address(dai), "Pool WETH/DAI");
        address poolDaiUsdc = _createPoolAndSet(address(dai), address(usdc), "Pool DAI/USDC");
        address poolWethUsdc = _createPoolAndSet(address(weth), address(usdc), "Pool WETH/USDC");

        address firstPoolWithWrappedAsset = _createPoolAndSet(address(waUSDC), address(weth), "wUSDC/WETH Pool");
        address secondPoolWithWrappedAsset = _createPoolAndSet(address(waDAI), address(weth), "wDAI/WETH Pool");

        address firstNestedPool = _createPoolAndSet(poolWethDai, poolDaiUsdc, "firstNestedPool");
        address secondNestedPool = _createPoolAndSet(poolDaiUsdc, poolWethUsdc, "secondNestedPool");
        address thirdNestedPool = _createPoolAndSet(poolWethDai, poolWethUsdc, "thirdNestedPool");

        vm.startPrank(lp);
        _initPool(poolWethDai, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);
        _initPool(poolDaiUsdc, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);
        _initPool(poolWethUsdc, [poolInitAmount * 2, poolInitAmount * 2].toMemoryArray(), 0);

        _initPool(firstPoolWithWrappedAsset, [WRAPPED_TOKEN_AMOUNT * 2, WRAPPED_TOKEN_AMOUNT * 2].toMemoryArray(), 0);
        _initPool(secondPoolWithWrappedAsset, [WRAPPED_TOKEN_AMOUNT * 2, WRAPPED_TOKEN_AMOUNT * 2].toMemoryArray(), 0);

        _initPool(firstNestedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(secondNestedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        _initPool(thirdNestedPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);

        IERC20(poolWethDai).transfer(alice, IERC20(poolWethDai).balanceOf(lp));
        IERC20(poolDaiUsdc).transfer(alice, IERC20(poolDaiUsdc).balanceOf(lp));
        IERC20(poolWethUsdc).transfer(alice, IERC20(poolWethUsdc).balanceOf(lp));

        vm.stopPrank();
    }

    function _createPoolAndSet(address tokenA, address tokenB, string memory poolName) private returns (address pool) {
        (pool, ) = _createPool([tokenA, tokenB].toMemoryArray(), poolName);
        _pools[tokenA][tokenB] = pool;
        _pools[tokenB][tokenA] = pool;

        approveForPool(IERC20(pool));
        _tokens.push(IERC20(pool));

        return pool;
    }

    function _assertApproxEqAbsArrays(
        uint256[] memory arrayA,
        uint256[] memory arrayB,
        uint256 delta,
        string memory err
    ) private pure {
        assertEq(arrayA.length, arrayB.length, err);
        for (uint256 i = 0; i < arrayA.length; i++) {
            assertApproxEqAbs(arrayA[i], arrayB[i], delta, err);
        }
    }

    function _assertEqArrays(uint256[] memory arrayA, uint256[] memory arrayB, string memory err) private pure {
        assertEq(arrayA.length, arrayB.length, err);
        for (uint256 i = 0; i < arrayA.length; i++) {
            assertEq(arrayA[i], arrayB[i], err);
        }
    }

    function _assertEqArrays(address[] memory arrayA, address[] memory arrayB, string memory err) private pure {
        assertEq(arrayA.length, arrayB.length, err);
        for (uint256 i = 0; i < arrayA.length; i++) {
            assertEq(arrayA[i], arrayB[i], err);
        }
    }

    function _checkBalances(
        Balances memory balancesBefore,
        Balances memory balancesAfter,
        bool wethIsEth,
        uint256 delta
    ) private view {
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);

            // If we operate with ETH, we take the diff that belongs to WETH and
            // check that Alice's ETH balance has changed, not her WETH balance.
            if (wethIsEth && address(token) == address(weth)) {
                assertApproxEqAbs(
                    balancesAfter.aliceEth,
                    uint256(int256(balancesBefore.aliceEth) + _aliceTokenBalancesDiff[address(token)]),
                    delta,
                    "The ETH balance of Alice is different than expected"
                );
                assertApproxEqAbs(
                    balancesAfter.aliceTokens[i],
                    balancesBefore.aliceTokens[i],
                    delta,
                    "The WETH balance of Alice should not be changed"
                );
            } else {
                assertApproxEqAbs(
                    balancesAfter.aliceTokens[i],
                    uint256(int256(balancesBefore.aliceTokens[i]) + _aliceTokenBalancesDiff[address(token)]),
                    delta,
                    "The token balance of Alice is different than expected"
                );
            }

            // We skip rebalancing for buffer-related tokens inside the Vault since
            // it's hard to calculate how many tokens the Vault will have in the end.
            if (ignoreVaultChangesForTokens[address(token)]) {
                continue;
            }

            assertApproxEqAbs(
                balancesAfter.vaultTokens[i],
                uint256(int256(balancesBefore.vaultTokens[i]) + _vaultTokenBalancesDiff[address(token)]),
                delta,
                "The token balance of Vault is different than expected"
            );
            assertEq(balancesAfter.vaultEth, balancesBefore.vaultEth, "The ETH balance of Vault should not be changed");
        }
    }

    function _toSwapPathExactAmountIn(
        UniversalSwapPath[] memory paths
    ) private pure returns (SwapPathExactAmountIn[] memory pathsExactIn) {
        pathsExactIn = new SwapPathExactAmountIn[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            pathsExactIn[i] = SwapPathExactAmountIn({
                tokenIn: paths[i].tokenIn,
                steps: paths[i].steps,
                exactAmountIn: paths[i].givenAmount,
                minAmountOut: paths[i].limit
            });
        }
    }

    function _toSwapPathExactAmountOut(
        UniversalSwapPath[] memory paths
    ) private pure returns (SwapPathExactAmountOut[] memory pathsExactOut) {
        pathsExactOut = new SwapPathExactAmountOut[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            pathsExactOut[i] = SwapPathExactAmountOut({
                tokenIn: paths[i].tokenIn,
                steps: paths[i].steps,
                maxAmountIn: paths[i].limit,
                exactAmountOut: paths[i].givenAmount
            });
        }
    }

    /***************************************************************************
                                Virtual functions
    ***************************************************************************/

    function querySwapExactIn(
        SwapPathExactAmountIn[] memory pathsExactIn
    )
        internal
        virtual
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        uint256 snapshot = vm.snapshotState();

        _prankStaticCall();
        (pathAmountsOut, tokensOut, amountsOut) = batchRouter.querySwapExactIn(pathsExactIn, address(0), bytes(""));

        vm.revertToState(snapshot);
    }

    function swapExactIn(
        SwapPathExactAmountIn[] memory pathsExactIn,
        bool wethIsEth,
        uint256 ethAmount
    )
        internal
        virtual
        returns (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut)
    {
        vm.prank(alice);
        return batchRouter.swapExactIn{ value: ethAmount }(pathsExactIn, MAX_UINT256, wethIsEth, bytes(""));
    }

    function expectRevertSwapExactIn(
        SwapPathExactAmountIn[] memory pathsExactIn,
        uint256 deadline,
        bool wethIsEth,
        uint256 ethAmount,
        bytes memory error
    ) internal virtual {
        vm.expectRevert(error);
        vm.prank(alice);
        batchRouter.swapExactIn{ value: ethAmount }(pathsExactIn, deadline, wethIsEth, bytes(""));
    }

    function querySwapExactOut(
        SwapPathExactAmountOut[] memory pathsExactOut
    ) internal virtual returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) {
        uint256 snapshot = vm.snapshotState();

        _prankStaticCall();
        (pathAmountsIn, tokensIn, amountsIn) = batchRouter.querySwapExactOut(pathsExactOut, address(0), bytes(""));

        vm.revertToState(snapshot);
    }

    function swapExactOut(
        SwapPathExactAmountOut[] memory pathsExactOut,
        bool wethIsEth,
        uint256 ethAmount
    ) internal virtual returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) {
        vm.prank(alice);
        return batchRouter.swapExactOut{ value: ethAmount }(pathsExactOut, MAX_UINT256, wethIsEth, bytes(""));
    }

    function expectRevertSwapExactOut(
        SwapPathExactAmountOut[] memory pathsExactOut,
        uint256 deadline,
        bool wethIsEth,
        uint256 ethAmount,
        bytes memory error
    ) internal virtual {
        vm.expectRevert(error);
        vm.prank(alice);
        batchRouter.swapExactOut{ value: ethAmount }(pathsExactOut, deadline, wethIsEth, bytes(""));
    }

    /***************************************************************************
                                Internal functions
    ***************************************************************************/

    // This function generates simple expected balance changes based only on tokensIn and tokensOut.
    function generateSimpleDiffs(UniversalSwapPath[] memory paths, SwapKind kind) internal {
        if (kind == SwapKind.EXACT_IN) {
            generateSimpleDiffs(_toSwapPathExactAmountIn(paths));
        } else {
            generateSimpleDiffs(_toSwapPathExactAmountOut(paths));
        }
    }

    function generateSimpleDiffs(SwapPathExactAmountIn[] memory pathsExactIn) internal {
        for (uint256 i = 0; i < pathsExactIn.length; i++) {
            SwapPathExactAmountIn memory pathExactIn = pathsExactIn[i];

            SwapPathStep memory lastStep = pathExactIn.steps[pathExactIn.steps.length - 1];

            addDiffForVault(pathExactIn.tokenIn, int256(pathExactIn.exactAmountIn));
            addDiffForVault(lastStep.tokenOut, -int256(pathExactIn.minAmountOut));

            addDiffForAlice(pathExactIn.tokenIn, -int256(pathExactIn.exactAmountIn));
            addDiffForAlice(lastStep.tokenOut, int256(pathExactIn.minAmountOut));

            addExpectedAmount(lastStep.tokenOut, pathExactIn.minAmountOut);
            addExpectedPathAmount(pathExactIn.minAmountOut);
        }
    }

    function generateSimpleDiffs(SwapPathExactAmountOut[] memory pathsExactOut) internal {
        for (uint256 i = 0; i < pathsExactOut.length; i++) {
            SwapPathExactAmountOut memory pathExactOut = pathsExactOut[i];

            SwapPathStep memory lastStep = pathExactOut.steps[pathExactOut.steps.length - 1];

            addDiffForVault(pathExactOut.tokenIn, int256(pathExactOut.maxAmountIn));
            addDiffForVault(lastStep.tokenOut, -int256(pathExactOut.exactAmountOut));

            addDiffForAlice(pathExactOut.tokenIn, -int256(pathExactOut.maxAmountIn));
            addDiffForAlice(lastStep.tokenOut, int256(pathExactOut.exactAmountOut));

            addExpectedAmount(pathExactOut.tokenIn, pathExactOut.maxAmountIn);
            addExpectedPathAmount(pathExactOut.exactAmountOut);
        }
    }

    // This line is moved into a separate method to provide encapsulation in case we need to extend it later.
    function addExpectedPathAmount(uint256 amount) internal {
        _expectedPathAmounts.push(amount);
    }

    // This line is moved into a separate method to provide encapsulation in case we need to extend it later.
    function addExpectedAmount(IERC20 token, uint256 amount) internal {
        (, uint256 currentAmountOut) = _expectedAmounts.tryGet(address(token));
        _expectedAmounts.set(address(token), currentAmountOut + amount);
    }

    // This line is moved into a separate method to provide encapsulation in case we need to extend it later.
    function addDiffForVault(IERC20 token, int256 diff) internal {
        _vaultTokenBalancesDiff[address(token)] += diff;
    }

    // This line is moved into a separate method to provide encapsulation in case we need to extend it later.
    function addDiffForAlice(IERC20 token, int256 diff) internal {
        _aliceTokenBalancesDiff[address(token)] += diff;
    }

    // Returns the pool, with the order of token A and B not being important.
    function getPool(IERC20 tokenA, IERC20 tokenB) internal view returns (address) {
        return getPool(address(tokenA), address(tokenB));
    }

    function getPool(address tokenA, address tokenB) internal view returns (address pool) {
        pool = _pools[tokenA][tokenB];
        if (pool != address(0)) {
            return pool;
        }

        pool = _pools[tokenB][tokenA];
        if (pool != address(0)) {
            return pool;
        }

        if (pool == address(0)) {
            revert("Test error: Pool not found");
        }

        return pool;
    }

    function testSwap(
        UniversalSwapPath[] memory paths,
        SwapKind kind,
        bool wethIsEth,
        uint256 ethAmount,
        uint256 delta
    ) internal {
        if (kind == SwapKind.EXACT_IN) {
            testSwapExactIn(_toSwapPathExactAmountIn(paths), wethIsEth, ethAmount, delta);
        } else {
            testSwapExactOut(_toSwapPathExactAmountOut(paths), wethIsEth, ethAmount, delta);
        }
    }

    function testSwapExactIn(
        SwapPathExactAmountIn[] memory pathsExactIn,
        bool wethIsEth,
        uint256 ethAmount,
        uint256 delta
    ) internal {
        // Get balances before swap
        Balances memory balancesBefore = getBalances(alice, _tokens);

        // Get swap results and revert state
        uint256 snapshot = vm.snapshotState();

        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = swapExactIn(
            pathsExactIn,
            wethIsEth,
            ethAmount
        );

        Balances memory balancesAfter = getBalances(alice, _tokens);
        vm.revertToState(snapshot);

        _checkBalances(balancesBefore, balancesAfter, wethIsEth, delta);

        // Get query swap results
        (
            uint256[] memory queryCalculatedPathAmountsOut,
            address[] memory queryTokensOut,
            uint256[] memory queryAmountsOut
        ) = querySwapExactIn(pathsExactIn);

        // Compare actual, expected and query results
        _assertApproxEqAbsArrays(
            pathAmountsOut,
            _expectedPathAmounts,
            delta,
            "Expected path amounts out different than actual"
        );
        _assertEqArrays(queryCalculatedPathAmountsOut, pathAmountsOut, "Query path amounts out different than actual");

        uint256[] memory expectedAmountsOut = new uint256[](_expectedAmounts.length());
        for (uint256 i = 0; i < expectedAmountsOut.length; i++) {
            (, expectedAmountsOut[i]) = _expectedAmounts.at(i);
        }

        // Compare actual, expected and query results
        _assertEqArrays(queryTokensOut, tokensOut, "Query tokens out length mismatch");

        // Compare actual, expected and query results
        _assertApproxEqAbsArrays(amountsOut, expectedAmountsOut, delta, "Expected tokens out different than actual");
        _assertEqArrays(queryAmountsOut, amountsOut, "Query amounts out different than actual");
    }

    function testSwapExactOut(
        SwapPathExactAmountOut[] memory pathsExactOut,
        bool wethIsEth,
        uint256 ethAmount,
        uint256 delta
    ) internal {
        // Get balances before swap
        Balances memory balancesBefore = getBalances(alice, _tokens);

        // Get swap results and revert state
        uint256 snapshot = vm.snapshotState();

        (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) = swapExactOut(
            pathsExactOut,
            wethIsEth,
            ethAmount
        );

        Balances memory balancesAfter = getBalances(alice, _tokens);
        vm.revertToState(snapshot);

        _checkBalances(balancesBefore, balancesAfter, wethIsEth, delta);

        // Get query swap results
        (
            uint256[] memory queryPathAmountsIn,
            address[] memory queryTokensIn,
            uint256[] memory queryAmountsIn
        ) = querySwapExactOut(pathsExactOut);

        // Compare actual, expected and query results
        _assertApproxEqAbsArrays(
            pathAmountsIn,
            _expectedPathAmounts,
            delta,
            "Expected path amounts in different than actual"
        );
        _assertEqArrays(queryPathAmountsIn, pathAmountsIn, "Query path amounts in different than actual");

        uint256[] memory expectedAmountsIn = new uint256[](_expectedAmounts.length());
        for (uint256 i = 0; i < expectedAmountsIn.length; i++) {
            (, expectedAmountsIn[i]) = _expectedAmounts.at(i);
        }

        // Compare actual, expected and query results
        _assertEqArrays(queryTokensIn, tokensIn, "Query tokens in length mismatch");

        // Compare actual, expected and query results
        _assertApproxEqAbsArrays(amountsIn, expectedAmountsIn, delta, "Expected tokens in different than actual");
        _assertEqArrays(queryAmountsIn, amountsIn, "Query amounts in different than actual");
    }
}
