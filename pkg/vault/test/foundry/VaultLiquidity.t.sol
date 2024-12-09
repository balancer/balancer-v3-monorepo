// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AddLiquidityKind, RemoveLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { RouterMock } from "../../contracts/test/RouterMock.sol";

contract VaultLiquidityTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        // We will use min trade amount in this test.
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;

        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    // Add

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
        bptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, bptAmountRoundDown, false, bytes(""));

        // Should mint correct amount of BPT tokens.
        assertEq(bptAmountOut, bptAmountRoundDown, "Invalid amount of BPT");
    }

    function testAddLiquidityUnbalanced() public {
        assertAddLiquidity(addLiquidityUnbalanced);
    }

    function testAddLiquidityTradeLimit() public {
        uint256[] memory amountsIn = [defaultAmount, PRODUCTION_MIN_TRADE_AMOUNT - 1].toMemoryArray();

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
        // Disable add custom liquidity.
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
        (pool, ) = createPool();

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
            abi.encodeWithSelector(
                IVaultErrors.BptAmountOutBelowMin.selector,
                bptAmountRoundDown,
                bptAmountRoundDown + 1
            )
        );
        vm.prank(alice);
        router.addLiquidityUnbalanced(
            pool,
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown + 1,
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

    // Remove

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
            PRODUCTION_MIN_TRADE_AMOUNT * 2 - 1,
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
        // We can't remove more than this, otherwise it fails
        amountsOut[daiIdx] = defaultAmount + defaultAmountRoundDown;

        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            pool,
            bptAmount,
            dai,
            amountsOut[daiIdx],
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

        (pool, ) = createPool();

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
            defaultAmountRoundDown,
            false,
            bytes("")
        );
    }

    function testRoundtripFee() public {
        uint256 swapFeePercentage = 10e16;
        setSwapFeePercentage(swapFeePercentage);

        uint256[] memory amountsIn = [defaultAmount, defaultAmount].toMemoryArray();
        uint256[] memory amountsOut = new uint256[](2);

        Balances memory balancesBefore = getBalances(alice);

        assertFalse(vault.getAddLiquidityCalledFlag(pool), "addLiquidityCalled flag is set");

        vm.startPrank(alice);
        (amountsIn, , , amountsOut) = router.manualAddAndRemoveLiquidity(
            RouterMock.ManualAddRemoveLiquidityParams({
                pool: pool,
                sender: alice,
                maxAmountsIn: amountsIn,
                minBptAmountOut: defaultAmount
            })
        );

        // The whole test runs in the same transaction, so transient storage is set for sessionId 0.
        assertTrue(vault.manualGetAddLiquidityCalledFlagBySession(pool, 0), "addLiquidityCalled flag not set");
        // But will not be set for the current session (1).
        assertEq(vault.manualGetCurrentUnlockSessionId(), 1, "Wrong sessionId");
        assertFalse(vault.getAddLiquidityCalledFlag(pool), "addLiquidityCalled flag still set");

        Balances memory balancesAfter = getBalances(alice);

        // Amount out is 90% amount in after the round-trip.
        assertEq(amountsOut[0], amountsIn[0].mulDown(swapFeePercentage.complement()), "Wrong AmountOut[0]");
        assertEq(amountsOut[1], amountsIn[1].mulDown(swapFeePercentage.complement()), "Wrong AmountOut[1]");

        // Tokens are transferred from the user to the Vault.
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] - amountsIn[0] + amountsOut[0],
            "Round-trip - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] - amountsIn[1] + amountsOut[1],
            "Round-trip - User balance: token 1"
        );

        // Tokens are now in the Vault / pool.
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] + amountsIn[0] - amountsOut[0],
            "Round-trip - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] + amountsIn[1] - amountsOut[0],
            "Round-trip - Pool balance: token 1"
        );

        assertEq(balancesAfter.userBpt, 0, "Round-trip - User BPT balance after");
    }

    function testAddRemoveWithoutRoundtripFee() public {
        uint256 swapFeePercentage = 10e16;
        setSwapFeePercentage(swapFeePercentage);

        uint256[] memory amountsIn = [defaultAmount, defaultAmount].toMemoryArray();

        Balances memory balancesBefore = getBalances(alice);

        vm.startPrank(alice);

        assertFalse(
            vault.manualGetAddLiquidityCalledFlagBySession(pool, 0),
            "addLiquidityCalled flag is set (session 0)"
        );
        amountsIn = router.addLiquidityProportional(pool, amountsIn, defaultAmount, false, bytes(""));

        assertTrue(
            vault.manualGetAddLiquidityCalledFlagBySession(pool, 0),
            "addLiquidityCalled flag not set (session 0)"
        );

        assertFalse(
            vault.manualGetAddLiquidityCalledFlagBySession(pool, 1),
            "addLiquidityCalled flag is set (session 1)"
        );
        uint256[] memory amountsOut = router.removeLiquidityProportional(
            pool,
            IERC20(pool).balanceOf(alice),
            [uint256(0), uint256(0)].toMemoryArray(),
            false,
            bytes("")
        );

        assertFalse(
            vault.manualGetAddLiquidityCalledFlagBySession(pool, 1),
            "addLiquidityCalled flag is set (session 1 - after remove)"
        );

        Balances memory balancesAfter = getBalances(alice);

        // Amount out is amount in after doing without round-trip.
        assertEq(amountsOut[0], amountsIn[0], "Wrong AmountOut[0]");
        assertEq(amountsOut[1], amountsIn[1], "Wrong AmountOut[1]");

        // Tokens are transferred from the user to the Vault.
        assertEq(
            balancesAfter.userTokens[0],
            balancesBefore.userTokens[0] - amountsIn[0] + amountsOut[0],
            "No Round-trip - User balance: token 0"
        );
        assertEq(
            balancesAfter.userTokens[1],
            balancesBefore.userTokens[1] - amountsIn[1] + amountsOut[1],
            "No Round-trip - User balance: token 1"
        );

        // Tokens are now in the Vault / pool.
        assertEq(
            balancesAfter.poolTokens[0],
            balancesBefore.poolTokens[0] + amountsIn[0] - amountsOut[0],
            "No Round-trip - Pool balance: token 0"
        );
        assertEq(
            balancesAfter.poolTokens[1],
            balancesBefore.poolTokens[1] + amountsIn[1] - amountsOut[0],
            "Round-trip - Pool balance: token 1"
        );

        assertEq(balancesAfter.userBpt, 0, "No Round-trip - User BPT balance after");
    }

    function testSwapFeesInEventRemoveLiquidityInRecovery() public {
        setSwapFeePercentage(swapFeePercentage);
        vault.manualEnableRecoveryMode(pool);

        uint256 totalSupplyBefore = IERC20(pool).totalSupply();
        uint256 bptAmountIn = defaultAmount;

        uint256 snapshotId = vm.snapshot();

        vm.prank(lp);
        uint256 amountOut = router.removeLiquiditySingleTokenExactIn(
            pool,
            bptAmountIn,
            dai,
            defaultAmount / 10,
            false,
            bytes("")
        );

        vm.revertTo(snapshotId);

        uint256 swapFeeAmountDai = 5e18;
        uint256[] memory deltas = new uint256[](2);
        deltas[daiIdx] = amountOut;

        // Exact values for swap fees are tested elsewhere; we only want to prove they are not 0 here.
        uint256[] memory swapFeeAmounts = new uint256[](2);
        swapFeeAmounts[daiIdx] = swapFeeAmountDai;

        // Fee should be non-zero, even in RecoveryMode
        vm.expectEmit();
        emit IVaultEvents.LiquidityRemoved(
            pool,
            lp,
            RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
            totalSupplyBefore - bptAmountIn,
            deltas,
            swapFeeAmounts
        );
        vm.prank(lp);
        router.removeLiquiditySingleTokenExactIn(pool, bptAmountIn, dai, defaultAmount / 10, false, bytes(""));
    }

    function testSwapFeesInEventAddLiquidityInRecovery() public {
        setSwapFeePercentage(swapFeePercentage);
        vault.manualEnableRecoveryMode(pool);

        uint256 totalSupplyBefore = IERC20(pool).totalSupply();
        uint256[] memory amountsIn = [defaultAmount, defaultAmount].toMemoryArray();

        uint256 snapshotId = vm.snapshot();

        vm.prank(alice);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));

        vm.revertTo(snapshotId);

        uint256[] memory deltas = new uint256[](2);
        deltas[daiIdx] = amountsIn[daiIdx];
        deltas[usdcIdx] = amountsIn[usdcIdx];

        // Exact values for swap fees are tested elsewhere; we only want to prove they are not 0 here.
        // The add is proportional except for rounding errors so the swap fees here are negligible (but not 0).
        uint256[] memory swapFeeAmounts = new uint256[](2);
        swapFeeAmounts[daiIdx] = 10;
        swapFeeAmounts[usdcIdx] = 10;

        // Fee should be non-zero, even in RecoveryMode
        vm.expectEmit();
        emit IVaultEvents.LiquidityAdded(
            pool,
            alice,
            AddLiquidityKind.UNBALANCED,
            totalSupplyBefore + bptAmountOut,
            deltas,
            swapFeeAmounts
        );

        vm.prank(alice);
        router.addLiquidityUnbalanced(pool, amountsIn, 0, false, bytes(""));
    }

    // Utils

    function assertAddLiquidity(function() returns (uint256[] memory, uint256) testFunc) internal {
        Balances memory balancesBefore = getBalances(alice);

        (uint256[] memory amountsIn, uint256 bptAmountOut) = testFunc();

        Balances memory balancesAfter = getBalances(alice);

        // Tokens are transferred from the user to the Vault.
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

        // Tokens are now in the Vault / pool.
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

        router.addLiquidityCustom(pool, [defaultAmount, defaultAmount].toMemoryArray(), bptAmount, false, bytes(""));

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

        // Tokens are no longer in the Vault / pool.
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

        // User has burned the correct amount of BPT.
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
