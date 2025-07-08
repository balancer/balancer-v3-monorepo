// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IAggregatorRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IAggregatorRouter.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import {
    StablePoolContractsDeployer
} from "@balancer-labs/v3-pool-stable/test/foundry/utils/StablePoolContractsDeployer.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { AddUnbalancedExtensionRouter } from "../../contracts/AddUnbalancedExtensionRouter.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AddUnbalancedExtensionRouterTest is BaseVaultTest, StablePoolContractsDeployer {
    using Address for address payable;
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant TOKEN_AMOUNT = 1e16;
    string constant POOL_VERSION = "Pool v1";
    uint256 constant DELTA = 1e11;

    string constant version = "Add Unbalanced Extension Router v1";

    AddUnbalancedExtensionRouter internal addUnbalancedExtensionRouter;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        addUnbalancedExtensionRouter = new AddUnbalancedExtensionRouter(IVault(address(vault)), permit2, version);

        vm.startPrank(alice);
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(
                address(tokens[i]),
                address(addUnbalancedExtensionRouter),
                type(uint160).max,
                type(uint48).max
            );
        }
        vm.stopPrank();
    }

    function createPoolFactory() internal override returns (address) {
        return address(deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
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
        uint256 bptAmountOut = addUnbalancedExtensionRouter.queryAddLiquidityUnbalanced(
            pool,
            [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertTo(snapshot);

        AddUnbalancedExtensionRouter.AddLiquidityProportionalParams
            memory addLiquidityParams = AddUnbalancedExtensionRouter.AddLiquidityProportionalParams({
                maxAmountsIn: [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
                exactBptAmountOut: bptAmountOut,
                userData: bytes("")
            });

        AddUnbalancedExtensionRouter.SwapExactInParams memory swapParams = AddUnbalancedExtensionRouter
            .SwapExactInParams({
                tokenIn: dai,
                tokenOut: usdc,
                exactAmountIn: TOKEN_AMOUNT / 2,
                minAmountOut: 0,
                userData: bytes("")
            });

        snapshot = vm.snapshot();
        vm.prank(alice);
        (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountOut,

        ) = addUnbalancedExtensionRouter.addProportionalAndSwapExactIn(
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

        ) = addUnbalancedExtensionRouter.queryAddProportionalAndSwapExactIn(
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
        uint256 bptAmountOut = addUnbalancedExtensionRouter.queryAddLiquidityUnbalanced(
            pool,
            [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
            alice,
            bytes("")
        );
        vm.revertTo(snapshot);

        AddUnbalancedExtensionRouter.AddLiquidityProportionalParams
            memory addLiquidityParams = AddUnbalancedExtensionRouter.AddLiquidityProportionalParams({
                maxAmountsIn: [TOKEN_AMOUNT / 2, TOKEN_AMOUNT / 2].toMemoryArray(),
                exactBptAmountOut: bptAmountOut,
                userData: bytes("")
            });

        AddUnbalancedExtensionRouter.SwapExactOutParams memory swapParams = AddUnbalancedExtensionRouter
            .SwapExactOutParams({
                tokenIn: dai,
                tokenOut: usdc,
                exactAmountOut: TOKEN_AMOUNT / 2,
                maxAmountIn: MAX_UINT256,
                userData: bytes("")
            });

        snapshot = vm.snapshot();
        vm.prank(alice);
        (
            uint256[] memory addLiquidityAmountsIn,
            uint256 addLiquidityBptAmountOut,
            uint256 swapAmountIn,

        ) = addUnbalancedExtensionRouter.addProportionalAndSwapExactOut(
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

        ) = addUnbalancedExtensionRouter.queryAddProportionalAndSwapExactOut(
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
