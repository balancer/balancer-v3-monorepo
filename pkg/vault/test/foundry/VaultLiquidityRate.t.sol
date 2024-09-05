// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityWithRatesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    // Track the indices for the local dai/wsteth pool.
    uint256 internal daiIdx;
    uint256 internal wstethIdx;

    IRateProvider[] internal rateProviders;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        RateProviderMock(address(rateProviders[wstethIdx])).mockRate(mockRate);
    }

    function createPool() internal override returns (address) {
        (daiIdx, wstethIdx) = getSortedIndexes(address(dai), address(wsteth));

        rateProviders = new IRateProvider[](2);

        // Add rate providers for wstEth and dai.
        rateProviders[daiIdx] = new RateProviderMock();
        rateProviders[wstethIdx] = new RateProviderMock();

        // Part of the tests use the rateProvider variable from BaseVaultTest, so we set that to wstEth rate provider.
        rateProvider = RateProviderMock(address(rateProviders[wstethIdx]));

        address newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        // Add tokens in the same order as rate providers.
        IERC20[] memory tokens = new IERC20[](2);
        tokens[daiIdx] = dai;
        tokens[wstethIdx] = wsteth;

        factoryMock.registerTestPool(newPool, vault.buildTokenConfig(tokens, rateProviders), poolHooksContract, lp);

        return newPool;
    }

    function testLastLiveBalanceInitialization() public {
        // Need to set the rate before initialization for this test.
        pool = createPool();
        rateProvider.mockRate(mockRate);
        initPool();

        uint256[] memory rawBalances = vault.getRawBalances(pool);
        uint256[] memory liveBalances = vault.getLastLiveBalances(pool);

        assertEq(FixedPoint.mulDown(rawBalances[wstethIdx], mockRate), liveBalances[wstethIdx]);
        assertEq(rawBalances[daiIdx], liveBalances[daiIdx]);
    }

    function testAddLiquiditySingleTokenExactOutWithRate() public {
        uint256[] memory expectedBalances = new uint256[](2);
        expectedBalances[wstethIdx] = FixedPoint.mulDown(defaultAmount, mockRate);
        expectedBalances[daiIdx] = defaultAmount;

        vm.startPrank(alice);
        vm.expectCall(
            pool,
            abi.encodeCall(
                IBasePool.computeBalance,
                (
                    expectedBalances, // liveBalancesScaled18
                    wstethIdx,
                    150e16 // 150% growth
                )
            )
        );

        router.addLiquiditySingleTokenExactOut(pool, wsteth, defaultAmount, defaultAmount, false, bytes(""));
    }

    function testAddLiquidityCustomWithRate() public {
        uint256 rateAdjustedAmount = FixedPoint.mulDown(defaultAmount, mockRate);

        uint256[] memory expectedAmountsInRaw = new uint256[](2);
        uint256[] memory expectedBalancesRaw = new uint256[](2);

        expectedAmountsInRaw[wstethIdx] = rateAdjustedAmount;
        expectedAmountsInRaw[daiIdx] = defaultAmount;

        expectedBalancesRaw[wstethIdx] = rateAdjustedAmount;
        expectedBalancesRaw[daiIdx] = defaultAmount;

        vm.startPrank(alice);
        vm.expectCall(
            pool,
            abi.encodeCall(
                IPoolLiquidity.onAddLiquidityCustom,
                (
                    address(router),
                    expectedAmountsInRaw, // maxAmountsIn
                    defaultAmount, // minBptOut
                    expectedBalancesRaw,
                    bytes("")
                )
            )
        );

        router.addLiquidityCustom(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );
    }

    function testRemoveLiquidityProportionalWithRate() public {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        // TODO: Find a way to test rates inside the Vault.
        router.removeLiquidityProportional(
            pool,
            defaultAmount * 2,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();
    }

    function testRemoveLiquiditySingleTokenExactInWithRate() public {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        PoolData memory balances = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);
        uint256 bptAmountIn = defaultAmount * 2;

        vm.expectCall(
            pool,
            abi.encodeCall(
                IBasePool.computeBalance,
                (
                    [balances.balancesLiveScaled18[daiIdx], balances.balancesLiveScaled18[wstethIdx]].toMemoryArray(),
                    wstethIdx, // tokenOutIndex
                    50e16 // invariantRatio
                )
            )
        );

        router.removeLiquiditySingleTokenExactIn(pool, bptAmountIn, wsteth, defaultAmount, false, bytes(""));
    }

    function testRemoveLiquidityCustomWithRate() public {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        PoolData memory balances = vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);
        uint256[] memory expectedAmountsOutRaw = new uint256[](2);

        expectedAmountsOutRaw[wstethIdx] = FixedPoint.mulDown(defaultAmount, mockRate);
        expectedAmountsOutRaw[daiIdx] = defaultAmount;

        vm.expectCall(
            pool,
            abi.encodeCall(
                IPoolLiquidity.onRemoveLiquidityCustom,
                (
                    address(router),
                    defaultAmount, // maxBptAmountIn
                    expectedAmountsOutRaw, // minAmountsOut
                    [balances.balancesLiveScaled18[daiIdx], balances.balancesLiveScaled18[wstethIdx]].toMemoryArray(),
                    bytes("")
                )
            )
        );

        router.removeLiquidityCustom(
            pool,
            defaultAmount,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testRemoveLiquiditySingleTokenExactInWithRate__Fuzz(uint256 rateWstEth, uint256 rateDai) public {
        rateWstEth = bound(rateWstEth, 1e16, 1e20);
        rateDai = bound(rateDai, 1e16, 1e20);

        RateProviderMock(address(rateProviders[wstethIdx])).mockRate(rateWstEth);
        RateProviderMock(address(rateProviders[daiIdx])).mockRate(rateDai);

        // Refresh lastBalancesLiveScaled18 with new rates.
        vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);

        // Fix pool liquidity, so there's enough liquidity to `removeLiquiditySingleTokenExactIn`. It adds enough
        // liquidity so that both tokens have 50% of liquidity in the pool, when scaled18. Since both tokens have 18
        // decimals, the only factor to consider is the rate of each one.
        // Considering a pool with exactly poolInitAmount of each token, we need to add tokens in the side where the
        // balance scaled18 is smaller. If rate of WstETH is 1, and DAI is 2, we have less WstETH than DAI, so we need
        // to add more WstETH. The amount of WstETH to add is `(daiBalance * rateDai / rateWstEth - wstEthBalance)`.
        // Since daiBalance and wstEthBalance is poolInitAmount, this formula becomes
        // `poolInitAmount * (rateDai / rateWstEth - 1)`.
        uint256[] memory amountsToAdd = new uint256[](2);
        if (rateWstEth < rateDai) {
            amountsToAdd[wstethIdx] = poolInitAmount * ((rateDai / rateWstEth) - 1);
        } else {
            amountsToAdd[daiIdx] = poolInitAmount * ((rateWstEth / rateDai) - 1);
        }

        if (amountsToAdd[wstethIdx] > 0 || amountsToAdd[daiIdx] > 0) {
            vm.prank(bob);
            router.addLiquidityUnbalanced(pool, amountsToAdd, 1, false, bytes(""));
        }

        // Refresh lastBalancesLiveScaled18 with new rates. Updated lastBalancesLiveScaled18 are needed to calculate
        // the current invariant in getBalances function.
        vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);

        BaseVaultTest.Balances memory balancesBefore = getBalances(bob);

        vm.startPrank(lp);
        uint256[] memory maxAmountsIn = [MAX_UINT128, MAX_UINT128].toMemoryArray();
        uint256[] memory amountsIn = router.addLiquidityProportional(
            pool,
            maxAmountsIn,
            balancesBefore.lpBpt / 2,
            false,
            bytes("")
        );
        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            pool,
            balancesBefore.lpBpt / 2,
            wsteth,
            1,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(bob);

        // To make sure we can compare the invariants from before and after the operation, we need to make sure that LP
        // BPTs have not changed.
        assertEq(balancesBefore.lpBpt, balancesAfter.lpBpt, "LP BPT is wrong");
        assertGe(balancesAfter.poolInvariant, balancesBefore.poolInvariant, "Invariant decreased");
    }

    function testRemoveLiquiditySingleTokenExactOutWithRate__Fuzz(
        uint256 wstEthRate,
        uint256 wstEthAmountOut,
        uint256 removePercentage
    ) public {
        wstEthAmountOut = bound(wstEthAmountOut, defaultAmount / 1e3, defaultAmount * 1e3);
        wstEthRate = bound(wstEthRate, 1e14, 1e22);
        removePercentage = bound(removePercentage, 1e4, 1e18);
        rateProvider.mockRate(wstEthRate);

        vm.startPrank(alice);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[wstethIdx] = wstEthAmountOut;
        amountsIn[daiIdx] = wstEthAmountOut * 2;

        BaseVaultTest.Balances memory balancesBeforeAdd = getBalances(alice);

        router.addLiquidityUnbalanced(pool, amountsIn, 1, false, bytes(""));

        BaseVaultTest.Balances memory balancesBeforeRemove = getBalances(alice);

        assertEq(
            wstEthAmountOut,
            balancesBeforeAdd.aliceTokens[wstethIdx] - balancesBeforeRemove.aliceTokens[wstethIdx],
            "Alice wstEth is wrong after add"
        );

        uint256 removeAmount = wstEthAmountOut.mulDown(removePercentage);

        router.removeLiquiditySingleTokenExactOut(pool, MAX_UINT128, wsteth, removeAmount, false, bytes(""));
        BaseVaultTest.Balances memory balancesAfterRemove = getBalances(alice);
        vm.stopPrank();

        assertEq(
            removeAmount,
            balancesAfterRemove.aliceTokens[wstethIdx] - balancesBeforeRemove.aliceTokens[wstethIdx],
            "Alice wstEth is wrong after remove"
        );
    }
}
