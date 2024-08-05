// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityWithRatesTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    // Track the indices for the local dai/wsteth pool.
    uint256 internal daiIdx;
    uint256 internal wstethIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        rateProvider.mockRate(mockRate);

        (daiIdx, wstethIdx) = getSortedIndexes(address(dai), address(wsteth));
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        // Still need the rate provider at index 0; buildTokenConfig will sort.
        rateProviders[0] = rateProvider;

        address newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        factoryMock.registerTestPool(
            newPool,
            vault.buildTokenConfig([address(wsteth), address(dai)].toMemoryArray().asIERC20(), rateProviders),
            poolHooksContract,
            lp
        );

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
            abi.encodeWithSelector(
                IBasePool.computeBalance.selector,
                expectedBalances, // liveBalancesScaled18
                wstethIdx,
                150e16 // 150% growth
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
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                router,
                expectedAmountsInRaw, // maxAmountsIn
                defaultAmount, // minBptOut
                expectedBalancesRaw,
                bytes("")
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
            abi.encodeWithSelector(
                IBasePool.computeBalance.selector,
                [balances.balancesLiveScaled18[daiIdx], balances.balancesLiveScaled18[wstethIdx]].toMemoryArray(),
                wstethIdx, // tokenOutIndex
                50e16 // invariantRatio
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
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                router,
                defaultAmount, // maxBptAmountIn
                expectedAmountsOutRaw, // minAmountsOut
                [balances.balancesLiveScaled18[daiIdx], balances.balancesLiveScaled18[wstethIdx]].toMemoryArray(),
                bytes("")
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
}
