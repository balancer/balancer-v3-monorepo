// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eSwapTest is BaseVaultTest {
    IERC20 internal token1;
    IERC20 internal token2;
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
        feeController.setPoolCreatorSwapFeePercentage(pool, 1e18);

        (_idxToken1, _idxToken2) = _getTokenIndexes();
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
        maxPoolSwapFeePercentage = 1e17;
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

    function testDoExactInUndoExactInVariableFees__Fuzz(uint256 exactAmountIn, uint256 poolSwapFeePercentage) public {
        exactAmountIn = bound(exactAmountIn, minSwapAmountToken1, maxSwapAmountToken1);
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

        uint256 exactAmountOutUndo = router.swapSingleTokenExactIn(
            pool,
            token2,
            token1,
            // Add fees, so the exactAmountOutUndo can be compared with `exactAmountIn - token1 fees`.
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

    function testDoExactOutUndoExactOutVariableFees__Fuzz(
        uint256 exactAmountOut,
        uint256 poolSwapFeePercentage
    ) public {
        exactAmountOut = bound(exactAmountOut, minSwapAmountToken2, maxSwapAmountToken2);
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

        uint256 exactAmountInUndo = router.swapSingleTokenExactOut(
            pool,
            token2,
            token1,
            // Remove fees, so the exactAmountInUndo can be compared with `exactAmountOut + token2 fees`.
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
