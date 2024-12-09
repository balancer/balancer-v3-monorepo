// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";
import { ProtocolFeeControllerMock } from "../../contracts/test/ProtocolFeeControllerMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract E2eSwapTest is BaseVaultTest {
    using ScalingHelpers for uint256;
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

    // We theoretically support the full range of token decimals, but tokens with extreme values don't tend to perform
    // well in AMMs, due to precision issues with their math. The lowest decimal value in common use would be 6,
    // used by many centralized stable coins (e.g., USDC). Some popular wrapped tokens have 8 (e.g., WBTC).
    uint256 private constant _LOW_DECIMAL_LIMIT = 6;

    function setUp() public virtual override {
        // We will use min trade amount in this test.
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;

        BaseVaultTest.setUp();

        // Tokens must be set before other variables, so the variables can be calculated based on tokens.
        setUpTokens();
        decimalsTokenA = IERC20Metadata(address(tokenA)).decimals();
        decimalsTokenB = IERC20Metadata(address(tokenB)).decimals();

        (tokenAIdx, tokenBIdx) = getSortedIndexes(address(tokenA), address(tokenB));

        // Pool Init Amount values are needed to set up variables that rely on the initial pool state.
        setPoolInitAmounts();

        setUpVariables();
        calculateMinAndMaxSwapAmounts();
        createAndInitCustomPool();

        // Donate tokens to vault as a shortcut to change the pool balances without the need to pass through add/remove
        // liquidity operations. (No need to deal with BPTs, pranking LPs, guardrails, etc).
        _donateToVault();

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        IAuthentication feeControllerAuth = IAuthentication(address(feeController));

        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );

        vm.prank(poolCreator);
        // Set pool creator fee to 100% bypassing checks, so protocol + creator fees = the total charged fees.
        feeController.manualSetPoolCreatorSwapFeePercentage(pool, FixedPoint.ONE);

        minPoolSwapFeePercentage = IBasePool(pool).getMinimumSwapFeePercentage();
        maxPoolSwapFeePercentage = IBasePool(pool).getMaximumSwapFeePercentage();

        // These tests rely on a minimum fee to work; set something very small for pool mock.
        minPoolSwapFeePercentage = (minPoolSwapFeePercentage == 0 ? 1e12 : minPoolSwapFeePercentage);
        maxPoolSwapFeePercentage = (maxPoolSwapFeePercentage == 1e18 ? 10e16 : maxPoolSwapFeePercentage);
    }

    /**
     * @notice Override pool created by BaseVaultTest.
     * @dev For this test to be generic and support tokens with different decimals, tokenA and tokenB must be set by
     * `setUpTokens`. If this function runs before `BaseVaultTest.setUp()`, in the `setUp()` function, tokens defined
     * by BaseTest (like dai and usdc) cannot be used. If it runs after, we don't know which tokens are used by
     * createPool and initPool. So, the solution is to create a parallel function to create and initialize a custom
     * pool after the BaseVaultTest setUp finishes.

     */
    function createAndInitCustomPool() internal virtual {
        address[] memory tokens = new address[](2);
        tokens[tokenAIdx] = address(tokenA);
        tokens[tokenBIdx] = address(tokenB);
        (pool, ) = _createPool(tokens, "custom-pool");

        setPoolInitAmounts();

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
     * @notice Set up test variables (sender and poolCreator).
     * @dev When extending the test, override this function and set the same variables.
     */
    function setUpVariables() internal virtual {
        sender = lp;
        poolCreator = lp;
    }

    function calculateMinAndMaxSwapAmounts() internal virtual {
        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // The vault does not allow trade amounts (amountGivenScaled18 or amountCalculatedScaled18) to be less than
        // PRODUCTION_MIN_TRADE_AMOUNT. For "linear" pools (PoolMock), amountGivenScaled18 and amountCalculatedScaled18
        // are the same. So, minAmountGivenScaled18 > PRODUCTION_MIN_TRADE_AMOUNT. To derive the formula below, note
        // that `amountGivenRaw = amountGivenScaled18/(rateToken * scalingFactor)`.
        uint256 tokenAMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenA).mulUp(10 ** decimalsTokenA);
        uint256 tokenBMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT.divUp(rateTokenB).mulUp(10 ** decimalsTokenB);

        // Also, since we undo the operation (reverse swap with the output of the first swap), amountCalculatedRaw
        // cannot be 0. Considering that amountCalculated is tokenB, and amountGiven is tokenA:
        // 1) amountCalculatedRaw > 0
        // 2) amountCalculatedRaw = amountCalculatedScaled18 * 10^(decimalsB) / (rateB * 10^18)
        // 3) amountCalculatedScaled18 = amountGivenScaled18 // Linear math
        // 4) amountGivenScaled18 = amountGivenRaw * rateA * 10^18 / 10^(decimalsA)
        // Combining the four formulas above, we determine that:
        // amountCalculatedRaw > rateB * 10^(decimalsA) / (rateA * 10^(decimalsB))
        uint256 tokenACalculatedNotZero = (rateTokenB * (10 ** decimalsTokenA)) / (rateTokenA * (10 ** decimalsTokenB));
        uint256 tokenBCalculatedNotZero = (rateTokenA * (10 ** decimalsTokenB)) / (rateTokenB * (10 ** decimalsTokenA));

        // Use the larger of the two values above to calculate the minSwapAmount. Also, multiply by 10 to account for
        // swap fees and compensate for rate rounding issues.
        uint256 feeFactor = 10;
        minSwapAmountTokenA = (
            tokenAMinTradeAmount > tokenACalculatedNotZero
                ? feeFactor * tokenAMinTradeAmount
                : feeFactor * tokenACalculatedNotZero
        );
        minSwapAmountTokenB = (
            tokenBMinTradeAmount > tokenBCalculatedNotZero
                ? feeFactor * tokenBMinTradeAmount
                : feeFactor * tokenBCalculatedNotZero
        );

        // 99% of pool init amount, to avoid rounding issues near the full liquidity of the pool.
        maxSwapAmountTokenA = poolInitAmountTokenA.mulDown(99e16);
        maxSwapAmountTokenB = poolInitAmountTokenB.mulDown(99e16);
    }

    /// @notice Donate tokens to vault, so liquidity tests are possible.
    function _donateToVault() internal virtual {
        tokenA.mint(address(vault), 100 * poolInitAmountTokenA);
        tokenB.mint(address(vault), 100 * poolInitAmountTokenB);
        // Override vault liquidity, to make sure the extra liquidity is registered.
        vault.manualSetReservesOf(tokenA, 100 * poolInitAmountTokenA);
        vault.manualSetReservesOf(tokenB, 100 * poolInitAmountTokenB);
    }

    /// @dev Override this function to introduce custom rates and rate providers.
    function getRate(IERC20) internal view virtual returns (uint256) {
        return FixedPoint.ONE;
    }

    function testDoUndoExactInSwapAmount__Fuzz(uint256 exactAmountIn) public {
        DoUndoLocals memory testLocals;

        testDoUndoExactInBase(exactAmountIn, testLocals);
    }

    function testDoUndoExactInLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.liquidityTokenA = liquidityTokenA;
        testLocals.liquidityTokenB = liquidityTokenB;

        uint256 exactAmountIn = maxSwapAmountTokenA;

        testDoUndoExactInBase(exactAmountIn, testLocals);
    }

    function testDoUndoExactInFees__Fuzz(uint256 poolSwapFeePercentage) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestFee = true;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        uint256 exactAmountIn = maxSwapAmountTokenA;

        testDoUndoExactInBase(exactAmountIn, testLocals);
    }

    function testDoUndoExactInDecimals__Fuzz(uint256 newDecimalsTokenA, uint256 newDecimalsTokenB) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestDecimals = true;
        testLocals.newDecimalsTokenA = newDecimalsTokenA;
        testLocals.newDecimalsTokenB = newDecimalsTokenB;

        uint256 exactAmountIn = maxSwapAmountTokenA;

        testDoUndoExactInBase(exactAmountIn, testLocals);
    }

    function testDoUndoExactInComplete__Fuzz(
        uint256 exactAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB,
        uint256 newDecimalsTokenA,
        uint256 newDecimalsTokenB
    ) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestDecimals = true;
        testLocals.shouldTestLiquidity = true;
        testLocals.shouldTestSwapAmount = true;
        testLocals.shouldTestFee = true;
        testLocals.liquidityTokenA = liquidityTokenA;
        testLocals.liquidityTokenB = liquidityTokenB;
        testLocals.newDecimalsTokenA = newDecimalsTokenA;
        testLocals.newDecimalsTokenB = newDecimalsTokenB;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        testDoUndoExactInBase(exactAmountIn, testLocals);
    }

    function testDoUndoExactOutSwapAmount__Fuzz(uint256 exactAmountOut) public {
        DoUndoLocals memory testLocals;

        testDoUndoExactOutBase(exactAmountOut, testLocals);
    }

    function testDoUndoExactOutLiquidity__Fuzz(uint256 liquidityTokenA, uint256 liquidityTokenB) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestLiquidity = true;
        testLocals.liquidityTokenA = liquidityTokenA;
        testLocals.liquidityTokenB = liquidityTokenB;

        uint256 exactAmountOut = maxSwapAmountTokenB;

        testDoUndoExactOutBase(exactAmountOut, testLocals);
    }

    function testDoUndoExactOutFees__Fuzz(uint256 poolSwapFeePercentage) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestFee = true;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        uint256 exactAmountOut = maxSwapAmountTokenB;

        testDoUndoExactOutBase(exactAmountOut, testLocals);
    }

    function testDoUndoExactOutDecimals__Fuzz(uint256 newDecimalsTokenA, uint256 newDecimalsTokenB) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestDecimals = true;
        testLocals.newDecimalsTokenA = newDecimalsTokenA;
        testLocals.newDecimalsTokenB = newDecimalsTokenB;

        uint256 exactAmountOut = maxSwapAmountTokenB;

        testDoUndoExactOutBase(exactAmountOut, testLocals);
    }

    function testDoUndoExactOutComplete__Fuzz(
        uint256 exactAmountOut,
        uint256 poolSwapFeePercentage,
        uint256 liquidityTokenA,
        uint256 liquidityTokenB,
        uint256 newDecimalsTokenA,
        uint256 newDecimalsTokenB
    ) public {
        DoUndoLocals memory testLocals;
        testLocals.shouldTestDecimals = true;
        testLocals.shouldTestLiquidity = true;
        testLocals.shouldTestSwapAmount = true;
        testLocals.shouldTestFee = true;
        testLocals.liquidityTokenA = liquidityTokenA;
        testLocals.liquidityTokenB = liquidityTokenB;
        testLocals.newDecimalsTokenA = newDecimalsTokenA;
        testLocals.newDecimalsTokenB = newDecimalsTokenB;
        testLocals.poolSwapFeePercentage = poolSwapFeePercentage;

        testDoUndoExactOutBase(exactAmountOut, testLocals);
    }

    function testExactInRepeatExactOutVariableFees__Fuzz(
        uint256 exactAmountIn,
        uint256 poolSwapFeePercentage,
        uint256 newDecimalsTokenA,
        uint256 newDecimalsTokenB
    ) public {
        decimalsTokenA = bound(newDecimalsTokenA, _LOW_DECIMAL_LIMIT, 18);
        decimalsTokenB = bound(newDecimalsTokenB, _LOW_DECIMAL_LIMIT, 18);

        _setTokenDecimalsInPool();

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

        if (decimalsTokenA != decimalsTokenB || exactAmountIn < PRODUCTION_MIN_TRADE_AMOUNT) {
            // If tokens have different decimals, an error is introduced in the computeBalance in the order of the
            // difference of the decimals.
            uint256 tolerance;
            if (decimalsTokenA < decimalsTokenB) {
                // Add 3 to give some extra tolerance for weighted pools (multiply by 1000).
                tolerance = 10 ** (decimalsTokenB - decimalsTokenA + 3);
            } else {
                // Add 3 to give some extra tolerance for weighted pools (multiply by 1000).
                tolerance = 10 ** (decimalsTokenA - decimalsTokenB + 3);
            }

            assertApproxEqAbs(
                exactAmountIn,
                exactAmountInSwap,
                tolerance,
                "ExactOut and ExactIn amountsIn should match"
            );
        } else {
            // Accepts an error of 0.0002% between amountIn from ExactOut and ExactIn swaps. This error is caused by
            // differences in the computeInGivenOut and computeOutGivenIn functions of the pool math (for small
            // amounts the error can be a bit above 0.0001%).
            assertApproxEqRel(exactAmountIn, exactAmountInSwap, 2e12, "ExactOut and ExactIn amountsIn should match");
        }
    }

    struct DoUndoLocals {
        bool shouldTestDecimals;
        bool shouldTestLiquidity;
        bool shouldTestSwapAmount;
        bool shouldTestFee;
        uint256 liquidityTokenA;
        uint256 liquidityTokenB;
        uint256 newDecimalsTokenA;
        uint256 newDecimalsTokenB;
        uint256 poolSwapFeePercentage;
    }

    function testDoUndoExactInBase(uint256 exactAmountIn, DoUndoLocals memory testLocals) internal {
        if (testLocals.shouldTestDecimals) {
            decimalsTokenA = bound(testLocals.newDecimalsTokenA, _LOW_DECIMAL_LIMIT, 18);
            decimalsTokenB = bound(testLocals.newDecimalsTokenB, _LOW_DECIMAL_LIMIT, 18);

            _setTokenDecimalsInPool();
        }

        uint256 maxAmountIn = maxSwapAmountTokenA;
        if (testLocals.shouldTestLiquidity) {
            testLocals.liquidityTokenA = bound(
                testLocals.liquidityTokenA,
                poolInitAmountTokenA / 10,
                10 * poolInitAmountTokenA
            );
            testLocals.liquidityTokenB = bound(
                testLocals.liquidityTokenB,
                poolInitAmountTokenB / 10,
                10 * poolInitAmountTokenB
            );

            maxAmountIn = _setPoolBalancesAndGetAmountIn(testLocals.liquidityTokenA, testLocals.liquidityTokenB);
        }

        if (testLocals.shouldTestSwapAmount) {
            // If the liquidity is very small for one of the tokens and decimals are small too, the maxAmountIn may be
            // smaller than minSwapAmount (usually 10^7), so just overwrite it.
            if (minSwapAmountTokenA > maxAmountIn) {
                exactAmountIn = maxAmountIn;
            } else {
                exactAmountIn = bound(exactAmountIn, minSwapAmountTokenA, maxAmountIn);
            }
        } else {
            exactAmountIn = maxAmountIn;
        }

        if (testLocals.shouldTestFee) {
            testLocals.poolSwapFeePercentage = bound(
                testLocals.poolSwapFeePercentage,
                minPoolSwapFeePercentage,
                maxPoolSwapFeePercentage
            );
        } else {
            testLocals.poolSwapFeePercentage = minPoolSwapFeePercentage;
        }

        vault.manualSetStaticSwapFeePercentage(pool, testLocals.poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender, Rounding.ROUND_DOWN);

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

        {
            // If the amount given is below the guardrail, don't continue.
            uint256 rateTokenB = getRate(tokenB);
            uint256 decimalScalingFactorTokenB = 10 ** (18 - decimalsTokenB);
            vm.assume(
                exactAmountOutDo.toScaled18ApplyRateRoundDown(decimalScalingFactorTokenB, rateTokenB).mulDown(
                    testLocals.poolSwapFeePercentage.complement()
                ) > vaultMockMinTradeAmount
            );
        }

        // In the first swap, the trade was exactAmountIn => exactAmountOutDo + feesTokenB. So, if
        // there were no fees, trading `exactAmountOutDo + feesTokenB` would get exactAmountIn. Therefore, a swap
        // with exact_in `exactAmountOutDo + feesTokenB` is comparable to `exactAmountIn`, given that the fees are
        // known.
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

        vm.assume(exactAmountOutUndo > 0);

        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender, Rounding.ROUND_UP);

        // User does not get any value out of the Vault.
        assertLe(exactAmountOutUndo, exactAmountIn - feesTokenA, "Amount out undo should be <= exactAmountIn");

        // - Token B should have been round-tripped with exact amounts
        // - Token A should have less balance after
        assertEq(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "User did not end up with the same amount of B tokens"
        );
        assertLe(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx],
            "User ended up with more A tokens"
        );

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
    }

    function testDoUndoExactOutBase(uint256 exactAmountOut, DoUndoLocals memory testLocals) internal {
        if (testLocals.shouldTestDecimals) {
            decimalsTokenA = bound(testLocals.newDecimalsTokenA, _LOW_DECIMAL_LIMIT, 18);
            decimalsTokenB = bound(testLocals.newDecimalsTokenB, _LOW_DECIMAL_LIMIT, 18);

            _setTokenDecimalsInPool();
        }

        uint256 maxAmountOut = maxSwapAmountTokenB;
        if (testLocals.shouldTestLiquidity) {
            testLocals.liquidityTokenA = bound(
                testLocals.liquidityTokenA,
                poolInitAmountTokenA / 10,
                10 * poolInitAmountTokenA
            );
            testLocals.liquidityTokenB = bound(
                testLocals.liquidityTokenB,
                poolInitAmountTokenB / 10,
                10 * poolInitAmountTokenB
            );

            maxAmountOut = _setPoolBalancesAndGetAmountOut(testLocals.liquidityTokenA, testLocals.liquidityTokenB);
        }

        if (testLocals.shouldTestSwapAmount) {
            // If the liquidity is very small for one of the tokens and decimals are small too, the maxAmountOut may be
            // smaller than minSwapAmount (usually 10^7), so just overwrite it.
            if (minSwapAmountTokenB > maxAmountOut) {
                exactAmountOut = maxAmountOut;
            } else {
                exactAmountOut = bound(exactAmountOut, minSwapAmountTokenB, maxAmountOut);
            }
        } else {
            exactAmountOut = maxAmountOut;
        }

        if (testLocals.shouldTestFee) {
            testLocals.poolSwapFeePercentage = bound(
                testLocals.poolSwapFeePercentage,
                minPoolSwapFeePercentage,
                maxPoolSwapFeePercentage
            );
        } else {
            testLocals.poolSwapFeePercentage = minPoolSwapFeePercentage;
        }

        vault.manualSetStaticSwapFeePercentage(pool, testLocals.poolSwapFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(sender, Rounding.ROUND_DOWN);

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

        {
            // If the amount given is below the guardrail, don't continue.
            uint256 rateTokenB = getRate(tokenB);
            uint256 decimalScalingFactorTokenB = 10 ** (18 - decimalsTokenB);
            vm.assume(
                exactAmountInDo.toScaled18ApplyRateRoundDown(decimalScalingFactorTokenB, rateTokenB).mulDown(
                    testLocals.poolSwapFeePercentage.complement()
                ) > vaultMockMinTradeAmount
            );
        }

        // In the first swap, the trade was exactAmountInDo => exactAmountOut (tokenB) + feesTokenA (tokenA). So, if
        // there were no fees, trading `exactAmountInDo - feesTokenA` would get exactAmountOut. Therefore, a swap
        // with exact_out `exactAmountInDo - feesTokenA` is comparable to `exactAmountOut`, given that the fees are
        // known.
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

        vm.assume(exactAmountInUndo > 0);

        uint256 feesTokenA = vault.getAggregateSwapFeeAmount(pool, tokenA);
        uint256 feesTokenB = vault.getAggregateSwapFeeAmount(pool, tokenB);
        vm.stopPrank();

        BaseVaultTest.Balances memory balancesAfter = getBalances(sender, Rounding.ROUND_UP);

        // User does not get any value out of the Vault.
        assertGe(exactAmountInUndo, exactAmountOut + feesTokenB, "Amount in undo should be >= exactAmountOut");

        // - Token A should have been round-tripped with exact amounts
        // - Token B should have less balance after
        assertEq(
            balancesAfter.userTokens[tokenAIdx],
            balancesBefore.userTokens[tokenAIdx],
            "User did not end up with the same amount of A tokens"
        );
        assertLe(
            balancesAfter.userTokens[tokenBIdx],
            balancesBefore.userTokens[tokenBIdx],
            "User ended up with more B tokens"
        );

        _checkUserBalancesAndPoolInvariant(balancesBefore, balancesAfter, feesTokenA, feesTokenB);
    }

    function _checkUserBalancesAndPoolInvariant(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256 feesTokenA,
        uint256 feesTokenB
    ) internal view {
        // Pool invariant cannot decrease after the swaps. All fees should be paid by the user.
        assertGe(balancesAfter.poolInvariant, balancesBefore.poolInvariant, "Pool invariant is smaller than before");

        vm.assume(feesTokenA > 0);
        vm.assume(feesTokenB > 0);

        // The user balance of each token cannot be greater than before because the swap and the reversed swap were
        // executed. Also, fees were paid to the protocol and pool creator, so make sure the user paid for them.
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
        setPoolBalances(liquidityTokenA, liquidityTokenB);

        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // Since tokens can have different decimals and amountIn is in relation to tokenA, normalize tokenB liquidity.
        uint256 normalizedLiquidityTokenB = (liquidityTokenB * (rateTokenB * 10 ** decimalsTokenA)) /
            (rateTokenA * 10 ** decimalsTokenB);

        // 20% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        amountIn = (liquidityTokenA > normalizedLiquidityTokenB ? normalizedLiquidityTokenB : liquidityTokenA).mulDown(
            20e16
        );
    }

    function _setPoolBalancesAndGetAmountOut(
        uint256 liquidityTokenA,
        uint256 liquidityTokenB
    ) private returns (uint256 amountOut) {
        // Set liquidity of pool.
        setPoolBalances(liquidityTokenA, liquidityTokenB);

        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // Since tokens can have different decimals and amountOut is in relation to tokenB, normalize tokenA liquidity.
        uint256 normalizedLiquidityTokenA = (liquidityTokenA * (rateTokenA * 10 ** decimalsTokenB)) /
            (rateTokenB * 10 ** decimalsTokenA);

        // 20% of tokenA or tokenB liquidity, the lowest value, to make sure the swap is executed.
        amountOut = (normalizedLiquidityTokenA > liquidityTokenB ? liquidityTokenB : normalizedLiquidityTokenA).mulDown(
            20e16
        );
    }

    function setPoolBalances(uint256 liquidityTokenA, uint256 liquidityTokenB) internal {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);

        uint256[] memory newPoolBalance = new uint256[](2);
        newPoolBalance[tokenAIdx] = liquidityTokenA;
        newPoolBalance[tokenBIdx] = liquidityTokenB;

        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        uint256[] memory newPoolBalanceLiveScaled18 = new uint256[](2);
        newPoolBalanceLiveScaled18[tokenAIdx] = liquidityTokenA.toScaled18ApplyRateRoundDown(
            10 ** (18 - decimalsTokenA),
            rateTokenA
        );
        newPoolBalanceLiveScaled18[tokenBIdx] = liquidityTokenB.toScaled18ApplyRateRoundDown(
            10 ** (18 - decimalsTokenB),
            rateTokenB
        );

        vault.manualSetPoolTokensAndBalances(pool, tokens, newPoolBalance, newPoolBalanceLiveScaled18);
    }

    function _setTokenDecimalsInPool() private {
        uint8[] memory tokenDecimalDiffs = new uint8[](2);
        tokenDecimalDiffs[tokenAIdx] = uint8(18 - decimalsTokenA);
        tokenDecimalDiffs[tokenBIdx] = uint8(18 - decimalsTokenB);

        // Token decimals are read only during the pool initialization and are then stored in the PoolConfig struct.
        // During vault operations, the decimals used to scale token amounts accordingly are read from PoolConfig.
        // This test leverages this behavior by setting the token decimals exclusively in the pool configuration.
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        poolConfig.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        vault.manualSetPoolConfig(pool, poolConfig);

        setPoolInitAmounts();
        setPoolBalances(poolInitAmountTokenA, poolInitAmountTokenB);

        // Min and Max swap amounts depends on the decimals of each token, so a recalculation is needed.
        calculateMinAndMaxSwapAmounts();
    }

    function setPoolInitAmounts() internal {
        uint256 rateTokenA = getRate(tokenA);
        uint256 rateTokenB = getRate(tokenB);

        // Fix pool init amounts, adjusting to new decimals. These values will be used to calculate max swap values and
        // pool liquidity.
        poolInitAmountTokenA = poolInitAmount.mulDown(10 ** (decimalsTokenA)).divDown(rateTokenA);
        poolInitAmountTokenB = poolInitAmount.mulDown(10 ** (decimalsTokenB)).divDown(rateTokenB);
    }
}
