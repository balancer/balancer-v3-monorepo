// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eSwapTest is BaseVaultTest {
    using ArrayHelpers for *;

    ERC20TestToken internal token1;
    ERC20TestToken internal token2;
    uint256 private _idxToken1;
    uint256 private _idxToken2;
    address internal sender;
    address internal poolCreator;

    uint256 internal minPoolSwapFeePercentage;
    uint256 internal maxPoolSwapFeePercentage;

    uint256 internal minSwapAmountToken1;
    uint256 internal maxSwapAmountToken1;

    uint256 internal minSwapAmountToken2;
    uint256 internal maxSwapAmountToken2;

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
        feeController.setPoolCreatorSwapFeePercentage(pool, FixedPoint.ONE);

        (_idxToken1, _idxToken2) = _getTokenIndexes();

        // Donate tokens to vault, so liquidity tests are possible.
        token1.mint(address(vault), 100 * poolInitAmount);
        token2.mint(address(vault), 100 * poolInitAmount);
        // Override vault liquidity, to make sure the extra liquidity is registered.
        vault.manualSetReservesOf(token1, 100 * poolInitAmount);
        vault.manualSetReservesOf(token2, 100 * poolInitAmount);
    }

    /**
     * @notice Set up test variables (tokens, pool swap fee, swap sizes).
     * @dev When extending the test, override this function and set the same variables.
     */
    function _setUpVariables() internal virtual {
        token1 = dai;
        token2 = usdc;
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountToken1 = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountToken1 = poolInitAmount;

        minSwapAmountToken2 = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountToken2 = poolInitAmount;

        // 0.0001% min swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 10e16;
    }

    function testDoExactInUndoExactInNoFees__Fuzz(uint256 exactAmountIn) public {
        exactAmountIn = bound(exactAmountIn, minSwapAmountToken1, maxSwapAmountToken1);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            token1,
            token2,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            token2,
            token1,
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
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1],
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2],
            "Wrong sender token2 balance"
        );
    }

    function testDoExactInUndoExactInLiquidity__Fuzz(uint256 liquidityToken1, uint256 liquidityToken2) public {
        liquidityToken1 = bound(liquidityToken1, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityToken2 = bound(liquidityToken2, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of token1 or token2 liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountIn = (liquidityToken1 > liquidityToken2 ? liquidityToken2 : liquidityToken1) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityToken1, liquidityToken2].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            token1,
            token2,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            token2,
            token1,
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
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1],
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2],
            "Wrong sender token2 balance"
        );
    }

    function testDoExactInUndoExactInVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
        uint256 exactAmountIn = maxSwapAmountToken1;
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            token1,
            token2,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesToken2 = vault.getAggregateSwapFeeAmount(pool, token2);

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesToken2. So, if
        // there were no fees, trading `exactAmountOutDo + feesToken2` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesToken2` is comparable with `exactAmountIn`, given that the fees are
        // known.
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            token2,
            token1,
            exactAmountOutDo + feesToken2,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesToken1 = vault.getAggregateSwapFeeAmount(pool, token1);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn - feesToken1, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1] - feesToken1,
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2] - feesToken2,
            "Wrong sender token2 balance"
        );
    }

    function testDoExactInUndoExactInVariableFeesAmountInAndLiquidity__Fuzz(
        uint256 exactAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 liquidityToken1,
        uint256 liquidityToken2
    ) public {
        liquidityToken1 = bound(liquidityToken1, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityToken2 = bound(liquidityToken2, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of token1 or token2 liquidity, the lowest value, to make sure the swap is executed.
        uint256 maxAmountIn = (liquidityToken1 > liquidityToken2 ? liquidityToken2 : liquidityToken1) / 4;

        exactAmountIn = bound(exactAmountIn, minSwapAmountToken1, maxAmountIn);
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityToken1, liquidityToken2].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountOutDo = router.swapSingleTokenExactIn(
            pool,
            token1,
            token2,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesToken2 = vault.getAggregateSwapFeeAmount(pool, token2);

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesToken2. So, if
        // there were no fees, trading `exactAmountOutDo + feesToken2` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesToken2` is comparable with `exactAmountIn`, given that the fees are
        // known.
        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            token2,
            token1,
            exactAmountOutDo + feesToken2,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesToken1 = vault.getAggregateSwapFeeAmount(pool, token1);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertLe(exactAmountOutUndo, exactAmountIn - feesToken1, "Amount out undo should be <= exactAmountIn");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1] - feesToken1,
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2] - feesToken2,
            "Wrong sender token2 balance"
        );
    }

    function testDoExactOutUndoExactOutNoFees__Fuzz(uint256 exactAmountOut) public {
        exactAmountOut = bound(exactAmountOut, minSwapAmountToken2, maxSwapAmountToken2);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            token1,
            token2,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            token2,
            token1,
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
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1],
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2],
            "Wrong sender token2 balance"
        );
    }

    function testDoExactOutUndoExactOutLiquidity__Fuzz(uint256 liquidityToken1, uint256 liquidityToken2) public {
        liquidityToken1 = bound(liquidityToken1, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityToken2 = bound(liquidityToken2, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of token1 or token2 liquidity, the lowest value, to make sure the swap is executed.
        uint256 exactAmountOut = (liquidityToken1 > liquidityToken2 ? liquidityToken2 : liquidityToken1) / 4;

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityToken1, liquidityToken2].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            token1,
            token2,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            token2,
            token1,
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
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1],
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2],
            "Wrong sender token2 balance"
        );
    }

    function testDoExactOutUndoExactOutVariableFees__Fuzz(uint256 poolSwapFeePercentage) public {
        uint256 exactAmountOut = maxSwapAmountToken2;
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            token1,
            token2,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesToken1 = vault.getAggregateSwapFeeAmount(pool, token1);

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (token2) + feesToken1 (token1). So, if
        // there were no fees, trading `exactAmountInDo - feesToken1` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesToken1` is comparable with `exactAmountOut`, given that the fees are
        // known.
        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            token2,
            token1,
            exactAmountInDo - feesToken1,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesToken2 = vault.getAggregateSwapFeeAmount(pool, token2);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut + feesToken2, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1] - feesToken1,
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2] - feesToken2,
            "Wrong sender token2 balance"
        );
    }

    function testDoExactOutUndoExactOutVariableFeesAmountOutAndLiquidity__Fuzz(
        uint256 exactAmountOut,
        uint256 poolSwapFeePercentage,
        uint256 liquidityToken1,
        uint256 liquidityToken2
    ) public {
        liquidityToken1 = bound(liquidityToken1, poolInitAmount / 10, 10 * poolInitAmount);
        liquidityToken2 = bound(liquidityToken2, poolInitAmount / 10, 10 * poolInitAmount);

        // 25% of token1 or token2 liquidity, the lowest value, to make sure the swap is executed.
        uint256 maxAmountOut = (liquidityToken1 > liquidityToken2 ? liquidityToken2 : liquidityToken1) / 4;

        exactAmountOut = bound(exactAmountOut, minSwapAmountToken2, maxAmountOut);
        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);

        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        // Set liquidity of pool.
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        uint256[] memory newPoolBalance = [liquidityToken1, liquidityToken2].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalance);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender);

        vm.startPrank(sender);
        uint256 exactAmountInDo = router.swapSingleTokenExactOut(
            pool,
            token1,
            token2,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );

        uint256 feesToken1 = vault.getAggregateSwapFeeAmount(pool, token1);

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (token2) + feesToken1 (token1). So, if
        // there were no fees, trading `exactAmountInDo - feesToken1` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesToken1` is comparable with `exactAmountOut`, given that the fees are
        // known.
        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            token2,
            token1,
            exactAmountInDo - feesToken1,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesToken2 = vault.getAggregateSwapFeeAmount(pool, token2);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender);

        assertGe(exactAmountInUndo, exactAmountOut + feesToken2, "Amount in undo should be >= exactAmountOut");
        // Since it was a do/undo operation, the user balance of each token cannot be greater than before.
        assertLe(
            balancesAfter.userTokens[_idxToken1],
            balancesBefore.userTokens[_idxToken1] - feesToken1,
            "Wrong sender token1 balance"
        );
        assertLe(
            balancesAfter.userTokens[_idxToken2],
            balancesBefore.userTokens[_idxToken2] - feesToken2,
            "Wrong sender token2 balance"
        );
    }

    function _getTokenIndexes() private view returns (uint256 idxToken1, uint256 idxToken2) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        // Iterate over token list because the pool may have more tokens than the 2 swapped.
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token1) {
                idxToken1 = i;
            }
            if (tokens[i] == token2) {
                idxToken2 = i;
            }
        }
    }
}
