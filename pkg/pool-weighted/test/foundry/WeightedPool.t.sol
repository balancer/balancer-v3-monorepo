// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { VaultUtils } from "vault/test/foundry/utils/VaultUtils.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

contract WeightedPoolTest is VaultUtils {
    using ArrayHelpers for *;

    WeightedPoolFactory factory;

    uint256 constant USDC_AMOUNT = 1e3 * 1e18;
    uint256 constant DAI_AMOUNT = 1e3 * 1e18;

    uint256 constant DAI_AMOUNT_IN = 1 * 1e18;
    uint256 constant USDC_AMOUNT_OUT = 1 * 1e18;

    uint256 constant DELTA = 1e9;

    bytes32 constant ZERO_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000000;

    WeightedPool internal weightedPool;
    uint256 internal bptAmountOut;

    function setUp() public virtual override {
        VaultUtils.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new WeightedPoolFactory(vault, 365 days);
        weightedPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                new IRateProvider[](2),
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                ZERO_BYTES32
            )
        );
        return address(weightedPool);
    }

    function initPool() internal override {
        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(lp);
        bptAmountOut = router.initialize(
            pool,
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            amountsIn,
            // Account for the precision less
            DAI_AMOUNT - DELTA - 1e6,
            false,
            bytes("")
        );
    }

    function testPoolPausedState() public {
        (bool paused, uint256 pauseWindow, uint256 bufferPeriod, address pauseManager) = vault.getPoolPausedState(
            address(pool)
        );

        assertFalse(paused);
        assertApproxEqAbs(pauseWindow, 365 days, 1);
        assertApproxEqAbs(bufferPeriod, 365 days + 90 days, 1);
        assertEq(pauseManager, address(0));
    }

    function testInitialize() public {
        // Tokens are transferred from lp
        assertEq(defaultBalance - usdc.balanceOf(lp), USDC_AMOUNT);
        assertEq(defaultBalance - dai.balanceOf(lp), DAI_AMOUNT);

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), USDC_AMOUNT);
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT);

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT);
        assertEq(balances[1], USDC_AMOUNT);

        // should mint correct amount of BPT tokens
        // Account for the precision less
        assertApproxEqAbs(weightedPool.balanceOf(lp), bptAmountOut, DELTA);
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT, DELTA);
    }

    function testAddLiquidity() public {
        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, DAI_AMOUNT - DELTA, false, bytes(""));

        // Tokens are transferred from Bob
        assertEq(defaultBalance - usdc.balanceOf(bob), USDC_AMOUNT);
        assertEq(defaultBalance - dai.balanceOf(bob), DAI_AMOUNT);

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), USDC_AMOUNT * 2);
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT * 2);

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT * 2);
        assertEq(balances[1], USDC_AMOUNT * 2);

        // should mint correct amount of BPT tokens
        assertApproxEqAbs(weightedPool.balanceOf(bob), bptAmountOut, DELTA);
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT, DELTA);
    }

    function testRemoveLiquidity() public {
        vm.startPrank(bob);
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            DAI_AMOUNT - DELTA,
            false,
            bytes("")
        );

        weightedPool.approve(address(vault), type(uint256).max);

        uint256 bobBptBalance = weightedPool.balanceOf(bob);
        uint256 bptAmountIn = bobBptBalance;

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            [uint256(less(DAI_AMOUNT, 1e4)), uint256(less(USDC_AMOUNT, 1e4))].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        // Tokens are transferred to Bob
        assertApproxEqAbs(usdc.balanceOf(bob), defaultBalance, DELTA, "USDC user balance is invalid");
        assertApproxEqAbs(dai.balanceOf(bob), defaultBalance, DELTA, "DAI user balance is invalid");

        // Tokens are stored in the Vault
        assertApproxEqAbs(usdc.balanceOf(address(vault)), USDC_AMOUNT, DELTA, "USDC vault balance is invalid");
        assertApproxEqAbs(dai.balanceOf(address(vault)), DAI_AMOUNT, DELTA, "DAI vault balance is invalid");

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertApproxEqAbs(balances[0], DAI_AMOUNT, DELTA, "USDC pool balance is invalid");
        assertApproxEqAbs(balances[1], USDC_AMOUNT, DELTA, "DAI pool balance is invalid");

        // amountsOut are correct
        assertApproxEqAbs(amountsOut[0], DAI_AMOUNT, DELTA);
        assertApproxEqAbs(amountsOut[1], USDC_AMOUNT, DELTA);

        // should mint correct amount of BPT tokens
        assertEq(weightedPool.balanceOf(bob), 0);
        assertEq(bobBptBalance, bptAmountIn);
    }

    function testSwap() public {
        vm.prank(bob);
        uint256 amountCalculated = router.swapExactIn(
            address(pool),
            dai,
            usdc,
            DAI_AMOUNT_IN,
            less(USDC_AMOUNT_OUT, 1e3),
            type(uint256).max,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(usdc.balanceOf(bob), defaultBalance + amountCalculated);
        assertEq(dai.balanceOf(bob), defaultBalance - DAI_AMOUNT_IN);

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), USDC_AMOUNT - amountCalculated);
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT + DAI_AMOUNT_IN);

        // Tokens are deposited to the pool
        (, uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT + DAI_AMOUNT_IN);
        assertEq(balances[1], USDC_AMOUNT - amountCalculated);
    }

    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }

    function testAddLiquidityUnbalanced() public {
        authorizer.grantRole(vault.getActionId(IVault.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), 10e16);

        uint256[] memory amountsIn = [uint256(1e2 * 1e18), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(bob);

        router.addLiquidityUnbalanced(address(pool), amountsIn, 0, false, bytes(""));
    }
}
