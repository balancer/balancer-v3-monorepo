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

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        rateProvider.mockRate(mockRate);
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
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

        assertEq(FixedPoint.mulDown(rawBalances[0], mockRate), liveBalances[0]);
        assertEq(rawBalances[1], liveBalances[1]);
    }

    function testAddLiquiditySingleTokenExactOutWithRate() public {
        vm.startPrank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.computeBalance.selector,
                [FixedPoint.mulDown(defaultAmount, mockRate), defaultAmount].toMemoryArray(), // liveBalancesScaled18
                0,
                150e16 // 150% growth
            )
        );

        router.addLiquiditySingleTokenExactOut(address(pool), wsteth, defaultAmount, defaultAmount, false, bytes(""));
    }

    function testAddLiquidityCustomWithRate() public {
        uint256 rateAdjustedAmount = FixedPoint.mulDown(defaultAmount, mockRate);

        vm.startPrank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onAddLiquidityCustom.selector,
                alice,
                [rateAdjustedAmount, defaultAmount].toMemoryArray(), // maxAmountsIn
                defaultAmount, // minBptOut
                [rateAdjustedAmount, defaultAmount].toMemoryArray(), // liveBalancesScaled18
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
                [balances.balancesLiveScaled18[0], balances.balancesLiveScaled18[1]].toMemoryArray(),
                0, // tokenOutIndex
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

        uint256 rateAdjustedAmountOut = FixedPoint.mulDown(defaultAmount, mockRate);

        PoolData memory balances = vault.computePoolDataUpdatingBalancesAndFees(address(pool), Rounding.ROUND_DOWN);

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolLiquidity.onRemoveLiquidityCustom.selector,
                alice,
                defaultAmount, // maxBptAmountIn
                [rateAdjustedAmountOut, defaultAmount].toMemoryArray(), // minAmountsOut
                [balances.balancesLiveScaled18[0], balances.balancesLiveScaled18[1]].toMemoryArray(),
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
