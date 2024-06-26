// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    LiquidityManagement,
    PoolRoleAccounts,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BasePoolMath } from "@balancer-labs/v3-solidity-utils/contracts/math/BasePoolMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { LotteryHookExample } from "../../contracts/LotteryHookExample.sol";

contract LotteryHookExampleTest is BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256 private constant _minSwapAmount = 1e6;
    uint256 private constant _minBptOut = 1e6;

    // Maximum number of swaps executed on each test, to try to be the winner of the lottery hook
    uint256 private constant MAX_ITERATIONS = 100;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    // Sets the hook of the pool and stores the address in the variable poolHooksContract
    function createHook() internal override returns (address) {
        // lp will be the owner of the hook. Only LP is able to set hook fee percentages.
        vm.prank(lp);
        LotteryHookExample hook = new LotteryHookExample(IVault(address(vault)), address(router));
        return address(hook);
    }

    // Overrides pool creation to set liquidityManagement (disables unbalanced liquidity)
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(vault)), "Lottery Pool", "LOTTERYPOOL");
        vm.label(address(newPool), label);

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = address(lp);

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
        uint256 swapAmount = poolInitAmount / 100;

        // 10% fee
        uint64 hookFeePercentage = 1e17;
        vm.prank(lp);
        LotteryHookExample(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(bob));

        uint256 accruedFees = 0;
        uint256 luckyNumber = LotteryHookExample(poolHooksContract).LUCKY_NUMBER();
        uint256 it;

        for (it = 1; it < MAX_ITERATIONS; ++it) {
            bool isWinner = LotteryHookExample(poolHooksContract).getRandomNumber() == luckyNumber;

            // Bob is the paying user, Alice is the user that'll be the winner of the lottery (so we can measure the
            // amount of fees sent)
            vm.startPrank(isWinner ? alice : bob);
            router.swapSingleTokenExactIn(address(pool), dai, usdc, swapAmount, 0, MAX_UINT256, false, bytes(""));
            vm.stopPrank();

            if (isWinner) {
                break;
            } else {
                accruedFees += hookFee;
            }
        }

        // If one of the conditions below fails, change the LUCKY_NUMBER in the LotteryHookExample contract
        assertNotEq(it, 1, "Only 1 iteration");
        assertNotEq(it, MAX_ITERATIONS, "Max iterations reached, no winner");

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(bob));

        // Alice paid `swapAmount` (in the last iteration, as the winner)
        assertEq(
            balancesBefore.aliceTokens[daiIdx] - balancesAfter.aliceTokens[daiIdx],
            swapAmount,
            "Alice DAI balance is wrong"
        );
        // Bob paid `swapAmount` in all iterations, but the last one (last one is the winner iteration and
        // was executed by Alice)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            (it - 1) * swapAmount,
            "Bob DAI balance is wrong"
        );
        // All accrued fees are paid to Alice, so the hook balance must be the same
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook DAI balance is wrong");

        // Alice receives `swapAmount` USDC + accrued fees in USDC
        assertEq(
            balancesAfter.aliceTokens[usdcIdx] - balancesBefore.aliceTokens[usdcIdx],
            swapAmount + accruedFees,
            "Alice USDC balance is wrong"
        );
        // Bob paid hookFee in every swap that it executed
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            (it - 1) * (swapAmount - hookFee),
            "Bob USDC balance is wrong"
        );
        // All accrued fees are paid to Alice, so the hook balance must be the same
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook USDC balance is wrong");

        _checkPoolAndVaultBalancesAfterSwap(balancesBefore, balancesAfter, it * swapAmount);
    }

    function testLotterySwapExactOut() public {
        uint256 swapAmount = poolInitAmount / 100;

        // 10% fee
        uint64 hookFeePercentage = 1e17;
        vm.prank(lp);
        LotteryHookExample(poolHooksContract).setHookSwapFeePercentage(hookFeePercentage);
        uint256 hookFee = swapAmount.mulDown(hookFeePercentage);

        BaseVaultTest.Balances memory balancesBefore = getBalances(address(bob));

        uint256 accruedFees = 0;
        uint256 it;

        for (it = 1; it < MAX_ITERATIONS; ++it) {
            uint8 randomNumber = LotteryHookExample(poolHooksContract).getRandomNumber();

            // Bob is the paying user, Alice is the user that'll be the winner of the lottery (so we can measure the
            // amount of fees sent)
            vm.prank(randomNumber == LotteryHookExample(poolHooksContract).LUCKY_NUMBER() ? alice : bob);
            router.swapSingleTokenExactOut(
                address(pool),
                dai,
                usdc,
                swapAmount,
                swapAmount + hookFee,
                MAX_UINT256,
                false,
                bytes("")
            );

            if (randomNumber == LotteryHookExample(poolHooksContract).LUCKY_NUMBER()) {
                break;
            } else {
                accruedFees += hookFee;
            }
        }

        // If one of the conditions below fails, change the LUCKY_NUMBER in the LotteryHookExample contract
        assertNotEq(it, 1, "Only 1 iteration");
        assertNotEq(it, MAX_ITERATIONS, "Max iterations reached, no winner");

        BaseVaultTest.Balances memory balancesAfter = getBalances(address(bob));

        // Alice paid swapAmount in the last iteration, but received accruedFees as the winner of the lottery.
        // If accruedFees > swapAmount, Alice has more DAI than before
        if (accruedFees > swapAmount) {
            assertEq(
                balancesAfter.aliceTokens[daiIdx] - balancesBefore.aliceTokens[daiIdx],
                accruedFees - swapAmount,
                "Alice DAI balance is wrong"
            );
        } else {
            assertEq(
                balancesBefore.aliceTokens[daiIdx] - balancesAfter.aliceTokens[daiIdx],
                swapAmount - accruedFees,
                "Alice DAI balance is wrong"
            );
        }

        // Bob paid swapAmount + hookFee in all iterations but the last one (last one is the winner iteration and
        // was executed by Alice)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            (it - 1) * (swapAmount + hookFee),
            "Bob DAI balance is wrong"
        );
        // All accrued fees are paid to Alice, so the hook balance must be the same
        assertEq(balancesBefore.hookTokens[daiIdx], balancesAfter.hookTokens[daiIdx], "Hook DAI balance is wrong");

        // Alice received swapAmount USDC in the last iteration
        assertEq(
            balancesAfter.aliceTokens[usdcIdx] - balancesBefore.aliceTokens[usdcIdx],
            swapAmount,
            "Alice USDC balance is wrong"
        );
        // Bob received swapAmount in all iterations but the last one
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            (it - 1) * swapAmount,
            "Bob USDC balance is wrong"
        );
        // All accrued fees are paid to Alice, so the hook balance must be the same
        assertEq(balancesBefore.hookTokens[usdcIdx], balancesAfter.hookTokens[usdcIdx], "Hook USDC balance is wrong");

        _checkPoolAndVaultBalancesAfterSwap(balancesBefore, balancesAfter, it * swapAmount);
    }

    // @dev Check if pool balances and vault reserves reflect all swaps
    function _checkPoolAndVaultBalancesAfterSwap(
        BaseVaultTest.Balances memory balancesBefore,
        BaseVaultTest.Balances memory balancesAfter,
        uint256 expectedBalanceChange
    ) private view {
        // Check if pool balances are correct after all swaps
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

        // Check if vault balances are correct after all swaps
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

        // Check if vault reserves are correct after all swaps
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
    }
}
