// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

contract WeightedPoolTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%

    WeightedPoolFactory factory;

    uint256 constant USDC_AMOUNT = 1e3 * 1e18;
    uint256 constant DAI_AMOUNT = 1e3 * 1e18;

    uint256 constant DAI_AMOUNT_IN = 1 * 1e18;
    uint256 constant USDC_AMOUNT_OUT = 1 * 1e18;

    uint256 constant DELTA = 1e9;

    WeightedPool internal weightedPool;
    uint256[] internal weights;
    uint256 internal bptAmountOut;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        weightedPool = WeightedPool(pool);
    }

    function _createPool(address[] memory tokens, string memory label) internal virtual override returns (address) {
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        weights = [uint256(0.50e18), uint256(0.50e18)].toMemoryArray();

        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(tokens.asIERC20()),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE,
                poolHooksContract,
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }

    function initPool() internal override {
        vm.startPrank(lp);
        bptAmountOut = _initPool(
            pool,
            [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray(),
            // Account for the precision loss
            DAI_AMOUNT - DELTA - 1e6
        );
        vm.stopPrank();
    }

    function testPoolAddress() public {
        address calculatedPoolAddress = factory.getDeploymentAddress(ZERO_BYTES32);
        assertEq(address(weightedPool), calculatedPoolAddress);
    }

    function testPoolPausedState() public {
        (bool paused, uint256 pauseWindow, uint256 bufferPeriod, address pauseManager) = vault.getPoolPausedState(
            address(pool)
        );

        assertFalse(paused, "Vault should not be paused initially");
        assertApproxEqAbs(pauseWindow, START_TIMESTAMP + 365 days, 1, "Pause window period mismatch");
        assertApproxEqAbs(bufferPeriod, START_TIMESTAMP + 365 days + 30 days, 1, "Pause buffer period mismatch");
        assertEq(pauseManager, address(0), "Pause manager should be 0");
    }

    function testInitialize() public {
        // Tokens are transferred from lp
        assertEq(defaultBalance - usdc.balanceOf(lp), USDC_AMOUNT, "LP: Wrong USDC balance");
        assertEq(defaultBalance - dai.balanceOf(lp), DAI_AMOUNT, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), USDC_AMOUNT, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT, "Pool: Wrong DAI balance");
        assertEq(balances[1], USDC_AMOUNT, "Pool: Wrong USDC balance");

        // should mint correct amount of BPT tokens
        // Account for the precision loss
        assertApproxEqAbs(weightedPool.balanceOf(lp), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT, DELTA, "Wrong bptAmountOut");
    }

    function testAddLiquidity() public {
        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, DAI_AMOUNT - DELTA, false, bytes(""));

        // Tokens are transferred from Bob
        assertEq(defaultBalance - usdc.balanceOf(bob), USDC_AMOUNT, "LP: Wrong USDC balance");
        assertEq(defaultBalance - dai.balanceOf(bob), DAI_AMOUNT, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), USDC_AMOUNT * 2, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT * 2, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT * 2, "Pool: Wrong DAI balance");
        assertEq(balances[1], USDC_AMOUNT * 2, "Pool: Wrong USDC balance");

        // should mint correct amount of BPT tokens
        assertApproxEqAbs(weightedPool.balanceOf(bob), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT, DELTA, "Wrong bptAmountOut");
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

        weightedPool.approve(address(vault), MAX_UINT256);

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
        assertApproxEqAbs(usdc.balanceOf(bob), defaultBalance, DELTA, "LP: Wrong USDC balance");
        assertApproxEqAbs(dai.balanceOf(bob), defaultBalance, DELTA, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertApproxEqAbs(usdc.balanceOf(address(vault)), USDC_AMOUNT, DELTA, "Vault: Wrong USDC balance");
        assertApproxEqAbs(dai.balanceOf(address(vault)), DAI_AMOUNT, DELTA, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertApproxEqAbs(balances[0], DAI_AMOUNT, DELTA, "Pool: Wrong DAI balance");
        assertApproxEqAbs(balances[1], USDC_AMOUNT, DELTA, "Pool: Wrong USDC balance");

        // amountsOut are correct
        assertApproxEqAbs(amountsOut[0], DAI_AMOUNT, DELTA, "Wrong DAI AmountOut");
        assertApproxEqAbs(amountsOut[1], USDC_AMOUNT, DELTA, "Wrong USDC AmountOut");

        // should mint correct amount of BPT tokens
        assertEq(weightedPool.balanceOf(bob), 0, "LP: Wrong BPT balance");
        assertEq(bobBptBalance, bptAmountIn, "LP: Wrong bptAmountIn");
    }

    function testSwap() public {
        // Set swap fee to zero for this test.
        vault.manuallySetSwapFee(pool, 0);

        vm.prank(bob);
        uint256 amountCalculated = router.swapSingleTokenExactIn(
            address(pool),
            dai,
            usdc,
            DAI_AMOUNT_IN,
            less(USDC_AMOUNT_OUT, 1e3),
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(usdc.balanceOf(bob), defaultBalance + amountCalculated, "LP: Wrong USDC balance");
        assertEq(dai.balanceOf(bob), defaultBalance - DAI_AMOUNT_IN, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), USDC_AMOUNT - amountCalculated, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT + DAI_AMOUNT_IN, "Vault: Wrong DAI balance");

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        assertEq(balances[daiIdx], DAI_AMOUNT + DAI_AMOUNT_IN, "Pool: Wrong DAI balance");
        assertEq(balances[usdcIdx], USDC_AMOUNT - amountCalculated, "Pool: Wrong USDC balance");
    }

    function testGetBptRate() public {
        uint256 totalSupply = bptAmountOut + MIN_BPT;
        uint256 weightedInvariant = WeightedMath.computeInvariant(weights, [DAI_AMOUNT, USDC_AMOUNT].toMemoryArray());
        uint256 expectedRate = weightedInvariant.divDown(totalSupply);
        uint256 actualRate = IRateProvider(address(pool)).getRate();
        assertEq(actualRate, expectedRate, "Wrong rate");

        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), 0].toMemoryArray();
        vm.prank(bob);
        uint256 addLiquidityBptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, 0, false, bytes(""));

        totalSupply += addLiquidityBptAmountOut;
        weightedInvariant = WeightedMath.computeInvariant(weights, [2 * DAI_AMOUNT, USDC_AMOUNT].toMemoryArray());

        expectedRate = weightedInvariant.divDown(totalSupply);
        actualRate = IRateProvider(address(pool)).getRate();
        assertEq(actualRate, expectedRate, "Wrong rate after addLiquidity");
    }

    function less(uint256 amount, uint256 base) internal pure returns (uint256) {
        return (amount * (base - 1)) / base;
    }

    function testAddLiquidityUnbalanced() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), 10e16);

        uint256[] memory amountsIn = [uint256(1e2 * 1e18), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(bob);

        router.addLiquidityUnbalanced(address(pool), amountsIn, 0, false, bytes(""));
    }

    function testSupportsIERC165() public {
        assertTrue(weightedPool.supportsInterface(type(IERC165).interfaceId), "Pool does not support IERC165");
        assertTrue(
            weightedPool.supportsInterface(type(ISwapFeePercentageBounds).interfaceId),
            "Pool does not support ISwapFeePercentageBounds"
        );
    }

    function testMinimumSwapFee() public {
        assertEq(weightedPool.getMinimumSwapFeePercentage(), MIN_SWAP_FEE, "Minimum swap fee mismatch");
    }

    function testMaximumSwapFee() public {
        assertEq(weightedPool.getMaximumSwapFeePercentage(), MAX_SWAP_FEE, "Maximum swap fee mismatch");
    }

    function testFailSwapFeeTooLow() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        PoolRoleAccounts memory roleAccounts;
        tokens[0].token = IERC20(dai);
        tokens[1].token = IERC20(usdc);

        address lowFeeWeightedPool = factory.create(
            "ERC20 Pool",
            "ERC20POOL",
            tokens,
            [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
            roleAccounts,
            MIN_SWAP_FEE - 1, // Swap fee too low
            poolHooksContract,
            ZERO_BYTES32
        );

        factoryMock.registerTestPool(lowFeeWeightedPool, tokens);
    }

    function testSetSwapFeeTooLow() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooLow.selector);
        vault.setStaticSwapFeePercentage(address(pool), MIN_SWAP_FEE - 1);
    }

    function testSetSwapFeeTooHigh() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooHigh.selector);
        vault.setStaticSwapFeePercentage(address(pool), MAX_SWAP_FEE + 1);
    }
}
