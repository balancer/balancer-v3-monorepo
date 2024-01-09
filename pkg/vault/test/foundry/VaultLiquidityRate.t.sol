// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolLiquidity } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolLiquidity.sol";
import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

import { VaultUtils } from "./utils/VaultUtils.sol";

contract VaultLiquidityWithRatesTest is VaultUtils {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        VaultUtils.setUp();
        rateProvider.mockRate(mockRate);
    }

    function createPool() internal override returns (address) {
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProvider = new RateProviderMock();
        rateProviders[0] = rateProvider;

        return
            address(new PoolMock(
                vault,
                "ERC20 Pool",
                "ERC20POOL",
                [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
                rateProviders,
                true,
                365 days,
                address(0)
            ));
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

        router.addLiquiditySingleTokenExactOut(
            address(pool),
            wsteth,
            defaultAmount,
            defaultAmount,
            false,
            bytes("")
        );
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

        PoolData memory balances = vault.getPoolData(address(pool), Rounding.ROUND_DOWN);
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

        router.removeLiquiditySingleTokenExactIn(
            address(pool),
            bptAmountIn,
            wsteth,
            defaultAmount,
            false,
            bytes("")
        );
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

        PoolData memory balances = vault.getPoolData(address(pool), Rounding.ROUND_DOWN);

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
