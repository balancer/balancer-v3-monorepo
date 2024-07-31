// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eBatchSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    address internal poolA;
    address internal poolB;
    address internal poolC;

    ERC20TestToken internal tokenA;
    ERC20TestToken internal tokenB;
    ERC20TestToken internal tokenC;
    ERC20TestToken internal tokenD;

    IERC20[] internal tokensToTrack;

    uint256 internal tokenAIdx;
    uint256 internal tokenBIdx;
    uint256 internal tokenCIdx;
    uint256 internal tokenDIdx;

    address internal sender;
    address internal poolCreator;

    uint256 internal minPoolSwapFeePercentage;
    uint256 internal maxPoolSwapFeePercentage;

    uint256 internal minSwapAmountTokenA;
    uint256 internal maxSwapAmountTokenA;

    uint256 internal minSwapAmountTokenD;
    uint256 internal maxSwapAmountTokenD;

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

        // Initialize pools that will be used by batch router.
        // Create poolA
        vm.startPrank(lp);
        poolA = _createPool([address(tokenA), address(tokenB)].toMemoryArray(), "poolA");
        _initPool(poolA, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        // Create poolB
        poolB = _createPool([address(tokenB), address(tokenC)].toMemoryArray(), "poolB");
        _initPool(poolB, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        // Create poolC
        poolC = _createPool([address(tokenC), address(tokenD)].toMemoryArray(), "PoolC");
        _initPool(poolC, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        tokensToTrack = [address(tokenA), address(tokenB), address(tokenC), address(tokenD)].toMemoryArray().asIERC20();

        // Idx of the token in relation to `tokensToTrack`.
        tokenAIdx = 0;
        tokenBIdx = 1;
        tokenCIdx = 2;
        tokenDIdx = 3;
    }

    /**
     * @notice Set up test variables (tokens, pool swap fee, swap sizes).
     * @dev When extending the test, override this function and set the same variables.
     */
    function _setUpVariables() internal virtual {
        tokenA = dai;
        tokenB = usdc;
        tokenC = ERC20TestToken(address(weth));
        tokenD = wsteth;
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountTokenA = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenA = poolInitAmount;

        minSwapAmountTokenD = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenD = poolInitAmount;

        // 0.0001% min swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 1e17;
    }

    function testDoExactInUndoExactInNoFees__Fuzz(uint256 exactAmountIn) public {
        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxSwapAmountTokenA);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender, tokensToTrack);
        uint256[] memory invariantsBefore = _getPoolInvariants();

        vm.startPrank(sender);
        uint256 amountOutDo = _executeAndCheckBatchExactIn(IERC20(address(tokenA)), exactAmountIn);
        uint256 amountOutUndo = _executeAndCheckBatchExactIn(IERC20(address(tokenD)), amountOutDo);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender, tokensToTrack);
        uint256[] memory invariantsAfter = _getPoolInvariants();

        assertLe(amountOutUndo, exactAmountIn, "Amount out undo should be <= exactAmountIn");

        _checkUserBalancesAndPoolInvariants(balancesBefore, balancesAfter, invariantsBefore, invariantsAfter);
    }

    //    function testDoExactInUndoExactInLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
    //        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
    //        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);
    //
    //        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
    //        uint256 exactAmountIn = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;
    //
    //        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
    //        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);
    //
    //        // Set liquidity of pool.
    //        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
    //        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
    //        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
    //
    //        vm.startPrank(sender);
    //        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
    //            pool,
    //            tokenA,
    //            tokenB,
    //            exactAmountIn,
    //            0,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
    //            pool,
    //            tokenB,
    //            tokenA,
    //            exactAmountOutDo,
    //            0,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        vm.stopPrank();
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
    //
    //        assertLe(exactAmountOutUndo, exactAmountIn, "Amount out undo should be <= exactAmountIn");
    //        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenA],
    //            balancesBefore.userTokens[_idxTokenA],
    //            "Wrong sender tokenA balance"
    //        );
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenB],
    //            balancesBefore.userTokens[_idxTokenB],
    //            "Wrong sender tokenB balance"
    //        );
    //    }
    //
    //    function testDoExactInUndoExactInVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
    //        uint256 exactAmountIn = maxSwapAmountTokenA;
    //        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);
    //
    //        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
    //
    //        vm.startPrank(sender);
    //        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
    //            pool,
    //            tokenA,
    //            tokenB,
    //            exactAmountIn,
    //            0,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
    //
    //        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesTokenB. So, if
    //        // there were no fees, trading `exactAmountOutDo + feesTokenB` would get exactAmountIn. Therefore, a swap
    //        // with exact_in `exactAmountOutDo + feesTokenB` is comparable with `exactAmountIn`, given that the fees are
    //        // known.
    //        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
    //            pool,
    //            tokenB,
    //            tokenA,
    //            exactAmountOutDo + feesTokenB,
    //            0,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
    //        vm.stopPrank();
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
    //
    //        assertLe(exactAmountOutUndo, exactAmountIn - feesTokenA, "Amount out undo should be <= exactAmountIn");
    //        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenA],
    //            balancesBefore.userTokens[_idxTokenA] - feesTokenA,
    //            "Wrong sender tokenA balance"
    //        );
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenB],
    //            balancesBefore.userTokens[_idxTokenB] - feesTokenB,
    //            "Wrong sender tokenB balance"
    //        );
    //    }
    //
    //    function testDoExactInUndoExactInVariableFeesAmountInAndLiquidity__Fuzz(
    //        uint256 exactAmountIn,
    //        uint256 poolSwapFeePercentage,
    //        uint256 liquidityTokenA,
    //        uint256 liquidityTokenB
    //    ) public {
    //        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
    //        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);
    //
    //        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
    //        uint256 maxAmountIn = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;
    //
    //        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxAmountIn);
    //        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);
    //
    //        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);
    //
    //        // Set liquidity of pool.
    //        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
    //        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
    //        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
    //
    //        vm.startPrank(sender);
    //        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
    //            pool,
    //            tokenA,
    //            tokenB,
    //            exactAmountIn,
    //            0,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
    //
    //        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesTokenB. So, if
    //        // there were no fees, trading `exactAmountOutDo + feesTokenB` would get exactAmountIn. Therefore, a swap
    //        // with exact_in `exactAmountOutDo + feesTokenB` is comparable with `exactAmountIn`, given that the fees are
    //        // known.
    //        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
    //            pool,
    //            tokenB,
    //            tokenA,
    //            exactAmountOutDo + feesTokenB,
    //            0,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
    //        vm.stopPrank();
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
    //
    //        assertLe(exactAmountOutUndo, exactAmountIn - feesTokenA, "Amount out undo should be <= exactAmountIn");
    //        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenA],
    //            balancesBefore.userTokens[_idxTokenA] - feesTokenA,
    //            "Wrong sender tokenA balance"
    //        );
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenB],
    //            balancesBefore.userTokens[_idxTokenB] - feesTokenB,
    //            "Wrong sender tokenB balance"
    //        );
    //    }
    //
    //    function testDoExactOutUndoExactOutNoFees__Fuzz(uint256 exactAmountOut) public {
    //        exactAmountOut = bound(exactAmountOut, minSwapAmountTokenB, maxSwapAmountTokenB);
    //
    //        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
    //        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
    //
    //        vm.startPrank(sender);
    //        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenA,
    //            tokenB,
    //            exactAmountOut,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenB,
    //            tokenA,
    //            exactAmountInDo,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        vm.stopPrank();
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
    //
    //        assertGe(exactAmountInUndo, exactAmountOut, "Amount in undo should be >= exactAmountOut");
    //        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenA],
    //            balancesBefore.userTokens[_idxTokenA],
    //            "Wrong sender tokenA balance"
    //        );
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenB],
    //            balancesBefore.userTokens[_idxTokenB],
    //            "Wrong sender tokenB balance"
    //        );
    //    }
    //
    //    function testDoExactOutUndoExactOutLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
    //        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
    //        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);
    //
    //        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
    //        uint256 exactAmountOut = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;
    //
    //        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
    //        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);
    //
    //        // Set liquidity of pool.
    //        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
    //        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
    //        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
    //
    //        vm.startPrank(sender);
    //        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenA,
    //            tokenB,
    //            exactAmountOut,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenB,
    //            tokenA,
    //            exactAmountInDo,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        vm.stopPrank();
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
    //
    //        assertGe(exactAmountInUndo, exactAmountOut, "Amount in undo should be >= exactAmountOut");
    //        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenA],
    //            balancesBefore.userTokens[_idxTokenA],
    //            "Wrong sender tokenA balance"
    //        );
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenB],
    //            balancesBefore.userTokens[_idxTokenB],
    //            "Wrong sender tokenB balance"
    //        );
    //    }
    //
    //    function testDoExactOutUndoExactOutVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
    //        uint256 exactAmountOut = maxSwapAmountTokenB;
    //        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);
    //
    //        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
    //
    //        vm.startPrank(sender);
    //        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenA,
    //            tokenB,
    //            exactAmountOut,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
    //
    //        // In the first swap, the trade was exactAmountInDo => exactAmountOut (tokenB) + feesTokenA (tokenA). So, if
    //        // there were no fees, trading `exactAmountInDo - feesTokenA` would get exactAmountOut. Therefore, a swap
    //        // with exact_out `exactAmountInDo - feesTokenA` is comparable with `exactAmountOut`, given that the fees are
    //        // known.
    //        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenB,
    //            tokenA,
    //            exactAmountInDo - feesTokenA,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
    //        vm.stopPrank();
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
    //
    //        assertGe(exactAmountInUndo, exactAmountOut + feesTokenB, "Amount in undo should be >= exactAmountOut");
    //        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenA],
    //            balancesBefore.userTokens[_idxTokenA] - feesTokenA,
    //            "Wrong sender tokenA balance"
    //        );
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenB],
    //            balancesBefore.userTokens[_idxTokenB] - feesTokenB,
    //            "Wrong sender tokenB balance"
    //        );
    //    }
    //
    //    function testDoExactOutUndoExactOutVariableFeesAmountOutAndLiquidity__Fuzz(
    //        uint256 exactAmountOut,
    //        uint256 poolSwapFeePercentage,
    //        uint256 liquidityTokenA,
    //        uint256 liquidityTokenB
    //    ) public {
    //        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
    //        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);
    //
    //        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
    //        uint256 maxAmountOut = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;
    //
    //        exactAmountOut = bound(exactAmountOut, minSwapAmountTokenB, maxAmountOut);
    //        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);
    //
    //        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);
    //
    //        // Set liquidity of pool.
    //        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
    //        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
    //        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);
    //
    //        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);
    //
    //        vm.startPrank(sender);
    //        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenA,
    //            tokenB,
    //            exactAmountOut,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //
    //        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
    //
    //        // In the first swap, the trade was exactAmountInDo => exactAmountOut (tokenB) + feesTokenA (tokenA). So, if
    //        // there were no fees, trading `exactAmountInDo - feesTokenA` would get exactAmountOut. Therefore, a swap
    //        // with exact_out `exactAmountInDo - feesTokenA` is comparable with `exactAmountOut`, given that the fees are
    //        // known.
    //        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
    //            pool,
    //            tokenB,
    //            tokenA,
    //            exactAmountInDo - feesTokenA,
    //            MAX_UINT128,
    //            MAX_UINT128,
    //            false,
    //            bytes("")
    //        );
    //        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
    //        vm.stopPrank();
    //
    //        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);
    //
    //        assertGe(exactAmountInUndo, exactAmountOut + feesTokenB, "Amount in undo should be >= exactAmountOut");
    //        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenA],
    //            balancesBefore.userTokens[_idxTokenA] - feesTokenA,
    //            "Wrong sender tokenA balance"
    //        );
    //        assertLe(
    //            balancesAfter.userTokens[_idxTokenB],
    //            balancesBefore.userTokens[_idxTokenB] - feesTokenB,
    //            "Wrong sender tokenB balance"
    //        );
    //    }

    function _executeAndCheckBatchExactIn(IERC20 tokenIn, uint256 exactAmountIn) private returns (uint256 amountOut) {
        IBatchRouter.SwapPathExactAmountIn[] memory swapPath = _buildExactInPaths(tokenIn, exactAmountIn, 0);

        (uint256[] memory pathAmountsOut, address[] memory tokensOut, uint256[] memory amountsOut) = batchRouter
            .swapExactIn(swapPath, MAX_UINT128, false, bytes(""));

        assertEq(pathAmountsOut.length, 1, "pathAmountsOut incorrect length");
        assertEq(tokensOut.length, 1, "tokensOut incorrect length");
        assertEq(amountsOut.length, 1, "amountsOut incorrect length");

        if (tokenIn == tokenA) {
            assertEq(tokensOut[0], address(tokenD), "tokenOut is not tokenD");
        } else {
            assertEq(tokensOut[0], address(tokenA), "tokenOut is not tokenA");
        }

        assertEq(pathAmountsOut[0], amountsOut[0], "pathAmountsOut and amountsOut do not match");

        amountOut = pathAmountsOut[0];
    }

    function _checkUserBalancesAndPoolInvariants(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256[] memory invariantsBefore,
        uint256[] memory invariantsAfter
    ) private {
        // The invariants of all pools should not decrease after the batch swap operation.
        for (uint256 i = 0; i < invariantsBefore.length; i++) {
            assertGe(invariantsAfter[i], invariantsBefore[i], "Wrong pool invariant");
        }

        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx],
            "Wrong sender tokenA balance"
        );
        assertEq(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "Wrong sender tokenB balance"
        );
        assertEq(
            balancesAfter.userTokens[tokenCIdx],
            balancesBefore.userTokens[tokenCIdx],
            "Wrong sender tokenC balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenDIdx],
            balancesBefore.userTokens[tokenDIdx],
            "Wrong sender tokenD balance"
        );
    }

    function _buildExactInPaths(
        IERC20 tokenIn,
        uint256 exactAmountIn,
        uint256 minAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenIn,
            steps: _getSwapSteps(tokenIn),
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }

    function _buildExactOutPaths(
        IERC20 tokenIn,
        uint256 maxAmountIn,
        uint256 exactAmountOut
    ) private view returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenIn,
            steps: _getSwapSteps(tokenIn),
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }

    function _getSwapSteps(IERC20 tokenIn) private view returns (IBatchRouter.SwapPathStep[] memory steps) {
        steps = new IBatchRouter.SwapPathStep[](3);

        if (address(tokenIn) == address(tokenD)) {
            steps[0] = IBatchRouter.SwapPathStep({ pool: poolC, tokenOut: IERC20(address(tokenC)), isBuffer: false });
            steps[1] = IBatchRouter.SwapPathStep({ pool: poolB, tokenOut: IERC20(address(tokenB)), isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: poolA, tokenOut: IERC20(address(tokenA)), isBuffer: false });
        } else {
            steps[0] = IBatchRouter.SwapPathStep({ pool: poolA, tokenOut: IERC20(address(tokenB)), isBuffer: false });
            steps[1] = IBatchRouter.SwapPathStep({ pool: poolB, tokenOut: IERC20(address(tokenC)), isBuffer: false });
            steps[2] = IBatchRouter.SwapPathStep({ pool: poolC, tokenOut: IERC20(address(tokenD)), isBuffer: false });
        }
    }

    function _getPoolInvariants() private returns (uint256[] memory poolInvariants) {
        address[] memory pools = [poolA, poolB, poolC].toMemoryArray();
        poolInvariants = new uint256[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(pools[i]);
            poolInvariants[i] = IBasePool(pools[i]).computeInvariant(lastBalancesLiveScaled18);
        }
    }
}
