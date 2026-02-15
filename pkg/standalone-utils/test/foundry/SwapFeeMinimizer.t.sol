// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { TokenConfig, PoolRoleAccounts, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { SwapFeeMinimizer } from "../../contracts/SwapFeeMinimizer/SwapFeeMinimizer.sol";
import {
    SwapFeeMinimizerFactory,
    PoolCreationParams,
    MinimizerParams
} from "../../contracts/SwapFeeMinimizer/SwapFeeMinimizerFactory.sol";

contract SwapFeeMinimizerTest is BaseVaultTest {
    SwapFeeMinimizerFactory factory;
    WeightedPoolFactory weightedPoolFactory;
    SwapFeeMinimizer minimizer;
    address testPool;

    address poolOwner = makeAddr("poolOwner");
    address normalUser = makeAddr("normalUser");

    uint256 constant MIN_SWAP_FEE = 0.001e16; // 0.001%
    uint256 constant MAX_SWAP_FEE = 10e16; // 10%
    uint256 constant NORMAL_SWAP_FEE = 1e16; // 1%
    uint256 constant LIQUIDITY_AMOUNT_DAI = 1000e18;
    uint256 constant LIQUIDITY_AMOUNT_USDC = 1000e6;

    // Pool configuration
    string poolName = "Fee Minimizer Test Pool";
    string poolSymbol = "FMTP";
    IERC20 outputToken;

    function setUp() public override {
        super.setUp();

        // Deploy factory and pool factory
        factory = new SwapFeeMinimizerFactory(router, vault, permit2);
        weightedPoolFactory = new WeightedPoolFactory(vault, 365 days, "Factory v1", "Pool v1");

        outputToken = dai;

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0] = TokenConfig({
            token: dai,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });
        tokens[1] = TokenConfig({
            token: usdc,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        uint256[] memory weights = new uint256[](2);
        // 50/50 pool
        weights[0] = 50e16;
        weights[1] = 50e16;

        PoolCreationParams memory poolParams = PoolCreationParams({
            name: poolName,
            symbol: poolSymbol,
            tokens: tokens,
            normalizedWeights: weights,
            swapFeePercentage: NORMAL_SWAP_FEE,
            poolHooksContract: address(0),
            enableDonation: false,
            disableUnbalancedLiquidity: false
        });

        IERC20[] memory inputTokens = new IERC20[](1);
        inputTokens[0] = usdc;

        MinimizerParams memory minimizerParams = MinimizerParams({
            inputTokens: inputTokens,
            outputToken: outputToken,
            initialOwner: poolOwner,
            minimalFee: MIN_SWAP_FEE
        });

        (testPool, minimizer) = factory.deployWeightedPoolWithMinimizer(
            poolParams,
            minimizerParams,
            weightedPoolFactory,
            keccak256("test")
        );

        _setupPoolLiquidity();
    }

    function _setupPoolLiquidity() internal {
        vm.startPrank(admin);
        dai.mint(address(this), LIQUIDITY_AMOUNT_DAI);
        usdc.mint(address(this), LIQUIDITY_AMOUNT_USDC);
        vm.stopPrank();

        // Approve tokens from test contract to router to seed pool
        dai.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        dai.approve(address(permit2), type(uint256).max);
        usdc.approve(address(permit2), type(uint256).max);
        permit2.approve(address(dai), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);

        // Initialize pool
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = LIQUIDITY_AMOUNT_DAI / 2;
        amountsIn[1] = LIQUIDITY_AMOUNT_USDC / 2;

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = dai;
        tokens[1] = usdc;

        router.initialize(testPool, tokens, amountsIn, 0, false, "");

        vm.startPrank(admin);
        dai.mint(poolOwner, 100e18);
        dai.mint(normalUser, 100e18);
        usdc.mint(poolOwner, 100e6);
        usdc.mint(normalUser, 100e6);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        dai.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        dai.approve(address(minimizer), type(uint256).max);
        usdc.approve(address(minimizer), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(normalUser);
        dai.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        dai.approve(address(permit2), type(uint256).max);
        usdc.approve(address(permit2), type(uint256).max);

        // permit2 approvals needed for **router** actions rather than the minimizer for normalUser
        permit2.approve(address(dai), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function testSwapExactInWithMinimizedFees() public {
        // Record initial fee
        uint256 initialFee = vault.getStaticSwapFeePercentage(testPool);
        assertEq(initialFee, NORMAL_SWAP_FEE);

        vm.prank(poolOwner);
        uint256 amountOut = minimizer.swapSingleTokenExactIn(testPool, usdc, dai, 10e6, 0, block.timestamp, false, "");

        uint256 finalFee = vault.getStaticSwapFeePercentage(testPool);
        assertEq(finalFee, NORMAL_SWAP_FEE);
        assertTrue(amountOut > 0);
    }

    function testSwapExactOutWithMinimizedFees() public {
        uint256 initialFee = vault.getStaticSwapFeePercentage(testPool);
        assertEq(initialFee, NORMAL_SWAP_FEE);

        vm.prank(poolOwner);
        uint256 amountIn = minimizer.swapSingleTokenExactOut(
            testPool,
            usdc,
            dai,
            5e18,
            10e6,
            block.timestamp,
            false,
            ""
        );

        uint256 finalFee = vault.getStaticSwapFeePercentage(testPool);
        assertEq(finalFee, NORMAL_SWAP_FEE);
        assertTrue(amountIn > 0);
    }

    function testFeeMinimizationDuringSwap() public {
        uint256 swapAmount = 10e6;
        uint256 snapshot = vm.snapshot();

        // compare output from normal user via router to poolOwner via minimizer
        vm.prank(normalUser);
        uint256 normalFeeResult = router.swapSingleTokenExactIn(
            testPool,
            usdc,
            dai,
            swapAmount,
            0,
            block.timestamp,
            false,
            ""
        );

        vm.revertTo(snapshot);
        vm.prank(poolOwner);
        uint256 minimizedFeeResult = minimizer.swapSingleTokenExactIn(
            testPool,
            usdc,
            dai,
            swapAmount,
            0,
            block.timestamp,
            false,
            ""
        );

        assertGt(minimizedFeeResult, normalFeeResult);

        // Check that the swap amounts without fees charged are roughly equivalent
        uint256 untaxedSwapAmountMinimized = (minimizedFeeResult * 1e18) / (1e18 - MIN_SWAP_FEE);
        uint256 untaxedSwapAmountNormal = (normalFeeResult * 1e18) / (1e18 - NORMAL_SWAP_FEE);
        uint256 positiveNumerator = SignedMath.abs(
            int256(untaxedSwapAmountMinimized) - int256(untaxedSwapAmountNormal)
        );
        uint256 pctError = (positiveNumerator * 1e18) / untaxedSwapAmountNormal;
        uint256 smallError = 0.1e16; // 0.1%
        assertLt(pctError, smallError);
    }

    function testFeeRestoresOnSwapRevert() public {
        uint256 initialFee = vault.getStaticSwapFeePercentage(testPool);

        // Induce a swap revert with expired deadline deadline
        vm.prank(poolOwner);
        try
            minimizer.swapSingleTokenExactIn(
                testPool,
                usdc,
                dai,
                10e6,
                0,
                block.timestamp - 1, // Deadline in past
                false,
                ""
            )
        {
            fail();
        } catch {
            // Do nothing
        }

        // Fee is restored to normal
        uint256 finalFee = vault.getStaticSwapFeePercentage(testPool);
        assertEq(finalFee, initialFee);
    }

    function testOwnerCanSetSwapFee() public {
        uint256 newFee = 0.005e16; // 0.005%
        vm.prank(poolOwner);

        minimizer.setSwapFeePercentage(newFee);
        assertEq(vault.getStaticSwapFeePercentage(testPool), newFee);
    }

    function testNonOwnerCannotSetSwapFee() public {
        uint256 newFee = 0.005e16; // 0.005%
        vm.prank(normalUser);

        // expect revert message from ownable
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, normalUser));
        minimizer.setSwapFeePercentage(newFee);
    }

    function testConcurrentUsage() public {
        // Normal users can swap via router
        vm.prank(normalUser);
        uint256 normalResult = router.swapSingleTokenExactIn(
            testPool,
            usdc,
            dai,
            5e6, // 5 USDC
            0,
            block.timestamp,
            false,
            ""
        );

        // Owner swap with minimizer
        vm.prank(poolOwner);
        uint256 minimizerResult = minimizer.swapSingleTokenExactIn(
            testPool,
            usdc,
            dai,
            5e6, // 5 USDC
            0,
            block.timestamp,
            false,
            ""
        );

        // Both swaps work, fee is nominal
        assertTrue(normalResult > 0);
        assertTrue(minimizerResult > 0);
        assertEq(vault.getStaticSwapFeePercentage(testPool), NORMAL_SWAP_FEE);
    }

    function testInvalidOutputToken() public {
        bytes memory expectedRevert = abi.encodeWithSelector(
            SwapFeeMinimizer.InvalidOutputToken.selector,
            dai, // expected
            usdc // actual
        );

        // Verify on ExactIn
        vm.prank(poolOwner);
        vm.expectRevert(expectedRevert);
        minimizer.swapSingleTokenExactIn(
            testPool,
            dai,
            usdc, // Invalid output token
            10e18,
            0,
            block.timestamp,
            false,
            ""
        );

        // Verify on ExactOut
        vm.prank(poolOwner);
        vm.expectRevert(expectedRevert);
        minimizer.swapSingleTokenExactOut(
            testPool,
            dai,
            usdc, // Invalid output token
            5e6,
            type(uint256).max,
            block.timestamp,
            false,
            ""
        );
    }

    function testOnlyPoolModifierReverts() public {
        address wrongPool = makeAddr("wrongPool");

        // Verify on ExactIn
        vm.prank(poolOwner);
        vm.expectRevert(SwapFeeMinimizer.InvalidPool.selector);
        minimizer.swapSingleTokenExactIn(wrongPool, usdc, dai, 10e6, 0, block.timestamp, false, "");

        // Verify on ExactOut
        vm.prank(poolOwner);
        vm.expectRevert(SwapFeeMinimizer.InvalidPool.selector);
        minimizer.swapSingleTokenExactOut(wrongPool, usdc, dai, 5e18, 100e6, block.timestamp, false, "");
    }

    function testPreExistingTokenBalance() public {
        // Give the contract some pre-existing DAI tokens
        uint256 preExistingBalance = 50e18;
        vm.prank(admin);
        dai.mint(address(minimizer), preExistingBalance);

        uint256 contractBalanceBefore = dai.balanceOf(address(minimizer));
        assertEq(contractBalanceBefore, preExistingBalance);

        uint256 userBalanceBefore = dai.balanceOf(poolOwner);

        vm.prank(poolOwner);
        uint256 amountOut = minimizer.swapSingleTokenExactIn(testPool, usdc, dai, 10e6, 0, block.timestamp, false, "");

        uint256 userBalanceAfter = dai.balanceOf(poolOwner);
        uint256 contractBalanceAfter = dai.balanceOf(address(minimizer));

        // User gets amountOut
        assertEq(userBalanceAfter - userBalanceBefore, amountOut);

        // Contract pre-existing balance unchanged
        assertEq(contractBalanceAfter, preExistingBalance);

        // Verify swap worked
        assertGt(amountOut, 0);
    }

    function testFeeSettingBounds() public {
        // Success on MIN
        vm.prank(poolOwner);
        minimizer.setSwapFeePercentage(MIN_SWAP_FEE);
        assertEq(vault.getStaticSwapFeePercentage(testPool), MIN_SWAP_FEE);

        // Success on MAX
        vm.prank(poolOwner);
        minimizer.setSwapFeePercentage(MAX_SWAP_FEE);
        assertEq(vault.getStaticSwapFeePercentage(testPool), MAX_SWAP_FEE);

        // Fail on MIN - 1
        vm.prank(poolOwner);
        vm.expectRevert();
        minimizer.setSwapFeePercentage(MIN_SWAP_FEE - 1);

        // Fail on MAX + 1
        vm.prank(poolOwner);
        vm.expectRevert();
        minimizer.setSwapFeePercentage(MAX_SWAP_FEE + 1);

        // Success on NORMAL
        vm.prank(poolOwner);
        minimizer.setSwapFeePercentage(NORMAL_SWAP_FEE);
    }
}
