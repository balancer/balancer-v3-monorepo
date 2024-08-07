// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultLiquidityTest is BaseVaultTest {
    using ArrayHelpers for *;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    /// Add

    function addLiquidityProportional() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        bptAmountOut = defaultAmount;
        amountsIn = [defaultAmount, defaultAmount].toMemoryArray();

        vm.prank(alice);
        amountsIn = router.addLiquidityProportional(pool, amountsIn, bptAmountOut, false, bytes(""));

        // should mint correct amount of BPT tokens.
        assertEq(bptAmountOut, defaultAmount, "Invalid amount of BPT");
    }

    function testAddLiquidityProportional() public {
        assertAddLiquidity(addLiquidityProportional);
    }

    function testAddLiquidityProportionalWithDust() public {
        dai.mint(address(vault), 1);
        usdc.mint(address(vault), 1);
        assertAddLiquidity(addLiquidityProportional);
    }

    function addLiquidityUnbalanced() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        amountsIn = [defaultAmount, defaultAmount].toMemoryArray();

        vm.prank(alice);
        bptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, defaultAmount, false, bytes(""));

        // Should mint correct amount of BPT tokens.
        assertEq(bptAmountOut, defaultAmount * 2, "Invalid amount of BPT");
    }

    function testAddLiquidityUnbalanced() public {
        assertAddLiquidity(addLiquidityUnbalanced);
    }

    function testAddLiquidityTradeLimit() public {
        uint256[] memory amountsIn = [defaultAmount, MIN_TRADE_AMOUNT - 1].toMemoryArray();

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        router.addLiquidityUnbalanced(pool, amountsIn, defaultAmount, false, bytes(""));
    }

    function testAddLiquidityUnbalancedDisabled() public {
        // Disable unbalanced liquidity.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        poolConfigBits.liquidityManagement.disableUnbalancedLiquidity = true;
        vault.manualSetPoolConfig(pool, poolConfigBits);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );
    }

    function addLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        bptAmountOut = defaultAmount;
        vm.prank(alice);
        uint256 amountIn = router.addLiquiditySingleTokenExactOut(
            pool,
            dai,
            defaultAmount,
            bptAmountOut,
            false,
            bytes("")
        );

        (amountsIn, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountIn);

        // Should mint correct amount of BPT tokens.
        assertEq(bptAmountOut, defaultAmount, "Invalid amount of BPT");
    }

    function testAddLiquiditySingleTokenExactOut() public {
        assertAddLiquidity(addLiquiditySingleTokenExactOut);
    }

    function testAddLiquiditySingleTokenExactOutDisabled() public {
        // Disable unbalanced liquidity.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        poolConfigBits.liquidityManagement.disableUnbalancedLiquidity = true;
        vault.manualSetPoolConfig(pool, poolConfigBits);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        router.addLiquiditySingleTokenExactOut(pool, dai, defaultAmount, defaultAmount, false, bytes(""));
    }

    function addLiquidityCustom() public returns (uint256[] memory amountsIn, uint256 bptAmountOut) {
        vm.prank(alice);
        (amountsIn, bptAmountOut, ) = router.addLiquidityCustom(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        // Should mint correct amount of BPT tokens.
        assertEq(bptAmountOut, defaultAmount);
    }

    function testAddLiquidityCustom() public {
        assertAddLiquidity(addLiquidityCustom);
    }

    function testAddLiquidityCustomDisabled() public {
        // Disable add custom liquidity
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        poolConfigBits.liquidityManagement.enableAddLiquidityCustom = false;
        vault.manualSetPoolConfig(pool, poolConfigBits);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.DoesNotSupportAddLiquidityCustom.selector);
        router.addLiquidityCustom(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );
    }

    function testAddLiquidityNotInitialized() public {
        pool = createPool();

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, pool));
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );
    }

    function testAddLiquidityBptAmountOutBelowMin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.BptAmountOutBelowMin.selector, 2 * defaultAmount, 2 * defaultAmount + 1)
        );
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            2 * defaultAmount + 1,
            false,
            bytes("")
        );
    }

    function testAddLiquidityAmountInAboveMax() public {
        uint256 bptAmountOut = defaultAmount;
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountInAboveMax.selector,
                address(dai),
                defaultAmount,
                defaultAmount - 1
            )
        );
        vm.prank(alice);
        router.addLiquiditySingleTokenExactOut(pool, dai, defaultAmount - 1, bptAmountOut, false, bytes(""));
    }

    /// Remove

    function removeLiquidityProportional() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        bptAmountIn = defaultAmount * 2;

        amountsOut = router.removeLiquidityProportional(
            pool,
            bptAmountIn,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );

        // Ensure `amountsOut` are correct.
        assertEq(amountsOut[0], defaultAmount, "Wrong AmountOut[0]");
        assertEq(amountsOut[1], defaultAmount, "Wrong AmountOut[1]");
    }

    function testRemoveLiquidityProportional() public {
        assertRemoveLiquidity(removeLiquidityProportional);
    }

    function testRemoveLiquidityTradeLimit() public {
        vm.expectRevert(IVaultErrors.TradeAmountTooSmall.selector);
        router.removeLiquidityProportional(
            pool,
            MIN_TRADE_AMOUNT * 2 - 1,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function removeLiquiditySingleTokenExactIn() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        bptAmountIn = defaultAmount * 2;

        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            pool,
            bptAmountIn,
            dai,
            defaultAmount,
            false,
            bytes("")
        );

        (amountsOut, ) = router.getSingleInputArrayAndTokenIndex(pool, dai, amountOut);

        // Ensure `amountsOut` are correct.
        assertEq(amountsOut[daiIdx], defaultAmount * 2, "Wrong AmountOut[dai]");
        assertEq(amountsOut[usdcIdx], 0, "AmountOut[usdc] > 0");
    }

    function testRemoveLiquiditySingleTokenExactIn() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactIn);
    }

    function testRemoveLiquiditySingleTokenExactInDisabled() public {
        // Disable unbalanced liquidity.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        poolConfigBits.liquidityManagement.disableUnbalancedLiquidity = true;
        vault.manualSetPoolConfig(pool, poolConfigBits);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        vm.startPrank(alice);
        router.removeLiquiditySingleTokenExactIn(pool, defaultAmount * 2, dai, defaultAmount, false, bytes(""));
    }

    function removeLiquiditySingleTokenExactOut() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        amountsOut = new uint256[](2);
        amountsOut[daiIdx] = defaultAmount * 2;

        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            pool,
            2 * defaultAmount,
            dai,
            uint256(2 * defaultAmount),
            false,
            bytes("")
        );
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        assertRemoveLiquidity(removeLiquiditySingleTokenExactOut);
    }

    function testRemoveLiquiditySingleTokenExactOutDisabled() public {
        // Disable unbalanced liquidity.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        poolConfigBits.liquidityManagement.disableUnbalancedLiquidity = true;

        vault.manualSetPoolConfig(pool, poolConfigBits);

        vm.expectRevert(IVaultErrors.DoesNotSupportUnbalancedLiquidity.selector);
        vm.startPrank(alice);
        router.removeLiquiditySingleTokenExactOut(pool, defaultAmount * 2, dai, defaultAmount * 2, false, bytes(""));
    }

    function removeLiquidityCustom() public returns (uint256[] memory amountsOut, uint256 bptAmountIn) {
        (bptAmountIn, amountsOut, ) = router.removeLiquidityCustom(
            pool,
            defaultAmount * 2,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );

        // Ensure `amountsOut` are correct.
        assertEq(amountsOut[daiIdx], defaultAmount, "Wrong AmountOut[dai]");
        assertEq(amountsOut[usdcIdx], defaultAmount, "Wrong AmountOut[usdc]");
    }

    function testRemoveLiquidityCustom() public {
        assertRemoveLiquidity(removeLiquidityCustom);
    }

    function testRemoveLiquidityCustomDisabled() public {
        // Disable remove custom liquidity.
        PoolConfig memory poolConfigBits = vault.getPoolConfig(pool);
        poolConfigBits.liquidityManagement.enableRemoveLiquidityCustom = false;

        vault.manualSetPoolConfig(pool, poolConfigBits);

        vm.expectRevert(IVaultErrors.DoesNotSupportRemoveLiquidityCustom.selector);
        vm.startPrank(alice);
        router.removeLiquidityCustom(
            pool,
            defaultAmount * 2,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testRemoveLiquidityNotInitialized() public {
        vm.startPrank(alice);

        pool = createPool();

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolNotInitialized.selector, pool));
        router.removeLiquidityProportional(
            pool,
            defaultAmount,
            [defaultAmount, defaultAmount].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testRemoveLiquidityAmountOutBelowMin() public {
        uint256[] memory amountsOut = new uint256[](2);
        amountsOut[daiIdx] = defaultAmount + 1;
        amountsOut[usdcIdx] = defaultAmount;

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.AmountOutBelowMin.selector,
                address(dai),
                defaultAmount,
                defaultAmount + 1
            )
        );
        vm.startPrank(alice);
        router.removeLiquidityProportional(pool, 2 * defaultAmount, amountsOut, false, bytes(""));
    }

    function testRemoveLiquidityBptInAboveMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.BptAmountInAboveMax.selector, defaultAmount, defaultAmount / 2 - 1)
        );
        vm.startPrank(alice);
        router.removeLiquiditySingleTokenExactOut(
            pool,
            defaultAmount / 2 - 1, // Exit with only one token, so the expected BPT amount in is 1/2 of the total.
            dai,
            defaultAmount,
            false,
            bytes("")
        );
    }

    /// Utils

    function assertAddLiquidity(function() returns (uint256[] memory, uint256) testFunc) internal {
        Balances memory balancesBefore = getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut) = testFunc();

        Balances memory balancesAfter = getBalances(alice);

        // Tokens are transferred from the user to the vault.
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] - amountsIn[0],
            "Add - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] - amountsIn[1],
            "Add - User balance: token 1"
        );

        // Tokens are now in the vault / pool.
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] + amountsIn[0],
            "Add - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] + amountsIn[1],
            "Add - Pool balance: token 1"
        );

        // User now has BPT.
        assertEq(balancesBefore.userBpt, 0, "Add - User BPT balance before");
        assertEq(balancesAfter.userBpt, bptAmountOut, "Add - User BPT balance after");

        // Ensure raw and last live balances are in sync after the operation.
        uint256[] memory currentLiveBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory lastBalancesLiveScaled18 = vault.getLastLiveBalances(pool);

        assertEq(currentLiveBalances.length, lastBalancesLiveScaled18.length);

        for (uint256 i = 0; i < currentLiveBalances.length; ++i) {
            assertEq(currentLiveBalances[i], lastBalancesLiveScaled18[i]);
        }
    }

    function assertRemoveLiquidity(function() returns (uint256[] memory, uint256) testFunc) internal {
        vm.startPrank(alice);

        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            defaultAmount,
            false,
            bytes("")
        );

        Balances memory balancesBefore = getBalances(alice);

        (uint256[] memory amountsOut, uint256 bptAmountIn) = testFunc();

        vm.stopPrank();

        Balances memory balancesAfter = getBalances(alice);

        // Tokens are transferred back to user.
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] + amountsOut[0],
            "Remove - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] + amountsOut[1],
            "Remove - User balance: token 1"
        );

        // Tokens are no longer in the vault / pool.
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] - amountsOut[0],
            "Remove - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] - amountsOut[1],
            "Remove - Pool balance: token 1"
        );

        // User has burnt the correct amount of BPT.
        assertEq(balancesBefore.userBpt, bptAmountIn, "Remove - User BPT balance before");
        assertEq(balancesAfter.userBpt, 0, "Remove - User BPT balance after");

        // Ensure raw and last live balances are in sync after the operation.
        uint256[] memory currentLiveBalances = vault.getCurrentLiveBalances(pool);
        uint256[] memory lastBalancesLiveScaled18 = vault.getLastLiveBalances(pool);

        assertEq(currentLiveBalances.length, lastBalancesLiveScaled18.length);

        for (uint256 i = 0; i < currentLiveBalances.length; ++i) {
            assertEq(currentLiveBalances[i], lastBalancesLiveScaled18[i]);
        }
    }
}
