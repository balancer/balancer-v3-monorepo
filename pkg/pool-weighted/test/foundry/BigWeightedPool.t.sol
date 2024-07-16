// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig, PoolConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { WeightedMath } from "@balancer-labs/v3-solidity-utils/contracts/math/WeightedMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { PoolConfigBits } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

contract BigWeightedPoolTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 constant DEFAULT_SWAP_FEE = 1e16; // 1%

    WeightedPoolFactory factory;

    uint256 constant TOKEN_AMOUNT = 1e3 * 1e18;
    uint256 constant TOKEN_AMOUNT_IN = 1 * 1e18;

    uint256 constant DELTA = 9e7;

    WeightedPool internal weightedPool;
    IERC20[] internal bigPoolTokens;
    uint256[] internal weights;
    uint256[] internal initAmounts;
    uint256 internal bptAmountOut;
    uint256 internal numTokens;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        weightedPool = WeightedPool(pool);
    }

    function createPool() internal override returns (address) {
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        numTokens = vault.getMaximumPoolTokens();
        bigPoolTokens = new IERC20[](numTokens);
        weights = new uint256[](numTokens);
        initAmounts = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            bigPoolTokens[i] = createERC20(string.concat("TKN", Strings.toString(i)), 18);
            ERC20TestToken(address(bigPoolTokens[i])).mint(lp, poolInitAmount);
            weights[i] = 1e18 / numTokens;
            initAmounts[i] = poolInitAmount;
        }

        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(bigPoolTokens),
                weights,
                roleAccounts,
                DEFAULT_SWAP_FEE,
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), "Big weighted pool");

        _approveForPool(IERC20(address(newPool)));

        // Get the sorted list of tokens.
        bigPoolTokens = vault.getPoolTokens(address(newPool));

        return address(newPool);
    }

    function _approveForSender() internal {
        for (uint256 i = 0; i < bigPoolTokens.length; ++i) {
            bigPoolTokens[i].approve(address(permit2), type(uint256).max);
            permit2.approve(address(bigPoolTokens[i]), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(bigPoolTokens[i]), address(batchRouter), type(uint160).max, type(uint48).max);
        }
    }

    function _approveForPool(IERC20 bpt) internal {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);

            _approveForSender();

            bpt.approve(address(router), type(uint256).max);
            bpt.approve(address(batchRouter), type(uint256).max);

            IERC20(bpt).approve(address(permit2), type(uint256).max);
            permit2.approve(address(bpt), address(router), type(uint160).max, type(uint48).max);
            permit2.approve(address(bpt), address(batchRouter), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }
    }

    function initPool() internal override {
        vm.startPrank(lp);
        bptAmountOut = _initPool(
            pool,
            initAmounts,
            // Account for the precision loss
            TOKEN_AMOUNT - DELTA
        );
        vm.stopPrank();
    }

    function testPoolAddress() public view {
        address calculatedPoolAddress = factory.getDeploymentAddress(ZERO_BYTES32);
        assertEq(address(weightedPool), calculatedPoolAddress);
    }

    function testPoolPausedState() public view {
        (bool paused, uint256 pauseWindow, uint256 bufferPeriod, address pauseManager) = vault.getPoolPausedState(
            address(pool)
        );

        assertFalse(paused, "Vault should not be paused initially");
        assertApproxEqAbs(pauseWindow, START_TIMESTAMP + 365 days, 1, "Pause window period mismatch");
        assertApproxEqAbs(bufferPeriod, START_TIMESTAMP + 365 days + 30 days, 1, "Pause buffer period mismatch");
        assertEq(pauseManager, address(0), "Pause manager should be 0");
    }

    function testInitialize() public view {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < numTokens; ++i) {
            // Tokens are transferred from lp
            assertEq(
                defaultBalance - bigPoolTokens[i].balanceOf(lp),
                TOKEN_AMOUNT,
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertEq(
                bigPoolTokens[i].balanceOf(address(vault)),
                TOKEN_AMOUNT,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool
            assertEq(balances[i], TOKEN_AMOUNT, string.concat("Pool: Wrong token balance for ", Strings.toString(i)));
        }

        // should mint correct amount of BPT tokens
        // Account for the precision loss
        assertApproxEqAbs(weightedPool.balanceOf(lp), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, TOKEN_AMOUNT, DELTA, "Wrong bptAmountOut");
    }

    /*function testAddLiquidity() public {
        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(TOKEN_AMOUNT)].toMemoryArray();
        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, DAI_AMOUNT - DELTA, false, bytes(""));

        // Tokens are transferred from Bob
        assertEq(defaultBalance - usdc.balanceOf(bob), TOKEN_AMOUNT, "LP: Wrong USDC balance");
        assertEq(defaultBalance - dai.balanceOf(bob), DAI_AMOUNT, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), TOKEN_AMOUNT * 2, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT * 2, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], DAI_AMOUNT * 2, "Pool: Wrong DAI balance");
        assertEq(balances[1], TOKEN_AMOUNT * 2, "Pool: Wrong USDC balance");

        // should mint correct amount of BPT tokens
        assertApproxEqAbs(weightedPool.balanceOf(bob), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, DAI_AMOUNT, DELTA, "Wrong bptAmountOut");
    }

    function testRemoveLiquidity() public {
        vm.startPrank(bob);
        router.addLiquidityUnbalanced(
            address(pool),
            [uint256(DAI_AMOUNT), uint256(TOKEN_AMOUNT)].toMemoryArray(),
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
            [uint256(less(DAI_AMOUNT, 1e4)), uint256(less(TOKEN_AMOUNT, 1e4))].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        // Tokens are transferred to Bob
        assertApproxEqAbs(usdc.balanceOf(bob), defaultBalance, DELTA, "LP: Wrong USDC balance");
        assertApproxEqAbs(dai.balanceOf(bob), defaultBalance, DELTA, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertApproxEqAbs(usdc.balanceOf(address(vault)), TOKEN_AMOUNT, DELTA, "Vault: Wrong USDC balance");
        assertApproxEqAbs(dai.balanceOf(address(vault)), DAI_AMOUNT, DELTA, "Vault: Wrong DAI balance");

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        assertApproxEqAbs(balances[0], DAI_AMOUNT, DELTA, "Pool: Wrong DAI balance");
        assertApproxEqAbs(balances[1], TOKEN_AMOUNT, DELTA, "Pool: Wrong USDC balance");

        // amountsOut are correct
        assertApproxEqAbs(amountsOut[0], DAI_AMOUNT, DELTA, "Wrong DAI AmountOut");
        assertApproxEqAbs(amountsOut[1], TOKEN_AMOUNT, DELTA, "Wrong USDC AmountOut");

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
            less(TOKEN_AMOUNT_OUT, 1e3),
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(usdc.balanceOf(bob), defaultBalance + amountCalculated, "LP: Wrong USDC balance");
        assertEq(dai.balanceOf(bob), defaultBalance - DAI_AMOUNT_IN, "LP: Wrong DAI balance");

        // Tokens are stored in the Vault
        assertEq(usdc.balanceOf(address(vault)), TOKEN_AMOUNT - amountCalculated, "Vault: Wrong USDC balance");
        assertEq(dai.balanceOf(address(vault)), DAI_AMOUNT + DAI_AMOUNT_IN, "Vault: Wrong DAI balance");

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        (uint256 daiIdx, uint256 usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        assertEq(balances[daiIdx], DAI_AMOUNT + DAI_AMOUNT_IN, "Pool: Wrong DAI balance");
        assertEq(balances[usdcIdx], TOKEN_AMOUNT - amountCalculated, "Pool: Wrong USDC balance");
    }

    function testGetBptRate() public {
        uint256 totalSupply = bptAmountOut + MIN_BPT;
        uint256 weightedInvariant = WeightedMath.computeInvariant(weights, [DAI_AMOUNT, TOKEN_AMOUNT].toMemoryArray());
        uint256 expectedRate = weightedInvariant.divDown(totalSupply);
        uint256 actualRate = IRateProvider(address(pool)).getRate();
        assertEq(actualRate, expectedRate, "Wrong rate");

        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), 0].toMemoryArray();
        vm.prank(bob);
        uint256 addLiquidityBptAmountOut = router.addLiquidityUnbalanced(address(pool), amountsIn, 0, false, bytes(""));

        totalSupply += addLiquidityBptAmountOut;
        weightedInvariant = WeightedMath.computeInvariant(weights, [2 * DAI_AMOUNT, TOKEN_AMOUNT].toMemoryArray());

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

        uint256[] memory amountsIn = [uint256(1e2 * 1e18), uint256(TOKEN_AMOUNT)].toMemoryArray();
        vm.prank(bob);

        router.addLiquidityUnbalanced(address(pool), amountsIn, 0, false, bytes(""));
    }

    function testMinimumSwapFee() public view {
        assertEq(weightedPool.getMinimumSwapFeePercentage(), MIN_SWAP_FEE, "Minimum swap fee mismatch");
    }

    function testMaximumSwapFee() public view {
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
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
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
    }*/
}
