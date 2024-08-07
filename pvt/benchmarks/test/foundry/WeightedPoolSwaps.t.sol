// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

contract WeightedPoolSwaps is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    IRateProvider[] rateProviders;
    WeightedPool weightedPool;
    WeightedPool weightedPoolWithRate;
    WeightedPoolFactory factory;

    uint256 constant minSwapAmount = 1e18;
    uint256 constant maxSwapAmount = 1e3 * 1e18;
    uint256 constant initializeAmount = maxSwapAmount * 100_000;
    uint256 constant initialFunds = initializeAmount * 100e6;
    uint256 constant swapTimes = 5000;
    uint256 constant swapFee = 1e16; // 1%

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        IProtocolFeeController feeController = vault.getProtocolFeeController();
        IAuthentication feeControllerAuth = IAuthentication(address(feeController));

        // Set protocol fee
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            alice
        );
        vm.prank(alice);
        feeController.setGlobalProtocolSwapFeePercentage(50e16); // 50%
    }

    function createPool() internal override returns (address) {
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        rateProviders.push(new RateProviderMock());
        rateProviders.push(new RateProviderMock());

        wsteth.mint(bob, initialFunds);
        dai.mint(bob, initialFunds);

        wsteth.mint(alice, initialFunds);
        dai.mint(alice, initialFunds);

        PoolRoleAccounts memory poolRoleAccounts;

        weightedPoolWithRate = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig([address(dai), address(wsteth)].toMemoryArray().asIERC20(), rateProviders),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                poolRoleAccounts,
                swapFee,
                address(0),
                false,
                false,
                bytes32(0)
            )
        );

        weightedPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig([address(dai), address(wsteth)].toMemoryArray().asIERC20()),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                poolRoleAccounts,
                swapFee,
                address(0),
                false,
                false,
                bytes32(uint256(1))
            )
        );

        return address(weightedPool);
    }

    function initPool() internal override {
        address[] memory pools = new address[](2);
        pools[0] = address(weightedPool);
        pools[1] = address(weightedPoolWithRate);

        // Set pool swap fee
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);

        for (uint256 i = 0; i < pools.length; ++i) {
            vm.prank(alice);
            router.initialize(
                pools[i],
                [address(dai), address(wsteth)].toMemoryArray().asIERC20(),
                [initializeAmount, initializeAmount].toMemoryArray(),
                0,
                false,
                bytes("")
            );

            vm.prank(alice);
            vault.setStaticSwapFeePercentage(pool, 1e16); // 1%
        }
    }

    function testExactInSnapshot() public {
        uint256 amountIn = maxSwapAmount;

        vm.startPrank(bob);
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(weightedPool),
            dai,
            wsteth,
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        router.swapSingleTokenExactIn(address(weightedPool), wsteth, dai, amountOut, 0, MAX_UINT256, false, bytes(""));
        vm.stopPrank();
    }

    function testExactInWithRateSnapshot() public {
        uint256 amountIn = maxSwapAmount;

        vm.startPrank(bob);
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(weightedPoolWithRate),
            dai,
            wsteth,
            amountIn,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        router.swapSingleTokenExactIn(
            address(weightedPoolWithRate),
            wsteth,
            dai,
            amountOut,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testExactOutSnapshot() public {
        uint256 amountOut = maxSwapAmount;

        vm.startPrank(bob);
        uint256 amountIn = router.swapSingleTokenExactOut(
            address(weightedPool),
            dai,
            wsteth,
            amountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        router.swapSingleTokenExactOut(
            address(weightedPool),
            wsteth,
            dai,
            amountIn,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testExactOutWithRateSnapshot() public {
        uint256 amountOut = maxSwapAmount;

        vm.startPrank(bob);
        uint256 amountIn = router.swapSingleTokenExactOut(
            address(weightedPoolWithRate),
            dai,
            wsteth,
            amountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        router.swapSingleTokenExactOut(
            address(weightedPoolWithRate),
            wsteth,
            dai,
            amountIn,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testSwapExactInWithoutRate() public {
        _testSwapExactIn(address(weightedPool));
    }

    function testSwapExactOutWithoutRate() public {
        _testSwapExactOut(address(weightedPool));
    }

    function testSwapExactInWithRate() public {
        _testSwapExactIn(address(weightedPoolWithRate));
    }

    function testSwapExactOutWithRate() public {
        _testSwapExactOut(address(weightedPoolWithRate));
    }

    function _testSwapExactIn(address pool) internal {
        uint256 amountIn = maxSwapAmount;

        vm.startPrank(bob);
        for (uint256 i = 0; i < swapTimes; ++i) {
            uint256 amountOut = router.swapSingleTokenExactIn(
                pool,
                dai,
                wsteth,
                amountIn,
                0,
                MAX_UINT256,
                false,
                bytes("")
            );

            router.swapSingleTokenExactIn(pool, wsteth, dai, amountOut, 0, MAX_UINT256, false, bytes(""));
        }
        vm.stopPrank();
    }

    function _testSwapExactOut(address pool) internal {
        uint256 amountOut = maxSwapAmount;

        vm.startPrank(bob);
        for (uint256 i = 0; i < swapTimes; ++i) {
            uint256 amountIn = router.swapSingleTokenExactOut(
                pool,
                dai,
                wsteth,
                amountOut,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            );

            router.swapSingleTokenExactOut(pool, wsteth, dai, amountIn, MAX_UINT256, MAX_UINT256, false, bytes(""));
        }
        vm.stopPrank();
    }
}
