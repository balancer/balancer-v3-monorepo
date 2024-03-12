// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

contract WeightedPoolSwaps is BaseVaultTest {
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

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Set protocol fee
        authorizer.grantRole(vault.getActionId(IVaultMain.setProtocolSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setProtocolSwapFeePercentage(50e16); // 50%
    }

    function createPool() internal override returns (address) {
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);
        rateProviders.push(new RateProviderMock());
        rateProviders.push(new RateProviderMock());

        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);

        wsteth.mint(bob, initialFunds);
        dai.mint(bob, initialFunds);

        wsteth.mint(alice, initialFunds);
        dai.mint(alice, initialFunds);

        weightedPoolWithRate = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
                rateProviders,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                bytes32(0)
            )
        );

        weightedPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
                new IRateProvider[](2),
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
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
        authorizer.grantRole(vault.getActionId(IVaultMain.setStaticSwapFeePercentage.selector), alice);

        for (uint256 index = 0; index < pools.length; index++) {
            vm.prank(alice);
            router.initialize(
                pools[index],
                [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
                [initializeAmount, initializeAmount].toMemoryArray(),
                0,
                false,
                bytes("")
            );

            vm.prank(alice);
            vault.setStaticSwapFeePercentage(pool, 1e16); // 1%
        }
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
            uint256 amountOut = router.swapExactIn(pool, dai, wsteth, amountIn, 0, MAX_UINT256, false, bytes(""));

            router.swapExactIn(pool, wsteth, dai, amountOut, 0, MAX_UINT256, false, bytes(""));
        }
        vm.stopPrank();
    }

    function _testSwapExactOut(address pool) internal {
        uint256 amountOut = maxSwapAmount;

        vm.startPrank(bob);
        for (uint256 i = 0; i < swapTimes; ++i) {
            uint256 amountIn = router.swapExactOut(
                pool,
                dai,
                wsteth,
                amountOut,
                MAX_UINT256,
                MAX_UINT256,
                false,
                bytes("")
            );

            router.swapExactOut(pool, wsteth, dai, amountIn, MAX_UINT256, MAX_UINT256, false, bytes(""));
        }
        vm.stopPrank();
    }
}
