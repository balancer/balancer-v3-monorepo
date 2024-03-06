// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityWithRatesTest is BaseVaultTest {
    using ArrayHelpers for *;

    // Track the indices for the local dai/wsteth pool.
    uint256 localDaiIdx;
    uint256 localWstethIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        rateProvider.mockRate(mockRate);

        localDaiIdx = address(dai) > address(wsteth) ? 1 : 0;
        localWstethIdx = localDaiIdx == 0 ? 1 : 0;
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        // Still need the rate provider at index 0; buildTokenConfig will sort.
        rateProviders[0] = rateProvider;

        return
            address(
                new PoolMock(
                    IVault(address(vault)),
                    "ERC20 Pool",
                    "ERC20POOL",
                    vault.buildTokenConfig([address(wsteth), address(dai)].toMemoryArray().asIERC20(), rateProviders),
                    true,
                    365 days,
                    address(0)
                )
            );
    }

    function testLastLiveBalanceInitialization() public {
        // Need to set the rate before initialization for this test
        pool = createPool();
        rateProvider.mockRate(mockRate);
        initPool();

        uint256[] memory rawBalances = vault.getRawBalances(address(pool));
        uint256[] memory liveBalances = vault.getLastLiveBalances(address(pool));

        assertEq(FixedPoint.mulDown(rawBalances[localWstethIdx], mockRate), liveBalances[localWstethIdx]);
        assertEq(rawBalances[localDaiIdx], liveBalances[localDaiIdx]);
    }

    function testAddLiquiditySingleTokenExactOutWithRate() public {
        uint256[] memory expectedBalances = new uint256[](2);
        expectedBalances[localWstethIdx] = FixedPoint.mulDown(defaultAmount, mockRate);
        expectedBalances[localDaiIdx] = defaultAmount;

        vm.startPrank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.computeBalance.selector,
                expectedBalances, // liveBalancesScaled18
                localWstethIdx,
                150e16 // 150% growth
            )
        );

        router.addLiquiditySingleTokenExactOut(address(pool), wsteth, defaultAmount, defaultAmount, false, bytes(""));
    }

    function testAddLiquidityCustomWithRate() public {
        uint256 rateAdjustedAmount = FixedPoint.mulDown(defaultAmount, mockRate);

        uint256[] memory expectedAmountsIn = new uint256[](2);
        uint256[] memory expectedBalances = new uint256[](2);

        expectedAmountsIn[localWstethIdx] = rateAdjustedAmount;
        expectedAmountsIn[localDaiIdx] = defaultAmount;

        expectedBalances[localWstethIdx] = rateAdjustedAmount;
        expectedBalances[localDaiIdx] = defaultAmount;

        vm.startPrank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                alice,
                expectedAmountsIn, // maxAmountsIn
                defaultAmount, // minBptOut
                expectedBalances, // liveBalancesScaled18
                bytes("")
            )
        );

        router.addLiquidityCustom(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );
    }

    function testRemoveLiquidityProportionalWithRate() public {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        // TODO: Find a way to test rates inside the Vault
        router.removeLiquidityProportional(
            address(pool),
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
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        PoolData memory balances = vault.computePoolDataUpdatingBalancesAndFees(address(pool), Rounding.ROUND_DOWN);
        uint256 bptAmountIn = defaultAmount * 2;

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.computeBalance.selector,
                [balances.balancesLiveScaled18[localDaiIdx], balances.balancesLiveScaled18[localWstethIdx]]
                    .toMemoryArray(),
                localWstethIdx, // tokenOutIndex
                50e16 // invariantRatio
            )
        );

        router.removeLiquiditySingleTokenExactIn(address(pool), bptAmountIn, wsteth, defaultAmount, false, bytes(""));
    }

    function testRemoveLiquidityCustomWithRate() public {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        PoolData memory balances = vault.computePoolDataUpdatingBalancesAndFees(address(pool), Rounding.ROUND_DOWN);
        uint256[] memory expectedAmountsOut = new uint256[](2);

        expectedAmountsOut[localWstethIdx] = FixedPoint.mulDown(defaultAmount, mockRate);
        expectedAmountsOut[localDaiIdx] = defaultAmount;

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                alice,
                defaultAmount, // maxBptAmountIn
                expectedAmountsOut, // minAmountsOut
                [balances.balancesLiveScaled18[localDaiIdx], balances.balancesLiveScaled18[localWstethIdx]]
                    .toMemoryArray(),
                bytes("")
            )
        );

        router.removeLiquidityCustom(
            address(pool),
            defaultAmount,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
