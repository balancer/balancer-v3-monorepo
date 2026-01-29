// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";

/**
 * @title StablePoolDecimalsAndScalingTest
 * @notice Exercises production scaling paths by using non-18-decimal tokens in a Stable pool.
 * @dev BaseVaultTest's default "USDC" is 18 decimals by design; this file fills that gap using:
 *  - usdc6Decimals (6 decimals)
 *  - wbtc8Decimals (8 decimals)
 * @dev compile --via-ir
 */
contract StablePoolDecimalsAndScalingTest is StablePoolContractsDeployer, BaseVaultTest {
    uint256 internal constant DEFAULT_AMP = 200;
    uint256 internal constant DEFAULT_SWAP_FEE = 1e12; // 0.0001%
    string internal constant POOL_VERSION = "Pool v1";

    StablePoolFactory internal stableFactory;
    uint256 internal poolCreationNonce;

    function setUp() public override {
        super.setUp();
        stableFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION);
    }

    function testOddDecimalsPoolScalingFactorsMatchTokenDecimals() public {
        address pool = _createAndInitOddDecimalsPool();

        IERC20[] memory tokens = vault.getPoolTokens(pool);
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(pool);

        assertEq(tokens.length, 2, "Expected 2-token pool");
        assertEq(decimalScalingFactors.length, 2, "Scaling factors length mismatch");

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint8 decimals = IERC20Metadata(address(tokens[i])).decimals();
            assertLe(decimals, 18, "Token decimals > 18 not supported");
            uint256 expectedScaling = 10 ** (18 - uint256(decimals));
            assertEq(decimalScalingFactors[i], expectedScaling, "Wrong decimal scaling factor");
        }
    }

    function testSingleSwapChargesFeesAndDoesNotDecreaseBptRateWithOddDecimals__Fuzz(
        uint256 rawAmountIn,
        bool swapUsdcToWbtc
    ) public {
        // NOTE: Round-trip and general decimals fuzzing are already covered by `E2eSwapStableTest` (via `E2eSwap.t.sol`).
        // This test is intentionally narrower: one swap on a pool built from *actual* 6/8-decimal tokens, ensuring:
        // - swap produces output (not dust-rounded to zero)
        // - invariant/BPT-rate do not decrease (scaled18 monotonicity signal under real decimals)
        // - if aggregate-fee tracking is enabled, the stored aggregate fee amount increases

        address pool = _createAndInitOddDecimalsPool();

        // Compute before-swap signals outside the swap scope to keep stack usage low for coverage compilation
        // (forge coverage disables viaIR + optimizer).
        uint256 invBeforeRoundDown = _computeInvariantScaled18(pool, Rounding.ROUND_DOWN);
        uint256 invBeforeRoundUp = _computeInvariantScaled18(pool, Rounding.ROUND_UP);
        uint256 bptRateBefore = vault.getBptRate(pool);

        // Do swap + fee assertions in a scoped block so token/amount locals don't remain live afterwards.
        {
            IERC20 tokenIn = swapUsdcToWbtc ? usdc6Decimals : wbtc8Decimals;
            IERC20 tokenOut = swapUsdcToWbtc ? wbtc8Decimals : usdc6Decimals;

            // Ensure fee amount is non-zero in raw units for DEFAULT_SWAP_FEE (= 1e-6):
            // - USDC-6: 1e6 raw (1 USDC) yields feeRaw ~= 1
            // - WBTC-8: 1e6 raw (0.01 WBTC) yields feeRaw ~= 1
            uint256 minAmountIn = 1e6;
            uint256 maxAmountIn = swapUsdcToWbtc ? (100_000 * 1e6) : (1e8); // 100k USDC or 1 WBTC
            uint256 amountIn = bound(rawAmountIn, minAmountIn, maxAmountIn);

            uint256 feesBefore = vault.getAggregateSwapFeeAmount(pool, tokenIn);
            uint256 aggregateSwapFeePercentage = vault.getPoolConfig(pool).aggregateSwapFeePercentage;

            vm.prank(alice);
            uint256 amountOut = router.swapSingleTokenExactIn(
                pool,
                tokenIn,
                tokenOut,
                amountIn,
                0,
                type(uint256).max,
                false,
                bytes("")
            );
            assertGt(amountOut, 0, "Swap should produce output");

            uint256 feesAfter = vault.getAggregateSwapFeeAmount(pool, tokenIn);
            if (aggregateSwapFeePercentage > 0) {
                assertGt(feesAfter, feesBefore, "Expected aggregate swap fees to increase");
            }
        }

        uint256 bptRateAfter = vault.getBptRate(pool);
        assertGe(bptRateAfter + 1, bptRateBefore, "BPT rate should not decrease after swap");

        uint256 invAfterRoundDown = _computeInvariantScaled18(pool, Rounding.ROUND_DOWN);
        uint256 invAfterRoundUp = _computeInvariantScaled18(pool, Rounding.ROUND_UP);
        assertGe(invAfterRoundUp, invBeforeRoundDown, "Invariant decreased (scaled18)");
        // Stronger check when rounding isn't binding.
        assertGe(invAfterRoundDown + 1, invBeforeRoundDown, "Invariant decreased (roundDown)");
        assertGe(invAfterRoundUp + 1, invBeforeRoundUp, "Invariant decreased (roundUp)");
    }

    function _createAndInitOddDecimalsPool() internal returns (address newPool) {
        IERC20[] memory tokens = _getOddDecimalsTokens();

        PoolRoleAccounts memory roleAccounts;

        newPool = stableFactory.create(
            "Stable Odd Decimals",
            "ODD",
            vault.buildTokenConfig(tokens),
            DEFAULT_AMP,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            address(0),
            false,
            false,
            bytes32(poolCreationNonce++)
        );

        // Initialize with large balances in raw units.
        // USDC-6: 1,000,000 tokens => 1_000_000 * 1e6
        // WBTC-8: 100 tokens => 100 * 1e8
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000 * 1e6;
        amounts[1] = 100 * 1e8;

        vm.prank(lp);
        router.initialize(newPool, tokens, amounts, 0, false, bytes(""));
    }

    function _getOddDecimalsTokens() internal view returns (IERC20[] memory tokens) {
        tokens = new IERC20[](2);
        tokens[0] = usdc6Decimals;
        tokens[1] = wbtc8Decimals;
        tokens = InputHelpers.sortTokens(tokens);
    }

    function _computeInvariantScaled18(address pool, Rounding rounding) internal view returns (uint256) {
        (, , , uint256[] memory balancesScaled18) = vault.getPoolTokenInfo(pool);
        return IBasePool(pool).computeInvariant(balancesScaled18, rounding);
    }
}
