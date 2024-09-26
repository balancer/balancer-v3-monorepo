// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { BasePoolTest } from "@balancer-labs/v3-vault/test/foundry/utils/BasePoolTest.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";
import { WeightedPoolContractsDeployer } from "./utils/WeightedPoolContractsDeployer.sol";

contract WeightedPoolTest is WeightedPoolContractsDeployer, BasePoolTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;

    uint256[] internal weights;

    uint256 daiIdx;
    uint256 usdcIdx;

    function setUp() public virtual override {
        expectedAddLiquidityBptAmountOut = TOKEN_AMOUNT;
        tokenAmountIn = TOKEN_AMOUNT / 4;
        isTestSwapFeeEnabled = false;

        BasePoolTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        poolMinSwapFeePercentage = 0.001e16; // 0.001%
        poolMaxSwapFeePercentage = 10e16;
    }

    function createPool() internal override returns (address) {
        IERC20[] memory sortedTokens = InputHelpers.sortTokens(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );
        for (uint256 i = 0; i < sortedTokens.length; i++) {
            poolTokens.push(sortedTokens[i]);
            tokenAmounts.push(TOKEN_AMOUNT);
        }

        factory = deployWeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        PoolRoleAccounts memory roleAccounts;
        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            WeightedPoolFactory(address(factory)).create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(sortedTokens),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE,
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        return address(newPool);
    }

    function initPool() internal override {
        vm.startPrank(lp);
        bptAmountOut = _initPool(
            pool,
            tokenAmounts,
            // Account for the precision loss
            expectedAddLiquidityBptAmountOut - DELTA
        );
        vm.stopPrank();
    }

    function testGetBptRate() public {
        vm.expectRevert(WeightedPool.WeightedPoolBptRateUnsupported.selector);
        IRateProvider(pool).getRate();
    }

    function testFailSwapFeeTooLow() public {
        TokenConfig[] memory tokenConfigs = new TokenConfig[](2);
        tokenConfigs[daiIdx].token = IERC20(dai);
        tokenConfigs[usdcIdx].token = IERC20(usdc);

        PoolRoleAccounts memory roleAccounts;

        address lowFeeWeightedPool = WeightedPoolFactory(address(factory)).create(
            "ERC20 Pool",
            "ERC20POOL",
            tokenConfigs,
            [uint256(50e16), uint256(50e16)].toMemoryArray(),
            roleAccounts,
            IBasePool(pool).getMinimumSwapFeePercentage() - 1, // Swap fee too low
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            "Low fee pool"
        );

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooLow.selector);
        factoryMock.registerTestPool(lowFeeWeightedPool, tokenConfigs);
    }

    function testSandwichSwapExactInWeighted() public {
        setSwapFeePercentage(10e16);

        uint256 exactAmountIn = defaultAmount / 10;

        vm.startPrank(alice);

        uint256 snapshotId = vm.snapshot();

        uint256 amountOut = router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            exactAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        console.log('simple swap amount in: ', exactAmountIn);
        console.log('simple swap amount out: ', amountOut);

        vm.revertTo(snapshotId);

        uint256 balanceUsdcBefore = usdc.balanceOf(alice);
        uint256 balanceDaiBefore = dai.balanceOf(alice);

        router.addLiquidityProportional(pool, [uint256(1e36), uint256(1e36)].toMemoryArray(), uint256(1e30), false, bytes(""));
        router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            exactAmountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        router.removeLiquidityProportional(
            pool,
            IERC20(pool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );

        uint256 intermediateDaiBalance = dai.balanceOf(alice);

        router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            amountOut - (intermediateDaiBalance - defaultBalance),
            exactAmountIn * 100,
            MAX_UINT256,
            false,
            bytes("")
        );

        uint256 balanceUsdcAfter = usdc.balanceOf(alice);
        uint256 balanceDaiAfter = dai.balanceOf(alice);
        uint256 sandwichAmountIn = balanceUsdcBefore - balanceUsdcAfter;
        uint256 sandwichAmountOut = balanceDaiAfter - balanceDaiBefore;

        console.log('sandwich amount in: ', sandwichAmountIn);
        console.log('sandwich amount out: ', sandwichAmountOut);
        assertEq(sandwichAmountOut, amountOut, "User did not get the same amount out end to end");
        assertGe(sandwichAmountIn, exactAmountIn, "User paid less using the sandwich attack");
    }
}
