// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

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
    uint256 constant swapFee = 1e16; // 1%

    uint256 wstethIdx;
    uint256 daiIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Set protocol fee
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setProtocolSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setProtocolSwapFeePercentage(50e16); // 50%
    }

    function createPool() internal override returns (address) {
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);
        rateProviders.push(new RateProviderMock());
        rateProviders.push(new RateProviderMock());
        (wstethIdx, daiIdx) = wsteth < dai ? (0, 1) : (1, 0);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[wstethIdx].token = IERC20(wsteth);
        tokens[daiIdx].token = IERC20(dai);

        wsteth.mint(bob, initialFunds);
        dai.mint(bob, initialFunds);

        wsteth.mint(alice, initialFunds);
        dai.mint(alice, initialFunds);

        weightedPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                tokens,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                swapFee,
                bytes32(uint256(1))
            )
        );

        tokens[0].tokenType = TokenType.WITH_RATE;
        tokens[1].tokenType = TokenType.WITH_RATE;
        tokens[wstethIdx].rateProvider = rateProviders[wstethIdx];
        tokens[daiIdx].rateProvider = rateProviders[daiIdx];

        weightedPoolWithRate = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                tokens,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                swapFee,
                bytes32(0)
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

        IERC20[] memory tokens = new IERC20[](2);
        tokens[wstethIdx] = wsteth;
        tokens[daiIdx] = dai;

        for (uint256 i = 0; i < pools.length; ++i) {
            vm.prank(alice);
            router.initialize(
                pools[i],
                tokens,
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
