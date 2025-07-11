// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { SwapKind, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    IAddUnbalancedLiquidityViaSwapRouter
} from "@balancer-labs/v3-interfaces/contracts/vault/IAddUnbalancedLiquidityViaSwapRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { AddUnbalancedLiquidityViaSwapRouter } from "../../contracts/AddUnbalancedLiquidityViaSwapRouter.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AddUnbalancedLiquidityViaSwapRouterTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    string constant POOL_VERSION = "Pool v1";
    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant TOKEN_AMOUNT = 1e16;
    uint256 constant DELTA = 1e11;

    string constant version = "Add Unbalanced Liquidity Via Swap Router Test v1";

    AddUnbalancedLiquidityViaSwapRouter internal addUnbalancedLiquidityViaSwapRouter;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        addUnbalancedLiquidityViaSwapRouter = new AddUnbalancedLiquidityViaSwapRouter(
            IVault(address(vault)),
            permit2,
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

    function createPoolFactory() internal override returns (address) {
        return address(new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
    }

    function _createPool(
        address[] memory tokens,
        string memory
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        PoolRoleAccounts memory roleAccounts;
        newPool = StablePoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            BASE_MIN_SWAP_FEE,
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: POOL_VERSION
            }),
            vault
        );
    }

    function testAddProportionalAndSwapExactIn() public {
        uint256[] memory currentBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory expectedBalances = currentBalances;
        expectedBalances[daiIdx] = currentBalances[daiIdx] + TOKEN_AMOUNT;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 bptAmountOut = router.queryAddLiquidityUnbalanced(
            pool,
            [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertTo(snapshot);

        IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityProportionalParams
            memory addLiquidityParams = IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityProportionalParams({
                maxAmountsIn: [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
                exactBptAmountOut: bptAmountOut,
                userData: bytes("")
            });

        AddUnbalancedLiquidityViaSwapRouter.SwapParams memory swapParams = IAddUnbalancedLiquidityViaSwapRouter
            .SwapParams({
                tokenIn: dai,
                tokenOut: usdc,
                kind: SwapKind.EXACT_IN,
                amountGiven: TOKEN_AMOUNT / 2,
                limit: 0,
                userData: bytes("")
            });

        snapshot = vm.snapshot();
        vm.prank(alice);
        (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountOut,

        ) = addUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwap(
                pool,
                MAX_UINT256,
                addLiquidityParams,
                swapParams
            );

        uint256[] memory balancesAfter = vault.getCurrentLiveBalances(pool);

        assertApproxEqAbs(balancesAfter[daiIdx], expectedBalances[daiIdx], DELTA, "Dai balance mismatch");
        assertApproxEqAbs(balancesAfter[usdcIdx], expectedBalances[usdcIdx], DELTA, "Usdc balance mismatch");

        vm.revertTo(snapshot);
        _prankStaticCall();
        (
            uint256[] memory queryAddLiquidityAmountsIn,
            uint256 queryAddLiquidityBptAmountOut,
            uint256 querySwapAmountOut,

        ) = addUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwap(
                pool,
                alice,
                addLiquidityParams,
                swapParams
            );

        assertEq(
            addLiquidityAmountsIn[daiIdx],
            queryAddLiquidityAmountsIn[daiIdx],
            "query and real dai amounts in mismatch"
        );
        assertEq(
            addLiquidityAmountsIn[usdcIdx],
            queryAddLiquidityAmountsIn[usdcIdx],
            "query and real usdc amounts in mismatch"
        );
        assertEq(addLiquidityBptAmountOut, queryAddLiquidityBptAmountOut, "query and real bpt amount out mismatch");
        assertEq(swapAmountOut, querySwapAmountOut, "query and real swap amount out mismatch");
    }

    function testAddProportionalAndSwapExactOut() public {
        uint256[] memory currentBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory expectedBalances = currentBalances;
        expectedBalances[daiIdx] = currentBalances[daiIdx] + TOKEN_AMOUNT;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 bptAmountOut = router.queryAddLiquidityUnbalanced(
            pool,
            [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertTo(snapshot);

        IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityProportionalParams
            memory addLiquidityParams = IAddUnbalancedLiquidityViaSwapRouter.AddLiquidityProportionalParams({
                maxAmountsIn: [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
                exactBptAmountOut: bptAmountOut,
                userData: bytes("")
            });

        IAddUnbalancedLiquidityViaSwapRouter.SwapParams memory swapParams = IAddUnbalancedLiquidityViaSwapRouter
            .SwapParams({
                tokenIn: dai,
                tokenOut: usdc,
                kind: SwapKind.EXACT_OUT,
                amountGiven: TOKEN_AMOUNT / 2,
                limit: MAX_UINT256,
                userData: bytes("")
            });

        snapshot = vm.snapshot();
        vm.prank(alice);
        (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountIn,

        ) = addUnbalancedLiquidityViaSwapRouter.addUnbalancedLiquidityViaSwap(
                pool,
                MAX_UINT256,
                addLiquidityParams,
                swapParams
            );

        uint256[] memory balancesAfter = vault.getCurrentLiveBalances(pool);

        assertApproxEqAbs(balancesAfter[daiIdx], expectedBalances[daiIdx], DELTA, "Dai balance mismatch");
        assertApproxEqAbs(balancesAfter[usdcIdx], expectedBalances[usdcIdx], DELTA, "Usdc balance mismatch");

        vm.revertTo(snapshot);
        _prankStaticCall();
        (
            uint256[] memory queryAddLiquidityAmountsIn,
            uint256 queryAddLiquidityBptAmountOut,
            uint256 querySwapAmountIn,

        ) = addUnbalancedLiquidityViaSwapRouter.queryAddUnbalancedLiquidityViaSwap(
                pool,
                alice,
                addLiquidityParams,
                swapParams
            );

        assertEq(
            addLiquidityAmountsIn[daiIdx],
            queryAddLiquidityAmountsIn[daiIdx],
            "query and real dai amounts in mismatch"
        );
        assertEq(
            addLiquidityAmountsIn[usdcIdx],
            queryAddLiquidityAmountsIn[usdcIdx],
            "query and real usdc amounts in mismatch"
        );
        assertEq(addLiquidityBptAmountOut, queryAddLiquidityBptAmountOut, "query and real bpt amount out mismatch");
        assertEq(swapAmountIn, querySwapAmountIn, "query and real swap amount in mismatch");
    }
}
