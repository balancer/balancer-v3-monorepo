// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    address internal sender;
    address internal poolCreator;

    uint256 internal minPoolSwapFeePercentage;
    uint256 internal maxPoolSwapFeePercentage;

    uint256 internal minSwapAmountDai;
    uint256 internal maxSwapAmountDai;

    uint256 internal minSwapAmountUsdc;
    uint256 internal maxSwapAmountUsdc;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        IProtocolFeeController feeController = vault.getProtocolFeeController();
        IAuthentication feeControllerAuth = IAuthentication(address(feeController));

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        _setUpVariables();

        // Set protocol and creator fees to 50%, so we can measure the charged fees.
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(5e17);

        vm.prank(poolCreator);
        // Set pool creator fee to 100%, so protocol + creator fees equals the total charged fees.
        feeController.setPoolCreatorSwapFeePercentage(pool, 1e18);

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Donate tokens to vault, so liquidity tests are possible.
        dai.mint(address(vault), 100 * poolInitAmount);
        usdc.mint(address(vault), 100 * poolInitAmount);

        // Override vault liquidity, to make sure the extra liquidity is registered.
        vault.manualSetReservesOf(dai, 100 * poolInitAmount);
        vault.manualSetReservesOf(usdc, 100 * poolInitAmount);
    }

    /**
     * @notice Set up test variables (tokens, pool swap fee, swap sizes).
     * @dev When extending the test, override this function and set the same variables.
     */
    function _setUpVariables() internal virtual {
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountDai = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountDai = poolInitAmount;

        minSwapAmountUsdc = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountUsdc = poolInitAmount;

        // 0.0001% min swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 1e17;
    }

    function testDoExactInUndoExactInNoFees__Fuzz(uint256 exactAmountIn) public {
        exactAmountIn = bound(exactAmountIn, minSwapAmountDai, maxSwapAmountDai);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            exactAmountOutDo,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(balancesAfter.userTokens[daiIdx], balancesBefore.userTokens[daiIdx], "Wrong sender dai balance");
        assertLe(balancesAfter.userTokens[usdcIdx], balancesBefore.userTokens[usdcIdx], "Wrong sender usdc balance");
    }

    function testDoExactInUndoExactInLiquidity__Fuzz(uint256 liquidityDai, uint256 liquidityUsdc) public {
        liquidityDai = bound(liquidityDai, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityUsdc = bound(liquidityUsdc, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of dai or usdc liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountIn = (liquidityDai > liquidityUsdc ? liquidityUsdc : liquidityDai) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityDai, liquidityUsdc].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            exactAmountOutDo,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(balancesAfter.userTokens[daiIdx], balancesBefore.userTokens[daiIdx], "Wrong sender dai balance");
        assertLe(balancesAfter.userTokens[usdcIdx], balancesBefore.userTokens[usdcIdx], "Wrong sender usdc balance");
    }

    function testDoExactInUndoExactInVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
        uint256 exactAmountIn = maxSwapAmountDai;
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesUsdc = vault.getAggregateSwapFeeAmount(pool, usdc);

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesUsdc. So, if
        // there were no fees, trading `exactAmountOutDo + feesUsdc` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesUsdc` is comparable with `exactAmountIn`, given that the fees are
        // known.
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            exactAmountOutDo + feesUsdc,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesDai = vault.getAggregateSwapFeeAmount(pool, dai);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn - feesDai, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] - feesDai,
            "Wrong sender dai balance"
        );
        assertLe(
            balancesAfter.userTokens[usdcIdx],
            balancesBefore.userTokens[usdcIdx] - feesUsdc,
            "Wrong sender usdc balance"
        );
    }

    function testDoExactInUndoExactInVariableFeesAmountInAndLiquidity__Fuzz(
        uint256 exactAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 liquidityDai,
        uint256 liquidityUsdc
    ) public {
        liquidityDai = bound(liquidityDai, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityUsdc = bound(liquidityUsdc, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of dai or usdc liquidity, the lowest value, to make sure the swap is executed.
        uint256 maxAmountIn = (liquidityDai > liquidityUsdc ? liquidityUsdc : liquidityDai) / 4;

        exactAmountIn = bound(exactAmountIn, minSwapAmountDai, maxAmountIn);
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityDai, liquidityUsdc].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            dai,
            usdc,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesUsdc = vault.getAggregateSwapFeeAmount(pool, usdc);

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesUsdc. So, if
        // there were no fees, trading `exactAmountOutDo + feesUsdc` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesUsdc` is comparable with `exactAmountIn`, given that the fees are
        // known.
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            exactAmountOutDo + feesUsdc,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesDai = vault.getAggregateSwapFeeAmount(pool, dai);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn - feesDai, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] - feesDai,
            "Wrong sender dai balance"
        );
        assertLe(
            balancesAfter.userTokens[usdcIdx],
            balancesBefore.userTokens[usdcIdx] - feesUsdc,
            "Wrong sender usdc balance"
        );
    }

    function testDoExactOutUndoExactOutNoFees__Fuzz(uint256 exactAmountOut) public {
        exactAmountOut = bound(exactAmountOut, minSwapAmountUsdc, maxSwapAmountUsdc);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            exactAmountInDo,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(balancesAfter.userTokens[daiIdx], balancesBefore.userTokens[daiIdx], "Wrong sender dai balance");
        assertLe(balancesAfter.userTokens[usdcIdx], balancesBefore.userTokens[usdcIdx], "Wrong sender usdc balance");
    }

    function testDoExactOutUndoExactOutLiquidity__Fuzz(uint256 liquidityDai, uint256 liquidityUsdc) public {
        liquidityDai = bound(liquidityDai, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityUsdc = bound(liquidityUsdc, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of dai or usdc liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountOut = (liquidityDai > liquidityUsdc ? liquidityUsdc : liquidityDai) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityDai, liquidityUsdc].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            exactAmountInDo,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(balancesAfter.userTokens[daiIdx], balancesBefore.userTokens[daiIdx], "Wrong sender dai balance");
        assertLe(balancesAfter.userTokens[usdcIdx], balancesBefore.userTokens[usdcIdx], "Wrong sender usdc balance");
    }

    function testDoExactOutUndoExactOutVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
        uint256 exactAmountOut = maxSwapAmountUsdc;
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesDai = vault.getAggregateSwapFeeAmount(pool, dai);

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (usdc) + feesDai (dai). So, if
        // there were no fees, trading `exactAmountInDo - feesDai` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesDai` is comparable with `exactAmountOut`, given that the fees are
        // known.
        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            exactAmountInDo - feesDai,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesUsdc = vault.getAggregateSwapFeeAmount(pool, usdc);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut + feesUsdc, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] - feesDai,
            "Wrong sender dai balance"
        );
        assertLe(
            balancesAfter.userTokens[usdcIdx],
            balancesBefore.userTokens[usdcIdx] - feesUsdc,
            "Wrong sender usdc balance"
        );
    }

    function testDoExactOutUndoExactOutVariableFeesAmountOutAndLiquidity__Fuzz(
        uint256 exactAmountOut,
        uint256 poolSwapFeePercentage,
        uint256 liquidityDai,
        uint256 liquidityUsdc
    ) public {
        liquidityDai = bound(liquidityDai, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityUsdc = bound(liquidityUsdc, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of dai or usdc liquidity, the lowest value, to make sure the swap is executed.
        uint256 maxAmountOut = (liquidityDai > liquidityUsdc ? liquidityUsdc : liquidityDai) / 4;

        exactAmountOut = bound(exactAmountOut, minSwapAmountUsdc, maxAmountOut);
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityDai, liquidityUsdc].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            dai,
            usdc,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesDai = vault.getAggregateSwapFeeAmount(pool, dai);

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (usdc) + feesDai (dai). So, if
        // there were no fees, trading `exactAmountInDo - feesDai` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesDai` is comparable with `exactAmountOut`, given that the fees are
        // known.
        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            usdc,
            dai,
            exactAmountInDo - feesDai,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesUsdc = vault.getAggregateSwapFeeAmount(pool, usdc);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut + feesUsdc, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[daiIdx],
            balancesBefore.userTokens[daiIdx] - feesDai,
            "Wrong sender dai balance"
        );
        assertLe(
            balancesAfter.userTokens[usdcIdx],
            balancesBefore.userTokens[usdcIdx] - feesUsdc,
            "Wrong sender usdc balance"
        );
    }
}
