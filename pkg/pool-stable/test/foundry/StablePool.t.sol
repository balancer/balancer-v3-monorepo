// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultMain.sol";
import { TokenConfig, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

contract StablePoolTest is BaseVaultTest {
    using ArrayHelpers for *;

    StablePoolFactory factory;

    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;
    uint256 constant TOKEN_AMOUNT_IN = 1 * 1e18;
    uint256 constant TOKEN_AMOUNT_OUT = 1 * 1e18;

    uint256 constant DELTA = 1e9;

    uint256 constant DEFAULT_AMP_FACTOR = 200;
    uint256 constant DEFAULT_SWAP_FEE = 0;

    StablePool internal stablePool;
    uint256 internal bptAmountOut;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new StablePoolFactory(IVault(address(vault)), 365 days);
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = IERC20(dai);
        tokens[1].token = IERC20(usdc);

        stablePool = StablePool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.sortTokenConfig(tokens),
                DEFAULT_AMP_FACTOR,
                DEFAULT_SWAP_FEE,
                ZERO_BYTES32
            )
        );
        return address(stablePool);
    }

    function initPool() internal override {
        uint256[] memory amountsIn = [uint256(TOKEN_AMOUNT), uint256(TOKEN_AMOUNT)].toMemoryArray();
        vm.prank(lp);
        bptAmountOut = router.initialize(
            pool,
            InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            amountsIn,
            // Account for the precision loss
            TOKEN_AMOUNT - DELTA - 1e6,
            false,
            bytes("")
        );
    }

    function testPoolPausedState() public {
        (bool paused, uint256 pauseWindow, uint256 bufferPeriod, address pauseManager) = vault.getPoolPausedState(
            address(pool)
        );

        assertFalse(paused);
        assertApproxEqAbs(pauseWindow, START_TIMESTAMP + 365 days, 1);
        assertApproxEqAbs(bufferPeriod, START_TIMESTAMP + 365 days + 30 days, 1);
        assertEq(pauseManager, address(0));
    }

    function testInitialize() public {
        // Tokens are transferred from lp
        assertEq(defaultBalance - usdc.balanceOf(lp), TOKEN_AMOUNT, "LP: Wrong USDC balance");
        assertEq(defaultBalance - dai.balanceOf(lp), TOKEN_AMOUNT, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), TOKEN_AMOUNT, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), TOKEN_AMOUNT, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], TOKEN_AMOUNT, "Pool: Wrong DAI balance");
        assertEq(balances[1], TOKEN_AMOUNT, "Pool: Wrong USDC balance");

        // should mint correct amount of BPT tokens
        // Account for the precision loss
        assertApproxEqAbs(stablePool.balanceOf(lp), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, TOKEN_AMOUNT * 2, DELTA, "Wrong bptAmountOut");
    }

    function testAddLiquidity() public {
        uint256[] memory amountsIn = [uint256(TOKEN_AMOUNT), uint256(TOKEN_AMOUNT)].toMemoryArray();
        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, TOKEN_AMOUNT - DELTA, false, bytes(""));

        // Tokens are transferred from Bob
        assertEq(defaultBalance - usdc.balanceOf(bob), TOKEN_AMOUNT, "LP: Wrong USDC balance");
        assertEq(defaultBalance - dai.balanceOf(bob), TOKEN_AMOUNT, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), TOKEN_AMOUNT * 2, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), TOKEN_AMOUNT * 2, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], TOKEN_AMOUNT * 2, "Pool: Wrong DAI balance");
        assertEq(balances[1], TOKEN_AMOUNT * 2, "Pool: Wrong USDC balance");

        // should mint correct amount of BPT tokens
        assertApproxEqAbs(stablePool.balanceOf(bob), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, TOKEN_AMOUNT * 2, DELTA, "Wrong bptAmountOut");
    }

    function testRemoveLiquidity() public {
        vm.startPrank(bob);
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(TOKEN_AMOUNT), uint256(TOKEN_AMOUNT)].toMemoryArray(),
            TOKEN_AMOUNT - DELTA,
            false,
            bytes("")
        );

        stablePool.approve(address(vault), MAX_UINT256);

        uint256 bobBptBalance = stablePool.balanceOf(bob);
        uint256 bptAmountIn = bobBptBalance;

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            [uint256(less(TOKEN_AMOUNT, 1e4)), uint256(less(TOKEN_AMOUNT, 1e4))].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        // Tokens are transferred to Bob
        assertApproxEqAbs(usdc.balanceOf(bob), defaultBalance, DELTA, "LP: Wrong USDC balance");
        assertApproxEqAbs(dai.balanceOf(bob), defaultBalance, DELTA, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertApproxEqAbs(usdc.balanceOf(address(vault)), TOKEN_AMOUNT, DELTA, "Vault: Wrong USDC balance");
        assertApproxEqAbs(dai.balanceOf(address(vault)), TOKEN_AMOUNT, DELTA, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertApproxEqAbs(balances[0], TOKEN_AMOUNT, DELTA, "Pool: Wrong DAI balance");
        assertApproxEqAbs(balances[1], TOKEN_AMOUNT, DELTA, "Pool: Wrong USDC balance");

        // amountsOut are correct
        assertApproxEqAbs(amountsOut[0], TOKEN_AMOUNT, DELTA, "Wrong DAI AmountOut");
        assertApproxEqAbs(amountsOut[1], TOKEN_AMOUNT, DELTA, "Wrong USDC AmountOut");

        // should mint correct amount of BPT tokens
        assertEq(stablePool.balanceOf(bob), 0, "LP: Wrong BPT balance");
        assertEq(bobBptBalance, bptAmountIn, "LP: Wrong bptAmountIn");
    }

    function testSwap() public {
        vm.prank(bob);
        uint256 amountCalculated = router.swapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            TOKEN_AMOUNT_IN,
            less(TOKEN_AMOUNT_OUT, 1e3),
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(usdc.balanceOf(bob), defaultBalance + amountCalculated, "LP: Wrong USDC balance");
        assertEq(dai.balanceOf(bob), defaultBalance - TOKEN_AMOUNT_IN, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), TOKEN_AMOUNT - amountCalculated, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), TOKEN_AMOUNT + TOKEN_AMOUNT_IN, "Vault: Wrong DAI balance");

        (, , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        assertEq(balances[daiIdx], TOKEN_AMOUNT + TOKEN_AMOUNT_IN, "Pool: Wrong DAI balance");
        assertEq(balances[usdcIdx], TOKEN_AMOUNT - amountCalculated, "Pool: Wrong USDC balance");
    }

    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }

    function testAddLiquidityUnbalanced() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), 10e16);

        uint256[] memory amountsIn = [uint256(1e2 * 1e18), uint256(TOKEN_AMOUNT)].toMemoryArray();
        vm.prank(bob);

        router.addLiquidityUnbalanced(address(pool), amountsIn, 0, false, bytes(""));
    }
}
