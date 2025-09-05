// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IAddUnbalancedLiquidityViaSwapRouter
} from "@balancer-labs/v3-interfaces/contracts/vault/IAddUnbalancedLiquidityViaSwapRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

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

        poolArgs = abi.encode(vault, name, symbol);
    }

    function testAddProportionalAndSwapExactIn__Fuzz(
        uint256 exactAmountIn,
        uint256 maxAmountIn,
        uint256 liquidityRatio
    ) public {
        bool wethIsEth = false;
        uint256[] memory balancesBefore = vault.getCurrentLiveBalances(pool);
        exactAmountIn = bound(exactAmountIn, 1e6, balancesBefore[wethIdx]);
        maxAmountIn = bound(maxAmountIn, exactAmountIn, balancesBefore[daiIdx]);
        liquidityRatio = bound(liquidityRatio, 2, 5);

        uint256 addLiquidityAmount = exactAmountIn / liquidityRatio;

        // Get expected BPT out for the add liquidity from the standard router
        uint256 snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256 expectedBptAmountOut = addUnbalancedLiquidityViaSwapRouter.queryAddLiquidityUnbalanced(
            pool,
            [addLiquidityAmount, addLiquidityAmount].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertToState(snapshot);

        // Create add liquidity and swap params
        IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityAndSwapParams
            memory params = IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityAndSwapParams({
                proportionalMaxAmountsIn: [addLiquidityAmount, addLiquidityAmount].toMemoryArray(),
                exactProportionalBptAmountOut: expectedBptAmountOut,
                tokenExactIn: weth,
                tokenMaxIn: dai,
                exactAmountIn: exactAmountIn,
                maxAmountIn: exactAmountIn * 2,
                addLiquidityUserData: bytes(""),
                swapUserData: bytes("")
            });

        // Get query amounts in from addLiquidityViaSwapRouter
        snapshot = vm.snapshotState();
        _prankStaticCall();
        uint256[] memory queryAmountsIn = addUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwap(
            pool,
            alice,
            params
        );
        vm.revertToState(snapshot);

        uint256 ethBalanceBefore = address(alice).balance;
        // Stack too deep
        bool _wethIsEth = wethIsEth;
        vm.prank(alice);
        uint256[] memory amountsIn = addUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwap{
            value: _wethIsEth ? exactAmountIn : 0
        }(pool, MAX_UINT256, _wethIsEth, params);

        // Check ETH balance
        if (_wethIsEth) {
            assertApproxEqAbs(
                address(alice).balance,
                ethBalanceBefore - exactAmountIn,
                ETH_DELTA,
                "ETH balance mismatch (wethIsEth)"
            );
        } else {
            assertEq(address(alice).balance, ethBalanceBefore, "ETH balance mismatch");
        }

        uint256[] memory _balancesBefore = balancesBefore;
        uint256 _exactAmountIn = exactAmountIn;
        uint256 _maxAmountIn = maxAmountIn;
        // Compute expected balances with real balances
        uint256[] memory balancesAfter = vault.getCurrentLiveBalances(pool);
        assertApproxEqRel(
            balancesAfter[wethIdx],
            _balancesBefore[wethIdx] + _exactAmountIn,
            DELTA_RATIO,
            "WETH balance mismatch"
        );
        assertLe(balancesAfter[daiIdx], _balancesBefore[daiIdx] + _maxAmountIn, "DAI balance mismatch");

        // Compare real amounts in with query amounts in
        assertEq(amountsIn, queryAmountsIn, "real and query amounts in mismatch");
    }
}
