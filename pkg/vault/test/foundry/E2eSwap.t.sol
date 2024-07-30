// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    ERC20TestToken internal tokenA;
    ERC20TestToken internal tokenB;
    uint256 internal tokenAIdx;
    uint256 internal tokenBIdx;
    address internal sender;
    address internal poolCreator;

    uint256 internal minPoolSwapFeePercentage;
    uint256 internal maxPoolSwapFeePercentage;

    uint256 internal minSwapAmountTokenA;
    uint256 internal maxSwapAmountTokenA;

    uint256 internal minSwapAmountTokenB;
    uint256 internal maxSwapAmountTokenB;

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
        feeController.setGlobalProtocolSwapFeePercentage(50e16);

        vm.prank(poolCreator);
        // Set pool creator fee to 100%, so protocol + creator fees equals the total charged fees.
        feeController.setPoolCreatorSwapFeePercentage(pool, FixedPoint.ONE);

        (tokenAIdx, tokenBIdx) = _getTokenIndexes();

        // Donate tokens to vault, so liquidity tests are possible.
        tokenA.mint(address(vault), 100 * poolInitAmount);
        tokenB.mint(address(vault), 100 * poolInitAmount);
        // Override vault liquidity, to make sure the extra liquidity is registered.
        vault.manualSetReservesOf(tokenA, 100 * poolInitAmount);
        vault.manualSetReservesOf(tokenB, 100 * poolInitAmount);
    }

    /**
     * @notice Set up test variables (tokens, pool swap fee, swap sizes).
     * @dev When extending the test, override this function and set the same variables.
     */
    function _setUpVariables() internal virtual {
        tokenA = dai;
        tokenB = usdc;
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountTokenA = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenA = poolInitAmount;

        minSwapAmountTokenB = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenB = poolInitAmount;

        // 0.0001% min swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 10e16;
    }

    function testDoExactInUndoExactInNoFees__Fuzz(uint256 exactAmountIn) public {
        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxSwapAmountTokenA);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            tokenA,
            tokenB,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            tokenB,
            tokenA,
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
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx],
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "Wrong sender tokenB balance"
        );
    }

    function testDoExactInUndoExactInLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountIn = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            tokenA,
            tokenB,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            tokenB,
            tokenA,
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
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx],
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "Wrong sender tokenB balance"
        );
    }

    function testDoExactInUndoExactInVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
        uint256 exactAmountIn = maxSwapAmountTokenA;
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            tokenA,
            tokenB,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesTokenB. So, if
        // there were no fees, trading `exactAmountOutDo + feesTokenB` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesTokenB` is comparable with `exactAmountIn`, given that the fees are
        // known.
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            tokenB,
            tokenA,
            exactAmountOutDo + feesTokenB,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn - feesTokenA, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx] - feesTokenA,
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx] - feesTokenB,
            "Wrong sender tokenB balance"
        );
    }

    function testDoExactInUndoExactInVariableFeesAmountInAndLiquidity__Fuzz(
        uint256 exactAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB
    ) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        uint256 maxAmountIn = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;

        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxAmountIn);
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            tokenA,
            tokenB,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesTokenB. So, if
        // there were no fees, trading `exactAmountOutDo + feesTokenB` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesTokenB` is comparable with `exactAmountIn`, given that the fees are
        // known.
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            tokenB,
            tokenA,
            exactAmountOutDo + feesTokenB,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn - feesTokenA, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx] - feesTokenA,
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx] - feesTokenB,
            "Wrong sender tokenB balance"
        );
    }

    function testDoExactOutUndoExactOutNoFees__Fuzz(uint256 exactAmountOut) public {
        exactAmountOut = bound(exactAmountOut, minSwapAmountTokenB, maxSwapAmountTokenB);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            tokenA,
            tokenB,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            tokenB,
            tokenA,
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
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx],
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "Wrong sender tokenB balance"
        );
    }

    function testDoExactOutUndoExactOutLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountOut = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            tokenA,
            tokenB,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            tokenB,
            tokenA,
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
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx],
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "Wrong sender tokenB balance"
        );
    }

    function testDoExactOutUndoExactOutVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
        uint256 exactAmountOut = maxSwapAmountTokenB;
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            tokenA,
            tokenB,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (tokenB) + feesTokenA (tokenA). So, if
        // there were no fees, trading `exactAmountInDo - feesTokenA` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesTokenA` is comparable with `exactAmountOut`, given that the fees are
        // known.
        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            tokenB,
            tokenA,
            exactAmountInDo - feesTokenA,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut + feesTokenB, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx] - feesTokenA,
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx] - feesTokenB,
            "Wrong sender tokenB balance"
        );
    }

    function testDoExactOutUndoExactOutVariableFeesAmountOutAndLiquidity__Fuzz(
        uint256 exactAmountOut,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB
    ) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        uint256 maxAmountOut = (liquidityTokenA > liquidityTokenB ? liquidityTokenB : liquidityTokenA) / 4;

        exactAmountOut = bound(exactAmountOut, minSwapAmountTokenB, maxAmountOut);
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityTokenA, liquidityTokenB].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            tokenA,
            tokenB,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (tokenB) + feesTokenA (tokenA). So, if
        // there were no fees, trading `exactAmountInDo - feesTokenA` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesTokenA` is comparable with `exactAmountOut`, given that the fees are
        // known.
        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            tokenB,
            tokenA,
            exactAmountInDo - feesTokenA,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut + feesTokenB, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx] - feesTokenA,
            "Wrong sender tokenA balance"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx] - feesTokenB,
            "Wrong sender tokenB balance"
        );
    }

    function _getTokenIndexes() private view returns (uint256 idxTokenA, uint256 idxTokenB) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        // Iterate over token list because the pool may have more tokens than the 2 swapped.
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenA) {
                idxTokenA = i;
            }
            if (tokens[i] == tokenB) {
                idxTokenB = i;
            }
        }
    }
}
