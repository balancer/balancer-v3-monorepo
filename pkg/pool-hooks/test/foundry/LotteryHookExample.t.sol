// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
    PoolRoleAccounts,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { LotteryHookExample } from "../../contracts/LotteryHookExample.sol";

contract LotteryHookExampleTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    // Maximum swap fee of 10%
    uint64 public constant MAX_SWAP_FEE_PERCENTAGE = 10e16;

    uint256 private constant _minSwapAmount = 1e6;
    uint256 private constant _minBptOut = 1e6;

    // Maximum number of swaps executed on each test, while attempting to win the lottery.
    uint256 private constant MAX_ITERATIONS = 100;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    // Sets the hook for the pool, and stores the address in `poolHooksContract`.
    function createHook() internal override returns (address) {
        // lp will be the owner of the hook. Only the owner can set hook fee percentages.
        vm.prank(lp);
        LotteryHookExample hook = new LotteryHookExample(IVault(address(vault)), address(router));
        return address(hook);
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity).
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "Lottery Pool", "LOTTERY-POOL");
        vm.label(address(newPool), label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        LiquidityManagement memory liquidityManagement;
        liquidityManagement.disableUnbalancedLiquidity = true;

        factoryMock.registerPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );

        return address(newPool);
    }

    function testLotterySwapExactIn() public {
        (
            BaseVaultTest.Balances memory balancesBefore,
            BaseVaultTest.Balances memory balancesAfter,
            uint256 swapAmount,
            uint256[] memory accruedFees,
            uint256 iterations
        ) = _executeLotterySwap(SwapKindLottery.EXACT_IN);

        // Alice paid `swapAmount` (in the last iteration, as the winner)
        assertEq(
            balancesBefore.aliceTokens[daiIdx] - balancesAfter.aliceTokens[daiIdx],
            swapAmount,
            "Alice DAI balance is wrong"
        );
        // Bob paid `swapAmount` in all iterations except the last one (last one is the winner iteration and
        // was executed by Alice)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            (iterations - 1) * swapAmount,
            "Bob DAI balance is wrong"
        );

        // Alice receives `swapAmount` USDC + accrued fees in USDC
        assertEq(
            balancesAfter.aliceTokens[usdcIdx] - balancesBefore.aliceTokens[usdcIdx],
            swapAmount + accruedFees[usdcIdx],
            "Alice USDC balance is wrong"
        );
        // Bob paid `hookFee` in every swap
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            (iterations - 1) * swapAmount - accruedFees[usdcIdx],
            "Bob USDC balance is wrong"
        );

        _checkHookPoolAndVaultBalancesAfterSwap(balancesBefore, balancesAfter, iterations * swapAmount);
    }

    function testLotterySwapExactOut() public {
        (
            BaseVaultTest.Balances memory balancesBefore,
            BaseVaultTest.Balances memory balancesAfter,
            uint256 swapAmount,
            uint256[] memory accruedFees,
            uint256 iterations
        ) = _executeLotterySwap(SwapKindLottery.EXACT_OUT);

        // Alice paid swapAmount in the last iteration, but received accruedFees as the winner of the lottery.
        // If accruedFees > swapAmount, Alice has more DAI than before.
        if (accruedFees[daiIdx] > swapAmount) {
            assertEq(
                balancesAfter.aliceTokens[daiIdx] - balancesBefore.aliceTokens[daiIdx],
                accruedFees[daiIdx] - swapAmount,
                "Alice DAI balance is wrong"
            );
        } else {
            assertEq(
                balancesBefore.aliceTokens[daiIdx] - balancesAfter.aliceTokens[daiIdx],
                swapAmount - accruedFees[daiIdx],
                "Alice DAI balance is wrong"
            );
        }

        // Bob paid swapAmount + hookFee in all iterations except the last (which Alice executed as the winner).
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            (iterations - 1) * swapAmount + accruedFees[daiIdx],
            "Bob DAI balance is wrong"
        );

        // Alice received swapAmount USDC in the last iteration.
        assertEq(
            balancesAfter.aliceTokens[usdcIdx] - balancesBefore.aliceTokens[usdcIdx],
            swapAmount,
            "Alice USDC balance is wrong"
        );
        // Bob received swapAmount in all iterations except the last one.
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            (iterations - 1) * swapAmount,
            "Bob USDC balance is wrong"
        );

        _checkHookPoolAndVaultBalancesAfterSwap(balancesBefore, balancesAfter, iterations * swapAmount);
    }

    function testLotterySwapBothInAndOut() public {
        // If we execute swaps with EXACT_IN and EXACT_OUT, Alice should receive all accrued fees for all tokens.
        (
            BaseVaultTest.Balances memory balancesBefore,
            BaseVaultTest.Balances memory balancesAfter,
            uint256 swapAmount,
            uint256[] memory accruedFees,
            uint256 iterations
        ) = _executeLotterySwap(SwapKindLottery.BOTH);

        // Alice paid swapAmount in the last iteration, but received accruedFees as the winner of the lottery.
        // If accruedFees > swapAmount, Alice has more DAI than before.
        if (accruedFees[daiIdx] > swapAmount) {
            assertEq(
                balancesAfter.aliceTokens[daiIdx] - balancesBefore.aliceTokens[daiIdx],
                accruedFees[daiIdx] - swapAmount,
                "Alice DAI balance is wrong"
            );
        } else {
            assertEq(
                balancesBefore.aliceTokens[daiIdx] - balancesAfter.aliceTokens[daiIdx],
                swapAmount - accruedFees[daiIdx],
                "Alice DAI balance is wrong"
            );
        }

        // Bob paid `swapAmount` in all iterations except the last one, plus fees accrued in DAI. (The final iteration
        // was the winner, executed by Alice.)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            (iterations - 1) * swapAmount + accruedFees[daiIdx],
            "Bob DAI balance is wrong"
        );

        // Alice received swapAmount + accrued fees in USDC in the last iteration.
        assertEq(
            balancesAfter.aliceTokens[usdcIdx] - balancesBefore.aliceTokens[usdcIdx],
            swapAmount + accruedFees[usdcIdx],
            "Alice USDC balance is wrong"
        );
        // Bob received swapAmount in all iterations except the last one, less fees accrued in USDC.
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            (iterations - 1) * swapAmount - accruedFees[usdcIdx],
            "Bob USDC balance is wrong"
        );

        _checkHookPoolAndVaultBalancesAfterSwap(balancesBefore, balancesAfter, swapAmount * iterations);
    }

    enum SwapKindLottery {
        EXACT_IN,
        EXACT_OUT,
        BOTH
    }

    function _executeLotterySwap(
        SwapKindLottery kind
    )
        private
        returns (
            BaseVaultTest.Balances memory balancesBefore,
            BaseVaultTest.Balances memory balancesAfter,
            uint256 swapAmount,
            uint256[] memory accruedFees,
            uint256 iterations
        )
    {
        swapAmount = poolInitAmount / 100;

        vm.prank(lp);
        LotteryHookExample(poolHooksContract).setHookSwapFeePercentage(MAX_SWAP_FEE_PERCENTAGE);
        uint256 hookFee = swapAmount.mulDown(MAX_SWAP_FEE_PERCENTAGE);

        balancesBefore = getBalances(bob);

        accruedFees = new uint256[](2); // Store the fees collected on each token
        iterations = 0;

        for (iterations = 1; iterations < MAX_ITERATIONS; ++iterations) {
            bytes4 routerMethod;
            // If kind is BOTH, odd iterations are EXACT_IN and even iterations are EXACT_OUT.
            if (kind == SwapKindLottery.EXACT_IN || (kind == SwapKindLottery.BOTH && iterations % 2 == 1)) {
                routerMethod = IRouter.swapSingleTokenExactIn.selector;
            } else {
                routerMethod = IRouter.swapSingleTokenExactOut.selector;
            }

            uint8 randomNumber = LotteryHookExample(poolHooksContract).getRandomNumber();

            uint256 amountGiven = swapAmount;
            uint256 amountCalculated = routerMethod == IRouter.swapSingleTokenExactIn.selector
                ? swapAmount - hookFee // If EXACT_IN, amount calculated is amount out; user receives less
                : swapAmount + hookFee; // If EXACT_IN, amount calculated is amount in; user pays more

            // Bob is the paying user, Alice is the user who will win the lottery (so we can measure the
            // amount of fee tokens sent).
            vm.prank(randomNumber == LotteryHookExample(poolHooksContract).LUCKY_NUMBER() ? alice : bob);
            (bool success, ) = address(router).call(
                abi.encodeWithSelector(
                    routerMethod,
                    address(pool),
                    dai,
                    usdc,
                    amountGiven,
                    amountCalculated,
                    MAX_UINT256,
                    false,
                    bytes("")
                )
            );

            assertTrue(success, "Swap has failed");

            if (randomNumber == LotteryHookExample(poolHooksContract).LUCKY_NUMBER()) {
                break;
            } else {
                if (routerMethod == IRouter.swapSingleTokenExactIn.selector) {
                    accruedFees[usdcIdx] += hookFee;
                } else {
                    accruedFees[daiIdx] += hookFee;
                }
            }
        }

        // If one of the conditions below fails, change the LUCKY_NUMBER in the LotteryHookExample contract.
        assertNotEq(iterations, 1, "Only 1 iteration");
        assertNotEq(iterations, MAX_ITERATIONS, "Max iterations reached, no winner");

        balancesAfter = getBalances(bob);
    }

    // Check whether pool balances and vault reserves reflect all swaps.
    function _checkHookPoolAndVaultBalancesAfterSwap(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256 expectedBalanceChange
    ) private view {
        // Check whether pool balances are correct after all swaps.
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            expectedBalanceChange,
            "Pool DAI balance is wrong"
        );
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            expectedBalanceChange,
            "Pool USDC balance is wrong"
        );

        // Check whether vault balances are correct after all swaps.
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            expectedBalanceChange,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            expectedBalanceChange,
            "Vault USDC balance is wrong"
        );

        // Check whether vault reserves are correct after all swaps.
        assertEq(
            balancesAfter.vaultReserves[daiIdx] - balancesBefore.vaultReserves[daiIdx],
            expectedBalanceChange,
            "Vault DAI reserve is wrong"
        );
        assertEq(
            balancesBefore.vaultReserves[usdcIdx] - balancesAfter.vaultReserves[usdcIdx],
            expectedBalanceChange,
            "Vault USDC reserve is wrong"
        );

        // All accrued fees are paid to Alice, so the hook balance must be the same.
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook DAI balance is wrong");
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook USDC balance is wrong");
    }
}
