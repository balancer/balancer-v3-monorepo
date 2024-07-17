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
    uint256 constant TOKEN_AMOUNT_OUT = 1 * 1e18;

    uint256 constant DELTA = 9e7;
    uint256 constant TOKEN_DELTA = 1e4;

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
            // Use all 18-decimal tokens, for simplicity
            bigPoolTokens[i] = createERC20(string.concat("TKN", Strings.toString(i)), 18);
            ERC20TestToken(address(bigPoolTokens[i])).mint(lp, TOKEN_AMOUNT);
            ERC20TestToken(address(bigPoolTokens[i])).mint(bob, TOKEN_AMOUNT);
            weights[i] = 1e18 / numTokens;
            initAmounts[i] = TOKEN_AMOUNT;
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
                TOKEN_AMOUNT - bigPoolTokens[i].balanceOf(lp),
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

    function testAddLiquidity() public {
        uint256[] memory amountsIn = _getAmountsIn();

        vm.prank(bob);
        bptAmountOut = router.addLiquidityUnbalanced(
            address(pool),
            amountsIn,
            TOKEN_AMOUNT_IN - DELTA,
            false,
            bytes("")
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < numTokens; ++i) {
            // Tokens are transferred from Bob
            assertEq(
                TOKEN_AMOUNT - bigPoolTokens[i].balanceOf(bob),
                TOKEN_AMOUNT_IN,
                string.concat("Bob: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertEq(
                bigPoolTokens[i].balanceOf(address(vault)),
                TOKEN_AMOUNT + TOKEN_AMOUNT_IN,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool
            assertEq(
                balances[i],
                TOKEN_AMOUNT + TOKEN_AMOUNT_IN,
                string.concat("Pool: Wrong token balance for ", Strings.toString(i))
            );
        }

        // should mint correct amount of BPT tokens
        assertApproxEqAbs(weightedPool.balanceOf(bob), bptAmountOut, DELTA, "LP: Wrong bptAmountOut");
        assertApproxEqAbs(bptAmountOut, TOKEN_AMOUNT_IN, DELTA, "Wrong bptAmountOut");
    }

    function testRemoveLiquidity() public {
        uint256[] memory amountsIn = _getAmountsIn();

        vm.startPrank(bob);
        router.addLiquidityUnbalanced(address(pool), amountsIn, TOKEN_AMOUNT_IN - DELTA, false, bytes(""));

        uint256 bobBptBalance = weightedPool.balanceOf(bob);
        uint256 bptAmountIn = bobBptBalance;

        uint256[] memory minAmountsOut = _getMinAmountsOut();

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(pool),
            bptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        vm.stopPrank();

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        for (uint256 i = 0; i < numTokens; ++i) {
            // Tokens are transferred to Bob
            assertApproxEqAbs(
                bigPoolTokens[i].balanceOf(bob),
                TOKEN_AMOUNT,
                TOKEN_DELTA,
                string.concat("LP: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are stored in the Vault
            assertApproxEqAbs(
                bigPoolTokens[i].balanceOf(address(vault)),
                TOKEN_AMOUNT,
                TOKEN_DELTA,
                string.concat("Vault: Wrong token balance for ", Strings.toString(i))
            );

            // Tokens are deposited to the pool
            assertApproxEqAbs(
                balances[i],
                TOKEN_AMOUNT,
                TOKEN_DELTA,
                string.concat("Pool: Wrong amountIn for ", Strings.toString(i))
            );

            // amountsOut are correct
            assertApproxEqAbs(
                amountsOut[i],
                TOKEN_AMOUNT_IN,
                TOKEN_DELTA,
                string.concat("Pool: Wrong amountOut for ", Strings.toString(i))
            );
        }

        // should mint correct amount of BPT tokens
        assertEq(weightedPool.balanceOf(bob), 0, "LP: Wrong BPT balance");
        assertEq(bobBptBalance, bptAmountIn, "LP: Wrong bptAmountIn");
    }

    function testSwap() public {
        // Set swap fee to zero for this test.
        vault.manuallySetSwapFee(address(weightedPool), 0);

        uint256 tokenInIndex = 3;
        uint256 tokenOutIndex = 7;

        IERC20 tokenIn = bigPoolTokens[tokenInIndex];
        IERC20 tokenOut = bigPoolTokens[tokenOutIndex];

        vm.prank(bob);
        uint256 amountCalculated = router.swapSingleTokenExactIn(
            address(weightedPool),
            tokenIn,
            tokenOut,
            TOKEN_AMOUNT_IN,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );

        // Tokens are transferred from Bob
        assertEq(tokenOut.balanceOf(bob), TOKEN_AMOUNT + amountCalculated, "LP: Wrong tokenOut balance");
        assertEq(tokenIn.balanceOf(bob), TOKEN_AMOUNT - TOKEN_AMOUNT_IN, "LP: Wrong tokenIn balance");

        // Tokens are stored in the Vault
        assertEq(tokenOut.balanceOf(address(vault)), TOKEN_AMOUNT - amountCalculated, "Vault: Wrong tokenOut balance");
        assertEq(tokenIn.balanceOf(address(vault)), TOKEN_AMOUNT + TOKEN_AMOUNT_IN, "Vault: Wrong tokenIn balance");

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        assertEq(balances[tokenInIndex], TOKEN_AMOUNT + TOKEN_AMOUNT_IN, "Pool: Wrong tokenIn balance");
        assertEq(balances[tokenOutIndex], TOKEN_AMOUNT - amountCalculated, "Pool: Wrong tokenOut balance");
    }

    function testGetBptRate() public {
        uint256 totalSupply = bptAmountOut + MIN_BPT;
        uint256[] memory balances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            balances[i] = TOKEN_AMOUNT;
        }

        uint256 weightedInvariant = WeightedMath.computeInvariant(weights, balances);
        uint256 expectedRate = weightedInvariant.divDown(totalSupply);
        uint256 actualRate = IRateProvider(address(pool)).getRate();
        assertEq(actualRate, expectedRate, "Wrong rate");

        // Send in only one token
        uint256[] memory amountsIn = new uint256[](numTokens);
        amountsIn[0] = TOKEN_AMOUNT;

        vm.prank(bob);
        uint256 addLiquidityBptAmountOut = router.addLiquidityUnbalanced(
            address(weightedPool),
            amountsIn,
            0,
            false,
            bytes("")
        );

        totalSupply += addLiquidityBptAmountOut;
        balances[0] += TOKEN_AMOUNT;

        weightedInvariant = WeightedMath.computeInvariant(weights, balances);

        expectedRate = weightedInvariant.divDown(totalSupply);
        actualRate = IRateProvider(address(pool)).getRate();
        assertEq(actualRate, expectedRate, "Wrong rate after addLiquidity");
    }

    function testAddLiquidityUnbalanced() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(weightedPool), 10e16);

        uint256[] memory amountsIn = _getAmountsIn();
        amountsIn[0] *= 100;

        vm.prank(bob);

        router.addLiquidityUnbalanced(address(weightedPool), amountsIn, 0, false, bytes(""));
    }

    function testMinimumSwapFee() public view {
        assertEq(weightedPool.getMinimumSwapFeePercentage(), MIN_SWAP_FEE, "Minimum swap fee mismatch");
    }

    function testMaximumSwapFee() public view {
        assertEq(weightedPool.getMaximumSwapFeePercentage(), MAX_SWAP_FEE, "Maximum swap fee mismatch");
    }

    function _getAmountsIn() private view returns (uint256[] memory amountsIn) {
        amountsIn = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsIn[i] = TOKEN_AMOUNT_IN;
        }
    }

    function _getMinAmountsOut() private view returns (uint256[] memory amountsOut) {
        amountsOut = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            amountsOut[i] = TOKEN_AMOUNT_OUT - TOKEN_DELTA;
        }
    }
}
