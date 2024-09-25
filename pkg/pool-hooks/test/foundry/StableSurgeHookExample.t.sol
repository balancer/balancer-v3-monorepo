// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import {
    PoolRoleAccounts,
    SwapKind,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { StableSurgeHookExample } from "../../contracts/StableSurgeHookExample.sol";

contract StableSurgeHookExampleTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    StablePoolFactory internal stablePoolFactory;

    uint64 SWAP_FEE_PERCENTAGE = 0.0004e18;
    uint256 AMP_FACTOR = 200;

    // The following reference values were calculated manually using settings above
    uint256 initialAmount = 50e18;
    uint256[] balancesScaled18 = [initialAmount, initialAmount].toMemoryArray();
    uint256 expectedThresholdBoundary = 0.6e18;
    uint256 amountInBelowThreshold = 1e18;
    uint256 amountInAboveThreshold = 30e18;
    // Return from GivenIn swap, input=amountInAboveThreshold, minus fee
    uint256 amountOutAboveThreshold = 29.850106042102014697e18;
    uint256 expectedSurgeFee = 0.026626754770082000e18;

    function setUp() public override {
        super.setUp();
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function createHook() internal override returns (address) {
        stablePoolFactory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        // LP will be the owner of the hook.
        vm.prank(lp);
        address stableSurgeHook = address(
            new StableSurgeHookExample(IVault(address(vault)), address(stablePoolFactory))
        );
        vm.label(stableSurgeHook, "Stable Surge Hook");
        return stableSurgeHook;
    }

    // Overrides pool creation to use StablePool
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.swapFeeManager = admin;

        vm.expectEmit(true, true, false, false);
        emit StableSurgeHookExample.StableSurgeHookExampleRegistered(
            poolHooksContract,
            address(stablePoolFactory),
            address(0)
        );

        address newPool = address(
            stablePoolFactory.create(
                "Stable Pool Test",
                "STABLE-TEST",
                vault.buildTokenConfig(tokens.asIERC20()),
                AMP_FACTOR,
                roleAccounts,
                MIN_SWAP_FEE,
                poolHooksContract,
                false, // Does not allow donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(newPool, label);

        authorizer.grantRole(vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector), admin);
        vm.prank(admin);
        vault.setStaticSwapFeePercentage(newPool, SWAP_FEE_PERCENTAGE);

        return newPool;
    }

    // Overrides pool init to use initial amounts matches to maths test
    function initPool() internal virtual override {
        vm.startPrank(lp);
        _initPool(pool, balancesScaled18, 0);
        vm.stopPrank();
    }

    function testsetThresholdWithWrongAddress() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableSurgeHookExample.SenderNotAllowed.selector
            )
        );
        StableSurgeHookExample(poolHooksContract).setThresholdPercentage(
            pool,
            0.2e18
        );
    }

    function testsetThresholdWithCorrectAddress() public {
        uint256 newThreshold = 0.2e18;
        vm.prank(admin);
        StableSurgeHookExample(poolHooksContract).setThresholdPercentage(
            pool,
            newThreshold
        );
        uint256 threshold = StableSurgeHookExample(poolHooksContract).poolThresholdPercentage(pool);
        assertEq(threshold, newThreshold);
    }

    function testsetSurgeCoefficientWithWrongAddress() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                StableSurgeHookExample.SenderNotAllowed.selector
            )
        );
        StableSurgeHookExample(poolHooksContract).setSurgeCoefficient(
            pool,
            0.2e18
        );
    }

    function testsetSurgeCoefficientWithCorrectAddress() public {
        uint256 newThreshold = 0.2e18;
        vm.prank(admin);
        StableSurgeHookExample(poolHooksContract).setSurgeCoefficient(
            pool,
            newThreshold
        );
        uint256 threshold = StableSurgeHookExample(poolHooksContract).poolSurgeCoefficient(pool);
        assertEq(threshold, newThreshold);
    }

    function testGetThresholdBoundary() public view {
        uint256 thresholdBoundary = StableSurgeHookExample(poolHooksContract).getThresholdBoundary(
            balancesScaled18.length,
            StableSurgeHookExample(poolHooksContract).DEFAULT_THRESHOLD()
        );
        assertEq(thresholdBoundary, expectedThresholdBoundary, "Incorrect threshold boundary calculation");
    }

    function testComputeSurgeFee() public view {
        uint256 thresholdBoundary = StableSurgeHookExample(poolHooksContract).getThresholdBoundary(
            balancesScaled18.length,
            StableSurgeHookExample(poolHooksContract).DEFAULT_THRESHOLD()
        );
        uint256 weightAfterSwap = StableSurgeHookExample(poolHooksContract).getWeightAfterSwap(
            balancesScaled18,
            daiIdx,
            amountInAboveThreshold,
            amountOutAboveThreshold
        );
        uint256 surgeFee = StableSurgeHookExample(poolHooksContract).getSurgeFee(
            weightAfterSwap,
            thresholdBoundary,
            SWAP_FEE_PERCENTAGE,
            StableSurgeHookExample(poolHooksContract).DEFAULT_SURGECOEFFICIENT()
        );
        assertEq(surgeFee, expectedSurgeFee, "Incorrect surge fee calculation");
    }

    function testHookSwapFeeBelowThreshold() public {
        // amount in results in below threshold so fee should be static
        vm.prank(address(vault));
        (, uint256 hookSwapFeePercentage) = StableSurgeHookExample(poolHooksContract).onComputeDynamicSwapFeePercentage(
            PoolSwapParams({
                kind: SwapKind.EXACT_IN,
                amountGivenScaled18: amountInBelowThreshold,
                balancesScaled18: balancesScaled18,
                indexIn: daiIdx,
                indexOut: usdcIdx,
                router: address(0), // The router is not used by the hook
                userData: bytes("") // User data is not used by the hook
            }),
            pool,
            SWAP_FEE_PERCENTAGE
        );
        assertEq(hookSwapFeePercentage, SWAP_FEE_PERCENTAGE, "Should be static swap fee");
    }

    function testHookSwapFeeAboveThreshold() public {
        // amount in results in above threshold so fee should surge
        vm.prank(address(vault));
        (, uint256 hookSwapFeePercentage) = StableSurgeHookExample(poolHooksContract).onComputeDynamicSwapFeePercentage(
            PoolSwapParams({
                kind: SwapKind.EXACT_IN,
                amountGivenScaled18: amountInAboveThreshold,
                balancesScaled18: balancesScaled18,
                indexIn: daiIdx,
                indexOut: usdcIdx,
                router: address(0), // The router is not used by the hook
                userData: bytes("") // User data is not used by the hook
            }),
            pool,
            SWAP_FEE_PERCENTAGE
        );
        assertEq(hookSwapFeePercentage, expectedSurgeFee, "Should be surge fee");
    }

    function testSwapBelowThreshold() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp);

        // Calculate the expected amount out (amount out without fees)
        uint256 poolInvariant = StableMath.computeInvariant(
            AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesBefore.poolTokens
        );
        uint256 expectedAmountOut = StableMath.computeOutGivenExactIn(
            AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesBefore.poolTokens,
            daiIdx,
            usdcIdx,
            amountInBelowThreshold,
            poolInvariant
        );

        // Swap with amount that should keep within threshold
        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, dai, usdc, amountInBelowThreshold, 0, MAX_UINT256, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp);

        // Measure the actual amount out, which should be `expectedAmountOut` - `swapFeeAmount`.
        uint256 actualAmountOut = balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx];
        uint256 swapFeeAmount = expectedAmountOut - actualAmountOut;

        // Check whether the calculated swap fee percentage equals the static fee percentage. It should,
        // since the pool was taken closer to equilibrium.
        assertEq(swapFeeAmount, expectedAmountOut.mulUp(SWAP_FEE_PERCENTAGE), "Swap Fee Amount is wrong");

        // Check Bob's balances (Bob deposited DAI to receive USDC)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            amountInBelowThreshold,
            "Bob DAI balance is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Bob USDC balance is wrong"
        );

        // Check pool balances (pool received DAI and returned USDC)
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            amountInBelowThreshold,
            "Pool DAI balance is wrong"
        );
        // Since the protocol swap fee is 0 (was not set in this test), all swap fee amounts are returned to the pool.
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Pool USDC balance is wrong"
        );

        // Check Vault balances (must reflect pool)
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            amountInBelowThreshold,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Vault USDC balance is wrong"
        );

        // Check Vault reserves (must reflect Vault balances)
        assertEq(
            balancesAfter.vaultReserves[daiIdx] - balancesBefore.vaultReserves[daiIdx],
            amountInBelowThreshold,
            "Vault DAI reserve is wrong"
        );
        assertEq(
            balancesBefore.vaultReserves[usdcIdx] - balancesAfter.vaultReserves[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Vault USDC reserve is wrong"
        );
    }

    function testSwapAboveThreshold() public {
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp);

        // Calculate the expected amount out (amount out without fees)
        uint256 poolInvariant = StableMath.computeInvariant(
            AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesBefore.poolTokens
        );
        uint256 expectedAmountOut = StableMath.computeOutGivenExactIn(
            AMP_FACTOR * StableMath.AMP_PRECISION,
            balancesBefore.poolTokens,
            daiIdx,
            usdcIdx,
            amountInAboveThreshold,
            poolInvariant
        );

        // Swap with amount that should push above threshold
        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, dai, usdc, amountInAboveThreshold, 0, MAX_UINT256, false, bytes(""));

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp);

        // Measure the actual amount out, which should be `expectedAmountOut` - `swapFeeAmount`.
        uint256 actualAmountOut = balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx];
        uint256 swapFeeAmount = expectedAmountOut - actualAmountOut;

        // Check whether the calculated swap fee percentage equals the surge fee.
        assertEq(swapFeeAmount, expectedAmountOut.mulUp(expectedSurgeFee), "Swap Fee Amount is wrong");

        // Check Bob's balances (Bob deposited DAI to receive USDC)
        assertEq(
            balancesBefore.bobTokens[daiIdx] - balancesAfter.bobTokens[daiIdx],
            amountInAboveThreshold,
            "Bob DAI balance is wrong"
        );
        assertEq(
            balancesAfter.bobTokens[usdcIdx] - balancesBefore.bobTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Bob USDC balance is wrong"
        );

        // Check pool balances (pool received DAI and returned USDC)
        assertEq(
            balancesAfter.poolTokens[daiIdx] - balancesBefore.poolTokens[daiIdx],
            amountInAboveThreshold,
            "Pool DAI balance is wrong"
        );
        // Since the protocol swap fee is 0 (was not set in this test), all swap fee amounts are returned to the pool.
        assertEq(
            balancesBefore.poolTokens[usdcIdx] - balancesAfter.poolTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Pool USDC balance is wrong"
        );

        // Check Vault balances (must reflect pool)
        assertEq(
            balancesAfter.vaultTokens[daiIdx] - balancesBefore.vaultTokens[daiIdx],
            amountInAboveThreshold,
            "Vault DAI balance is wrong"
        );
        assertEq(
            balancesBefore.vaultTokens[usdcIdx] - balancesAfter.vaultTokens[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Vault USDC balance is wrong"
        );

        // Check Vault reserves (must reflect Vault balances)
        assertEq(
            balancesAfter.vaultReserves[daiIdx] - balancesBefore.vaultReserves[daiIdx],
            amountInAboveThreshold,
            "Vault DAI reserve is wrong"
        );
        assertEq(
            balancesBefore.vaultReserves[usdcIdx] - balancesAfter.vaultReserves[usdcIdx],
            expectedAmountOut - swapFeeAmount,
            "Vault USDC reserve is wrong"
        );
    }
}
