// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";

/**
 * @notice Liquidity operations that are unproportional allow for indirect swaps. It is
 * crucial to guarantee that the swap fees for indirect swaps facilitated
 * through liquidity operations are not lower than those for direct swaps.
 * To ensure this, we analyze the results of two different operations:
 * unproportional liquidity operation (addLiquidityUnbalanced) combined with
 * add/remove liquidity proportionally, and swapExactIn. Consider the following scenario:
 *
 * Alice begins with balances of [100, 0].
 * She executes addLiquidityUnbalanced([100, 0]) and subsequently removeLiquidityProportionally,
 * resulting in balances of [66, 33].
 * Bob, starting with the same balances [100, 0], performs a swapExactIn(34).
 * We determine the amount Alice indirectly traded as 34 (100 - 66 = 34),
 * enabling us to compare the swap fees incurred on the trade.
 * This comparison ensures that the fees for a direct swap remain higher than those for an indirect swap.
 * Finally, we assess the final balances of Alice and Bob. Two criteria must be satisfied:
 *   a. The initial coin balances for the trade should be identical,
 *      meaning Alice's [66, ...] should correspond to Bob's [66, ...].
 *   b. The resulting balances from the trade should ensure that Bob always has an equal or greater amount than Alice.
 *      But the difference should never be too much, i.e. we don't want to steal from users on liquidity operations.
 *      This implies that Alice's balance [..., 33] should be less than or at most equal to Bob's [..., 34].
 *
 * This methodology and evaluation criteria are applicable to all unproportional liquidity operations and pool types.
 * Furthermore, this approach validates the correct amount of BPT minted/burned for liquidity operations.
 * If more BPT were minted or fewer BPT were burned than required,
 * it would result in Alice having more assets at the end than Bob, which we have verified to be untrue.
 *
 * @dev assertGe( (usdc.balanceOf(bob) * 1e18) / usdc.balanceOf(alice), 99e16, "Bob has too little USDC compare to Alice");
                                                             // See @notice
                                                                     assertLe( (usdc.balanceOf(bob) * 1e18) / usdc.balanceOf(alice), 101e16, "Bob has too much USDC compare to Alice");

 * Bob should always maintain a balance of USDC equal to or greater than Alice's
 * since liquidity operations should not confer any advantage over a pure swap.
 * At the same time, we aim to avoid unfairly diminishing user balances.
 * Therefore, Alice's balance should ideally be slightly less than Bob's,
 * though extremely close. This allowance for a minor discrepancy accounts
 * for the inherent imperfections in Solidity's mathematics and rounding errors in the code.
 */
contract LiquidityApproximationTest is BaseVaultTest {
    using ArrayHelpers for *;

    PoolMock internal swapPool;
    PoolMock internal liquidityPool;
    // Allows small delta to account for rounding
    uint256 internal delta = 1e12;
    uint256 internal maxAmount = 3e8 * 1e18;

    function setUp() public virtual override {
        defaultBalance = 1e10 * 1e18;
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        liquidityPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            new IRateProvider[](2),
            true,
            365 days,
            address(0)
        );
        vm.label(address(liquidityPool), "liquidityPool");

        swapPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            [address(dai), address(usdc)].toMemoryArray().asIERC20(),
            new IRateProvider[](2),
            true,
            365 days,
            address(0)
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

        uint256 liquidityGrowthPercentage = (6e15 * swapFee) / 1e17;

        // See @notice at `LiquidityApproximationTest`
        assertGe(bobToAliceRatio, 1e18 - liquidityGrowthPercentage - delta, "Bob has too little USDC compare to Alice");
        assertLe(bobToAliceRatio, 1e18 + liquidityGrowthPercentage + delta, "Bob has too much USDC compare to Alice");
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

        uint256 liquidityGrowthPercentage = (6e15 * swapFee) / 1e17;

        // See @notice at `LiquidityApproximationTest`
        assertGe(bobToAliceRatio, 1e18 - liquidityGrowthPercentage - delta, "Bob has too little USDC compare to Alice");
        assertLe(bobToAliceRatio, 1e18 + liquidityGrowthPercentage + delta, "Bob has too much USDC compare to Alice");
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

        uint256 liquidityGrowthPercentage = (6e15 * swapFee) / 1e17;

        // See @notice at `LiquidityApproximationTest`
        assertGe(bobToAliceRatio, 1e18 - liquidityGrowthPercentage - delta, "Bob has too little USDC compare to Alice");
        assertLe(bobToAliceRatio, 1e18 + liquidityGrowthPercentage + delta, "Bob has too much USDC compare to Alice");
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
