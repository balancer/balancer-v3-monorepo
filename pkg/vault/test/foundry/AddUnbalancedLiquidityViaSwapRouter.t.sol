// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapKind, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    IAddUnbalancedLiquidityViaSwapRouter
} from "@balancer-labs/v3-interfaces/contracts/vault/IAddUnbalancedLiquidityViaSwapRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { AddUnbalancedLiquidityViaSwapRouter } from "../../contracts/AddUnbalancedLiquidityViaSwapRouter.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AddUnbalancedLiquidityViaSwapRouterTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    string constant POOL_VERSION = "Pool v1";
    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant DELTA_RATIO = 1e15; // 0.1% delta
    uint256 constant ETH_DELTA = 1e3;

    string constant version = "Add Unbalanced Liquidity Via Swap Router Test v1";

    AddUnbalancedLiquidityViaSwapRouter internal addUnbalancedLiquidityViaSwapRouter;

    // Track the indices for the standard dai/weth pool.
    uint256 internal daiIdx;
    uint256 internal wethIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        addUnbalancedLiquidityViaSwapRouter = new AddUnbalancedLiquidityViaSwapRouter(
            IVault(address(vault)),
            permit2,
            weth,
            version
        );

        vm.startPrank(alice);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(
                address(tokens[i]),
                address(addUnbalancedLiquidityViaSwapRouter),
                type(uint160).max,
                type(uint48).max
            );
        }
        vm.stopPrank();
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        (daiIdx, wethIdx) = getSortedIndexes(address(dai), address(weth));

        IERC20[] memory tokens = InputHelpers.sortTokens([address(weth), address(dai)].toMemoryArray().asIERC20());

        newPool = PoolFactoryMock(poolFactory).createPool(name, symbol);
        vm.label(newPool, "ERC20 Pool");

        PoolFactoryMock(poolFactory).registerTestPool(newPool, vault.buildTokenConfig(tokens), poolHooksContract, lp);
    }

    function testAddProportionalAndSwapExactIn__Fuzz(uint256 tokenAmount, bool wethIsEth) public {
        wethIsEth = false;
        uint256[] memory expectedBalances = vault.getCurrentLiveBalances(pool);
        tokenAmount = bound(tokenAmount, 1e6, expectedBalances[wethIdx]);
        expectedBalances[wethIdx] += tokenAmount;

        uint256 halfTokenAmount = tokenAmount / 2;
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 expectedBptAmountOut = addUnbalancedLiquidityViaSwapRouter.queryAddLiquidityUnbalanced(
            pool,
            [halfTokenAmount, halfTokenAmount].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertToState(snapshot);

        IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityAndSwapParams
            memory params = IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityAndSwapParams({
                maxAmountsIn: [halfTokenAmount, halfTokenAmount].toMemoryArray(),
                exactBptAmountOut: expectedBptAmountOut,
                swapTokenIn: weth,
                swapTokenOut: dai,
                swapAmountGiven: halfTokenAmount,
                swapLimit: 0
            });

        snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queryAmountsIn = addUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwapExactIn(
            pool,
            alice,
            params
        );
        vm.revertTo(snapshot);

        uint256 ethBalanceBefore = address(alice).balance;

        bool _wethIsEth = wethIsEth;
        vm.prank(alice);
        uint256[] memory amountsIn = addUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapExactIn{
            value: _wethIsEth ? tokenAmount : 0
        }(pool, MAX_UINT256, _wethIsEth, params);

        if (_wethIsEth) {
            assertApproxEqAbs(
                address(alice).balance,
                ethBalanceBefore - tokenAmount,
                ETH_DELTA,
                "ETH balance mismatch (wethIsEth)"
            );
        } else {
            assertEq(address(alice).balance, ethBalanceBefore, "ETH balance mismatch");
        }

        uint256[] memory balancesAfter = vault.getCurrentLiveBalances(pool);
        assertApproxEqRel(balancesAfter[daiIdx], expectedBalances[daiIdx], DELTA_RATIO, "Dai balance mismatch");
        assertApproxEqRel(balancesAfter[wethIdx], expectedBalances[wethIdx], DELTA_RATIO, "WETH balance mismatch");

        assertEq(amountsIn, queryAmountsIn, "real and query amounts in mismatch");
    }

    function testAddProportionalAndSwapExactOut__Fuzz(uint256 tokenAmount, bool wethIsEth) public {
        uint256[] memory expectedBalances = vault.getCurrentLiveBalances(pool);
        tokenAmount = bound(tokenAmount, 1e6, expectedBalances[wethIdx]);
        expectedBalances[wethIdx] += tokenAmount;
        uint256 halfTokenAmount = tokenAmount / 2;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 bptAmountOut = addUnbalancedLiquidityViaSwapRouter.queryAddLiquidityUnbalanced(
            pool,
            [halfTokenAmount, halfTokenAmount].toMemoryArray(),
            alice,
            bytes("")
        );

        _prankStaticCall();
        uint256 expectedSwapAmountOut = addUnbalancedLiquidityViaSwapRouter.querySwapSingleTokenExactIn(
            pool,
            weth,
            dai,
            halfTokenAmount,
            alice,
            bytes("")
        );
        vm.revertTo(snapshot);

        IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityAndSwapParams
            memory params = IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityAndSwapParams({
                maxAmountsIn: [halfTokenAmount, halfTokenAmount].toMemoryArray(),
                exactBptAmountOut: bptAmountOut,
                swapTokenIn: weth,
                swapTokenOut: dai,
                swapAmountGiven: expectedSwapAmountOut,
                swapLimit: MAX_UINT256
            });

        uint256 ethBalanceBefore = address(alice).balance;
        snapshot = vm.snapshot();
        vm.prank(alice);
        uint256[] memory amountsIn = addUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwapExactOut{
            value: wethIsEth ? tokenAmount : 0
        }(pool, MAX_UINT256, wethIsEth, params);

        if (wethIsEth) {
            assertApproxEqAbs(
                address(alice).balance,
                ethBalanceBefore - tokenAmount,
                ETH_DELTA,
                "ETH balance mismatch (wethIsEth)"
            );
        } else {
            assertEq(address(alice).balance, ethBalanceBefore, "ETH balance mismatch");
        }

        uint256[] memory balancesAfter = vault.getCurrentLiveBalances(pool);

        assertApproxEqRel(balancesAfter[daiIdx], expectedBalances[daiIdx], DELTA_RATIO, "Dai balance mismatch");
        assertApproxEqRel(balancesAfter[wethIdx], expectedBalances[wethIdx], DELTA_RATIO, "WETH balance mismatch");

        vm.revertTo(snapshot);
        _prankStaticCall();
        uint256[] memory queryAmountsIn = addUnbalancedLiquidityViaSwapRouter
            .queryAddUnbalancedLiquidityViaSwapExactOut(pool, alice, params);

        assertEq(amountsIn, queryAmountsIn, "real and query amounts in mismatch");
    }
}
