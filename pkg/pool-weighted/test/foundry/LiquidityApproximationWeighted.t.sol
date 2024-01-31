// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TokenConfig, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

contract LiquidityApproximationTest is BaseVaultTest {
    using ArrayHelpers for *;

    WeightedPool internal swapPool;
    WeightedPool internal liquidityPool;
    // Allows small delta to account for rounding
    uint256 internal delta = 1e12;
    uint256 internal maxAmount = 3e8 * 1e18;
    bytes32 constant ZERO_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000000;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = IERC20(dai);
        tokens[1].token = IERC20(usdc);

        liquidityPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                tokens,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                ZERO_BYTES32
            )
        );
        vm.label(address(liquidityPool), "liquidityPool");

        swapPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                tokens,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                ZERO_BYTES32
            )
        );
        vm.label(address(swapPool), "swapPool");

        return address(liquidityPool);
    }

    function initPool() internal override {
        poolInitAmount = 1e9 * 1e18;
        // poolInitAmount = 1000 * 1e18;
        (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(address(swapPool));
        vm.prank(lp);
        router.initialize(address(swapPool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, "");

        vm.prank(lp);
        router.initialize(
            address(liquidityPool),
            tokens,
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            0,
            false,
            ""
        );
    }

    /// Add

    function testAddLiquidityUnbalancedSimpleFuzz(uint256 daiAmountIn, uint256 swapFee) public {
        daiAmountIn = bound(daiAmountIn, 1e18, maxAmount);
        // swap fee from 0% - 10%
        swapFee = bound(swapFee, 0, 1e17);

        //daiAmountIn = defaultAmount;
        //swapFee = 1e17;

        setSwapFeePercentage(swapFee, address(liquidityPool));
        setSwapFeePercentage(swapFee, address(swapPool));

        uint256[] memory amountsIn = [uint256(daiAmountIn), 0].toMemoryArray();

        vm.startPrank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(liquidityPool), amountsIn, 0, false, bytes(""));

        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(liquidityPool),
            liquidityPool.balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );
        vm.stopPrank();

        vm.prank(bob);
        uint256 amountOut = router.swapExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[0],
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        console2.log("daiAmountIn - amountsOut[0]:", daiAmountIn - amountsOut[0]);
        console2.log("amountOut:", amountOut / 1e18);

        console2.log("usdc.balanceOf(bob):", usdc.balanceOf(bob) / 1e18);
        console2.log("dai.balanceOf(bob):", dai.balanceOf(bob) / 1e18);
        console2.log("amountsOut:", amountsOut[0] / 1e18);
        console2.log("amountsOut:", amountsOut[1] / 1e18);
        console2.log("usdc.balanceOf(alice):", usdc.balanceOf(alice) / 1e18);
        console2.log("dai.balanceOf(alice):", dai.balanceOf(alice) / 1e18);

        // See @notice
        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        uint256 aliceAmountOut = usdc.balanceOf(alice) - defaultBalance;
        console2.log("aliceAmountOut:", aliceAmountOut);
        uint256 bobAmountOut = usdc.balanceOf(bob) - defaultBalance;
        console2.log("bobAmountOut:", bobAmountOut);
        uint256 bobToAliceRatio = (bobAmountOut * 1e18) / aliceAmountOut;

        uint256 liquidityTaxPercentage = (6e15 * swapFee) / 1e17;

        // See @notice at `LiquidityApproximationTest`
        assertGe(bobToAliceRatio, 1e18 - liquidityTaxPercentage - delta, "Bob has too little USDC compare to Alice");
        assertLe(bobToAliceRatio, 1e18 + liquidityTaxPercentage + delta, "Bob has too much USDC compare to Alice");
    }

    function testAddLiquiditySingleTokenExactOutFuzz(uint256 exactBptAmountOut, uint256 swapFee) public {
        exactBptAmountOut = bound(exactBptAmountOut, 1e18, maxAmount);
        console2.log("exactBptAmountOut:", exactBptAmountOut);
        // swap fee from 0% - 10%
        swapFee = bound(swapFee, 0, 1e17);
        console2.log("swapFee:", swapFee);

        //swapFee = 1e17;

        setSwapFeePercentage(swapFee, address(liquidityPool));
        setSwapFeePercentage(swapFee, address(swapPool));

        vm.startPrank(alice);
        uint256[] memory amountsIn = router.addLiquiditySingleTokenExactOut(
            address(liquidityPool),
            dai,
            1e50,
            exactBptAmountOut,
            false,
            bytes("")
        );
        uint256 daiAmountIn = amountsIn[0];
        console2.log("daiAmountIn:", daiAmountIn);
        console2.log("amountsIn[1]:", amountsIn[1]);

        console2.log("liquidityPool.balanceOf(alice):", liquidityPool.balanceOf(alice));
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            address(liquidityPool),
            liquidityPool.balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );
        vm.stopPrank();

        console2.log("amountsOut:", amountsOut[0]);
        console2.log("amountsOut:", amountsOut[1]);

        vm.prank(bob);
        uint256 amountOut = router.swapExactIn(
            address(swapPool),
            dai,
            usdc,
            daiAmountIn - amountsOut[0],
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        console2.log("daiAmountIn - amountsOut[0]:", daiAmountIn - amountsOut[0]);
        console2.log("amountOut:", amountOut / 1e18);

        console2.log("usdc.balanceOf(bob):", usdc.balanceOf(bob) / 1e18);
        console2.log("dai.balanceOf(bob):", dai.balanceOf(bob) / 1e18);
        console2.log("usdc.balanceOf(alice):", usdc.balanceOf(alice) / 1e18);
        console2.log("dai.balanceOf(alice):", dai.balanceOf(alice) / 1e18);

        // See @notice
        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        uint256 aliceAmountOut = usdc.balanceOf(alice) - defaultBalance;
        console2.log("aliceAmountOut:", aliceAmountOut);
        uint256 bobAmountOut = usdc.balanceOf(bob) - defaultBalance;
        console2.log("bobAmountOut:", bobAmountOut);
        uint256 bobToAliceRatio = (bobAmountOut * 1e18) / aliceAmountOut;

        uint256 liquidityTaxPercentage = (6e15 * swapFee) / 1e17;

        // See @notice at `LiquidityApproximationTest`
        assertGe(bobToAliceRatio, 1e18 - liquidityTaxPercentage - delta, "Bob has too little USDC compare to Alice");
        assertLe(bobToAliceRatio, 1e18 + liquidityTaxPercentage + delta, "Bob has too much USDC compare to Alice");
    }

    /// Remove

    function testRemoveLiquiditySingleTokenExactFuzz(uint256 exactAmountOut, uint256 swapFee) public {
        exactAmountOut = bound(exactAmountOut, 1e18, maxAmount);
        console2.log("exactAmountOut:", exactAmountOut);
        // swap fee from 0% - 10%
        swapFee = bound(swapFee, 0, 1e17);
        console2.log("swapFee:", swapFee);

        //swapFee = 1e17;

        setSwapFeePercentage(swapFee, address(liquidityPool));
        setSwapFeePercentage(swapFee, address(swapPool));

        // Add liquidity so we have something to remove
        vm.prank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(
            address(liquidityPool),
            [maxAmount, maxAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        vm.startPrank(alice);
        uint256 bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(liquidityPool),
            bptAmountOut,
            usdc,
            exactAmountOut,
            false,
            bytes("")
        );
        console2.log("bptAmountIn:", bptAmountIn);

        router.removeLiquidityProportional(
            address(liquidityPool),
            liquidityPool.balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );

        vm.stopPrank();

        vm.startPrank(bob);
        uint256 amountOut = router.swapExactIn(
            address(swapPool),
            dai,
            usdc,
            defaultBalance - dai.balanceOf(alice),
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        vm.stopPrank();

        console2.log("amountOut:", amountOut / 1e18);

        console2.log("usdc.balanceOf(bob):", usdc.balanceOf(bob) / 1e18);
        console2.log("dai.balanceOf(bob):", dai.balanceOf(bob) / 1e18);
        console2.log("usdc.balanceOf(alice):", usdc.balanceOf(alice) / 1e18);
        console2.log("dai.balanceOf(alice):", dai.balanceOf(alice) / 1e18);

        // See @notice
        assertEq(dai.balanceOf(alice), dai.balanceOf(bob), "Bob and Alice DAI balances are not equal");

        uint256 aliceAmountOut = usdc.balanceOf(alice) - defaultBalance;
        console2.log("aliceAmountOut:", aliceAmountOut);
        uint256 bobAmountOut = usdc.balanceOf(bob) - defaultBalance;
        console2.log("bobAmountOut:", bobAmountOut);
        uint256 bobToAliceRatio = (bobAmountOut * 1e18) / aliceAmountOut;

        uint256 liquidityTaxPercentage = (6e15 * swapFee) / 1e17;

        // See @notice at `LiquidityApproximationTest`
        assertGe(bobToAliceRatio, 1e18 - delta, "Bob has too little USDC compare to Alice");
        assertLe(bobToAliceRatio, 1e18 + liquidityTaxPercentage + delta, "Bob has too much USDC compare to Alice");
    }

    /// Utils

    function setSwapFeePercentage(uint256 swapFee, address pool) internal {
        authorizer.grantRole(vault.getActionId(IVaultExtension.setStaticSwapFeePercentage.selector), alice);
        vm.prank(alice);
        vault.setStaticSwapFeePercentage(address(pool), swapFee); // 1%
    }

    function computeSimpleInvariant(uint256[] memory balances) external pure returns (uint256) {
        // inv = x + y
        uint256 invariant;
        for (uint256 index = 0; index < balances.length; index++) {
            invariant += balances[index];
        }
        return invariant;
    }
}
