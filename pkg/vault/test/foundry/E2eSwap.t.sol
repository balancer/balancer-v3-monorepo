// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eSwapTest is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    ERC20TestToken internal tokenA;
    ERC20TestToken internal tokenB;
    uint256 internal tokenAIdx;
    uint256 internal tokenBIdx;

    uint256 internal decimalsTokenA;
    uint256 internal decimalsTokenB;
    uint256 internal poolInitAmountTokenA;
    uint256 internal poolInitAmountTokenB;

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

        // Tokens must be set before other variables, so the variables can be calculated based on tokens.
        setUpTokens();

        (tokenAIdx, tokenBIdx) = getSortedIndexes(address(tokenA), address(tokenB));

        decimalsTokenA = IERC20Metadata(address(tokenA)).decimals();
        decimalsTokenB = IERC20Metadata(address(tokenB)).decimals();
        poolInitAmountTokenA = poolInitAmount.mulDown(10 ** decimalsTokenA);
        poolInitAmountTokenB = poolInitAmount.mulDown(10 ** decimalsTokenB);

        setUpVariables();
        createAndInitCustomPool();

        _donateToVault();

        IProtocolFeeController feeController = vault.getProtocolFeeController();
        IAuthentication feeControllerAuth = IAuthentication(address(feeController));

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        // Set protocol and creator fees to 50%, so we can measure the charged fees.
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(FIFTY_PERCENT);

        vm.prank(poolCreator);
        // Set pool creator fee to 100%, so protocol + creator fees equals the total charged fees.
        feeController.setPoolCreatorSwapFeePercentage(pool, FixedPoint.ONE);
    }

    /**
     * @notice Override pool created by BaseVaultTest
     * @dev For this test to be generic and support tokens with different decimals, tokenA and tokenB must be set by
     * _setUpVariables function. If this function runs before `BaseVaultTest.setUp()`, in the `setUp()` function, tokens
     * defined by BaseTest (like dai and usdc) cannot be used. If it runs after, we don't know which tokens are used to
     * use createPool and initPool. So, the solution is to create a parallel function to create and init a custom pool
     * after BaseVaultTest setUp finishes.
     */
    function createAndInitCustomPool() internal virtual {
        pool = _createPool([address(tokenA), address(tokenB)].toMemoryArray(), "custom-pool");

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[tokenAIdx] = poolInitAmountTokenA;
        initAmounts[tokenBIdx] = poolInitAmountTokenB;

        vm.startPrank(lp);
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();
    }

    /**
     * @notice Set up tokens.
     * @dev When extending the test, override this function and set the same variables.
     */
    function setUpTokens() internal virtual {
        tokenA = dai;
        tokenB = usdc;
    }

    /**
     * @notice Set up test variables (sender, poolCreator, pool swap fee, swap sizes).
     * @dev When extending the test, override this function and set the same variables.
     */
    function setUpVariables() internal virtual {
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 10 creates a margin.
        minSwapAmountTokenA = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenA = poolInitAmountTokenA;

        minSwapAmountTokenB = 10 * MIN_TRADE_AMOUNT;
        maxSwapAmountTokenB = poolInitAmountTokenB;

        // 0.0001% min swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 10e16;
    }

    /// @notice Donate tokens to vault, so liquidity tests are possible.
    function _donateToVault() internal virtual {
        tokenA.mint(address(vault), 100 * poolInitAmountTokenA);
        tokenB.mint(address(vault), 100 * poolInitAmountTokenB);
        // Override vault liquidity, to make sure the extra liquidity is registered.
        vault.manualSetReservesOf(tokenA, 100 * poolInitAmountTokenA);
        vault.manualSetReservesOf(tokenB, 100 * poolInitAmountTokenB);
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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, 0, 0);
    }

    function testDoExactInUndoExactInLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmountTokenA / 10, 10 * poolInitAmountTokenA);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmountTokenB / 10, 10 * poolInitAmountTokenB);

        uint256 exactAmountIn = _setPoolBalancesAndGetAmountIn(liquidityTokenA, liquidityTokenB);

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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, 0, 0);
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
        // with exact_in `exactAmountOutDo + feesTokenB` is comparable to `exactAmountIn`, given that the fees are
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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
    }

    function testDoExactInUndoExactInVariableFeesAmountInAndLiquidity__Fuzz(
        uint256 exactAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB
    ) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmountTokenA / 10, 10 * poolInitAmountTokenA);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmountTokenB / 10, 10 * poolInitAmountTokenB);

        uint256 maxAmountIn = _setPoolBalancesAndGetAmountIn(liquidityTokenA, liquidityTokenB);

        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxAmountIn);
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
        // with exact_in `exactAmountOutDo + feesTokenB` is comparable to `exactAmountIn`, given that the fees are
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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, 0, 0);
    }

    function testDoExactOutUndoExactOutLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmountTokenA / 10, 10 * poolInitAmountTokenA);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmountTokenB / 10, 10 * poolInitAmountTokenB);

        uint256 exactAmountOut = _setPoolBalancesAndGetAmountOut(liquidityTokenA, liquidityTokenB);

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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, 0, 0);
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
        // with exact_out `exactAmountInDo - feesTokenA` is comparable to `exactAmountOut`, given that the fees are
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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
    }

    function testDoExactOutUndoExactOutVariableFeesAmountOutAndLiquidity__Fuzz(
        uint256 exactAmountOut,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB
    ) public {
        liquidityTokenA = bound(liquidityTokenA, poolInitAmountTokenA / 10, 10 * poolInitAmountTokenA);
        liquidityTokenB = bound(liquidityTokenB, poolInitAmountTokenB / 10, 10 * poolInitAmountTokenB);

        uint256 maxAmountOut = _setPoolBalancesAndGetAmountOut(liquidityTokenA, liquidityTokenB);
        exactAmountOut = bound(exactAmountOut, minSwapAmountTokenB, maxAmountOut);

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
        // with exact_out `exactAmountInDo - feesTokenA` is comparable to `exactAmountOut`, given that the fees are
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

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
    }

    function testExactInRepeatExactOutNoFees__Fuzz(uint256 exactAmountIn) public {
        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxSwapAmountTokenA);

        // Set swap fees to 0 (do not check pool fee percentage limits, some pool types do not accept 0 fees).
        vault.manualUnsafeSetStaticSwapFeePercentage(pool, 0);

        vm.startPrank(sender);
        uint256 snapshotId = vm.snapshot();
        uint256 exactAmountOut = router.swapSingleTokenExactIn(
            pool,
            tokenA,
            tokenB,
            exactAmountIn,
            0,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.revertTo(snapshotId);
        uint256 exactAmountInSwap = router.swapSingleTokenExactOut(
            pool,
            tokenA,
            tokenB,
            exactAmountOut,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        vm.stopPrank();

        if (decimalsTokenA != decimalsTokenB) {
            // If tokens have different decimals, `computeBalance` will be off by an order of magnitude proportional to the difference in decimals.
            uint256 tolerance;
            if (decimalsTokenA < decimalsTokenB) {
                tolerance = 10 ** (decimalsTokenB - decimalsTokenA + 1);
            } else {
                tolerance = 10 ** (decimalsTokenA - decimalsTokenB + 1);
            }
            assertApproxEqAbs(
                exactAmountInSwap,
                exactAmountIn,
                tolerance,
                "ExactOut and ExactIn amountsIn should match"
            );
        } else {
            // Accepts an error of 0.0000001% between amountIn from ExactOut and ExactIn swaps. This error is caused by
            // differences in the computeInGivenExactOut and computeOutGivenExactIn functions of the pool math.
            assertApproxEqRel(exactAmountInSwap, exactAmountIn, 1e9, "ExactOut and ExactIn amountsIn should match");
        }
    }

    function testExactInRepeatExactOutVariableFees__Fuzz(uint256 exactAmountIn, uint256 poolSwapFeePercentage) public {
        exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxSwapAmountTokenA);

        poolSwapFeePercentage = bound(poolSwapFeePercentage, minPoolSwapFeePercentage, maxPoolSwapFeePercentage);
        vault.manualSetStaticSwapFeePercentage(pool, poolSwapFeePercentage);

        vm.startPrank(sender);
        uint256 snapshotId = vm.snapshot();
        uint256 exactAmountOut = router.swapSingleTokenExactIn(
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

        vm.revertTo(snapshotId);
        uint256 exactAmountInSwap = router.swapSingleTokenExactOut(
            pool,
            tokenA,
            tokenB,
            exactAmountOut + feesTokenB,
            MAX_UINT128,
            MAX_UINT128,
            false,
            bytes("")
        );
        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
        vm.stopPrank();

        if (decimalsTokenA != decimalsTokenB) {
            // If tokens have different decimals, an error is introduced in the computeBalance in the order of the
            // difference of the decimals.
            uint256 tolerance;
            if (decimalsTokenA < decimalsTokenB) {
                tolerance = 10 ** (decimalsTokenB - decimalsTokenA + 1);
            } else {
                tolerance = 10 ** (decimalsTokenA - decimalsTokenB + 1);
            }
            assertApproxEqAbs(
                exactAmountInSwap - feesTokenA,
                exactAmountIn,
                tolerance,
                "ExactOut and ExactIn amountsIn should match"
            );
        } else {
            // Accepts an error of 0.0000001% between amountIn from ExactOut and ExactIn swaps. This error is caused by
            // differences in the computeInGivenOut and computeOutGivenIn functions of the pool math.
            assertApproxEqRel(
                exactAmountInSwap - feesTokenA,
                exactAmountIn,
                1e9,
                "ExactOut and ExactIn amountsIn should match"
            );
        }
    }

    function _checkUserBalancesAndPoolInvariant(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256 feesTokenA,
        uint256 feesTokenB
    ) internal view {
        // Pool invariant cannot decrease after the swaps. All fees should be paid by the user.
        assertGe(balancesAfter.poolInvariant, balancesBefore.poolInvariant, "Pool invariant is smaller than before");

        // The user balance of each token cannot be greater than before because the swap and the reversed swap were
        // executed. Also, fees were paid to the protocol and pool creator, so make sure the user paid for them.
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

        // The vault balance of each token cannot be smaller than before because the swap and the reversed swap were
        // executed.
        assertGe(
            balancesAfter.vaultTokens[tokenAIdx],
            balancesBefore.vaultTokens[tokenAIdx],
            "Wrong vault tokenA balance"
        );
        assertGe(
            balancesAfter.vaultTokens[tokenBIdx],
            balancesBefore.vaultTokens[tokenBIdx],
            "Wrong vault tokenB balance"
        );
    }

    function _setPoolBalancesAndGetAmountIn(
        uint256 liquidityTokenA,
        uint256 liquidityTokenB
    ) private returns (uint256 amountIn) {
        // Set pool liquidity.
        _setPoolBalances(liquidityTokenA, liquidityTokenB);

        // Since tokens can have different decimals and amountIn is in relation to tokenA, normalize tokenB liquidity.
        uint256 normalizedLiquidityTokenB = (liquidityTokenB * (10 ** decimalsTokenA)) / (10 ** decimalsTokenB);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        amountIn = (liquidityTokenA > normalizedLiquidityTokenB ? normalizedLiquidityTokenB : liquidityTokenA) / 4;
    }

    function _setPoolBalancesAndGetAmountOut(
        uint256 liquidityTokenA,
        uint256 liquidityTokenB
    ) private returns (uint256 amountOut) {
        // Set liquidity of pool.
        _setPoolBalances(liquidityTokenA, liquidityTokenB);

        // Since tokens can have different decimals and amountOut is in relation to tokenB, normalize tokenA liquidity.
        uint256 normalizedLiquidityTokenA = (liquidityTokenA * (10 ** decimalsTokenB)) / (10 ** decimalsTokenA);

        // 25% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        amountOut = (normalizedLiquidityTokenA > liquidityTokenB ? liquidityTokenB : normalizedLiquidityTokenA) / 4;
    }

    function _setPoolBalances(uint256 liquidityTokenA, uint256 liquidityTokenB) private {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);

        uint256[] memory newPoolBalance = new uint256[](2);
        newPoolBalance[tokenAIdx] = liquidityTokenA;
        newPoolBalance[tokenBIdx] = liquidityTokenB;

        // Rate is 1, so we just need to compare 18 with token decimals to scale each liquidity accordingly.
        uint256[] memory newPoolBalanceLiveScaled18 = new uint256[](2);
        newPoolBalanceLiveScaled18[tokenAIdx] = liquidityTokenA * 10 ** (18 - decimalsTokenA);
        newPoolBalanceLiveScaled18[tokenBIdx] = liquidityTokenB * 10 ** (18 - decimalsTokenB);

        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalanceLiveScaled18);
    }
}
