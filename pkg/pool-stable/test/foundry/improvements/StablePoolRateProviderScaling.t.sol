// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";

import { StablePoolFactory } from "../../../contracts/StablePoolFactory.sol";
import { StablePoolContractsDeployer } from "../utils/StablePoolContractsDeployer.sol";

/**
 * @title StablePoolRateProviderScalingTest
 * @notice Tests stable pool behavior when one token uses a rate provider (TokenType.WITH_RATE).
 * @dev Covers the "rate changes between operations" gap by mutating the rate provider between swaps and ensuring:
 *  - swaps succeed across a range of rates
 *  - swap fees accrue (non-dust execution)
 *  - BPT rate + scaled invariant do not decrease for each swap (at a fixed rate)
 *  - explicit extreme rate-jump regression coverage (0.5x <-> 3x)
 */
contract StablePoolRateProviderScalingTest is StablePoolContractsDeployer, BaseVaultTest {
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_AMP = 200;
    uint256 internal constant DEFAULT_SWAP_FEE = 1e12; // 0.0001%
    string internal constant POOL_VERSION = "Pool v1";
    uint256 internal constant MIN_NON_DUST_AMOUNT = 1e12; // 1e-6 token (18 decimals); ensures non-zero fees

    StablePoolFactory internal stableFactory;
    uint256 internal poolCreationNonce;
    RateProviderMock internal localRateProvider;

    function setUp() public override {
        super.setUp();
        stableFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION);
        localRateProvider = new RateProviderMock();

        // `getAggregateSwapFeeAmount` tracks protocol + pool creator fees (not LP swap fees).
        // Ensure the global protocol fee is non-zero so tests can assert fee accrual deterministically.
        IProtocolFeeController feeController = vault.getProtocolFeeController();
        IAuthentication feeControllerAuth = IAuthentication(address(feeController));
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        vm.prank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(1e16); // 1% of collected swap fees
    }

    function testSwapsAcrossChangingRatesDoNotDecreaseInvariant__Fuzz(uint256 rawRate1, uint256 rawRate2) public {
        // Choose two different rates; we will do one swap at each rate.
        uint256 rate1 = bound(rawRate1, 5e17, 3e18); // 0.5x .. 3x
        uint256 rate2 = bound(rawRate2, 5e17, 3e18);
        vm.assume(rate1 != rate2);

        address pool = _createAndInitPoolWithRateProvider();
        (IERC20[] memory tokens, uint256 rateTokenIndex, uint256 standardTokenIndex) = _getPoolTokensAndIndexes(pool);

        uint256 amountOut1;

        // Swap 1 at rate1 (scoped block to keep stack usage low).
        {
            localRateProvider.mockRate(rate1);
            _syncPoolData(pool);
            uint256 bptRateBefore = vault.getBptRate(pool);
            uint256 invBefore = _computeInvariantScaled18(pool, Rounding.ROUND_DOWN);
            uint256 feesBefore = vault.getAggregateSwapFeeAmount(pool, tokens[standardTokenIndex]);

            vm.prank(alice);
            amountOut1 = router.swapSingleTokenExactIn(
                pool,
                tokens[standardTokenIndex],
                tokens[rateTokenIndex],
                1e18, // 1 token (18 decimals in this harness)
                0,
                type(uint256).max,
                false,
                bytes("")
            );
            assertGt(amountOut1, 0, "Swap at rate1 should produce output");

            assertGt(
                vault.getAggregateSwapFeeAmount(pool, tokens[standardTokenIndex]),
                feesBefore,
                "Expected aggregate swap fees to increase at rate1"
            );
            _syncPoolData(pool);
            assertGe(
                _computeInvariantScaled18(pool, Rounding.ROUND_DOWN),
                invBefore,
                "Invariant should not decrease after swap at rate1"
            );
            assertGe(vault.getBptRate(pool) + 1, bptRateBefore, "BPT rate should not decrease at rate1");
        }

        // Swap 2 at rate2 (rate changes between operations).
        {
            localRateProvider.mockRate(rate2);
            _syncPoolData(pool);
            uint256 bptRateBefore = vault.getBptRate(pool);
            uint256 invBefore = _computeInvariantScaled18(pool, Rounding.ROUND_DOWN);
            uint256 feesBefore = vault.getAggregateSwapFeeAmount(pool, tokens[rateTokenIndex]);

            // Swap back a fraction of what we received, but keep it comfortably above dust.
            vm.assume(amountOut1 >= MIN_NON_DUST_AMOUNT);
            uint256 amountIn2 = bound(amountOut1 / 10 + 1, MIN_NON_DUST_AMOUNT, amountOut1);

            vm.prank(alice);
            uint256 amountOut2 = router.swapSingleTokenExactIn(
                pool,
                tokens[rateTokenIndex],
                tokens[standardTokenIndex],
                amountIn2, // small reverse trade
                0,
                type(uint256).max,
                false,
                bytes("")
            );
            assertGt(amountOut2, 0, "Swap at rate2 should produce output");

            assertGt(
                vault.getAggregateSwapFeeAmount(pool, tokens[rateTokenIndex]),
                feesBefore,
                "Expected aggregate swap fees to increase at rate2"
            );
            _syncPoolData(pool);
            assertGe(
                _computeInvariantScaled18(pool, Rounding.ROUND_DOWN),
                invBefore,
                "Invariant should not decrease after swap at rate2"
            );
            assertGe(vault.getBptRate(pool) + 1, bptRateBefore, "BPT rate should not decrease at rate2");
        }
    }

    function testSwapsAcrossExtremeRateJumpDoNotDecreaseInvariant() public {
        address pool = _createAndInitPoolWithRateProvider();
        (IERC20[] memory tokens, uint256 rateTokenIndex, uint256 standardTokenIndex) = _getPoolTokensAndIndexes(pool);

        // Hard-code the scary jump (0.5x -> 3x) so we *guarantee* covering it.
        uint256 rateLow = 5e17;
        uint256 rateHigh = 3e18;

        uint256 amountOut1;

        // Swap 1 at low rate (scoped block to keep stack usage low).
        {
            localRateProvider.mockRate(rateLow);
            _syncPoolData(pool);
            uint256 bptRateBefore = vault.getBptRate(pool);
            uint256 invBefore = _computeInvariantScaled18(pool, Rounding.ROUND_DOWN);
            uint256 feesBefore = vault.getAggregateSwapFeeAmount(pool, tokens[standardTokenIndex]);

            vm.prank(alice);
            amountOut1 = router.swapSingleTokenExactIn(
                pool,
                tokens[standardTokenIndex],
                tokens[rateTokenIndex],
                1e18,
                0,
                type(uint256).max,
                false,
                bytes("")
            );

            assertGt(amountOut1, 0, "Swap at low rate should produce output");
            assertGt(
                vault.getAggregateSwapFeeAmount(pool, tokens[standardTokenIndex]),
                feesBefore,
                "Expected fees to increase at low rate"
            );
            _syncPoolData(pool);
            assertGe(
                _computeInvariantScaled18(pool, Rounding.ROUND_DOWN),
                invBefore,
                "Invariant should not decrease after swap at low rate"
            );
            assertGe(vault.getBptRate(pool) + 1, bptRateBefore, "BPT rate should not decrease at low rate");
        }

        // Swap 2 after high-rate jump (separate scope).
        {
            localRateProvider.mockRate(rateHigh);
            _syncPoolData(pool);
            uint256 bptRateBefore = vault.getBptRate(pool);
            uint256 invBefore = _computeInvariantScaled18(pool, Rounding.ROUND_DOWN);
            uint256 feesBefore = vault.getAggregateSwapFeeAmount(pool, tokens[rateTokenIndex]);

            vm.prank(alice);
            uint256 amountOut2 = router.swapSingleTokenExactIn(
                pool,
                tokens[rateTokenIndex],
                tokens[standardTokenIndex],
                amountOut1 / 10 + 1,
                0,
                type(uint256).max,
                false,
                bytes("")
            );

            assertGt(amountOut2, 0, "Swap after high-rate jump should produce output");
            assertGt(
                vault.getAggregateSwapFeeAmount(pool, tokens[rateTokenIndex]),
                feesBefore,
                "Expected fees to increase after high-rate jump"
            );
            _syncPoolData(pool);
            assertGe(
                _computeInvariantScaled18(pool, Rounding.ROUND_DOWN),
                invBefore,
                "Invariant should not decrease after swap at high rate"
            );
            assertGe(vault.getBptRate(pool) + 1, bptRateBefore, "BPT rate should not decrease at high rate");
        }
    }


    function _createAndInitPoolWithRateProvider() internal returns (address newPool) {
        // Configure DAI as WITH_RATE using the (mutable) RateProviderMock; USDC remains STANDARD.
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[0] = TokenConfig({
            token: dai,
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(address(localRateProvider)),
            paysYieldFees: false
        });
        tokenConfig[1] = TokenConfig({
            token: usdc,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            paysYieldFees: false
        });

        tokenConfig = _sortTokenConfig2(tokenConfig);

        PoolRoleAccounts memory roleAccounts;

        newPool = stableFactory.create(
            "Stable Rate Provider",
            "RATESTABLE",
            tokenConfig,
            DEFAULT_AMP,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            address(0),
            false,
            false,
            bytes32(poolCreationNonce++)
        );

        // Initialize with equal raw balances (both 18 decimals in this harness).
        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = tokenConfig[0].token;
        tokens[1] = tokenConfig[1].token;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e22;
        amounts[1] = 1e22;

        vm.prank(lp);
        router.initialize(newPool, tokens, amounts, 0, false, bytes(""));
    }

    function _getPoolTokensAndIndexes(
        address pool
    ) internal view returns (IERC20[] memory tokens, uint256 rateTokenIndex, uint256 standardTokenIndex) {
        tokens = vault.getPoolTokens(pool);
        require(tokens.length == 2, "Expected 2-token pool");

        // DAI is the "rate" token in this test.
        if (address(tokens[0]) == address(dai)) {
            rateTokenIndex = 0;
            standardTokenIndex = 1;
        } else {
            rateTokenIndex = 1;
            standardTokenIndex = 0;
        }
    }

    function _computeInvariantScaled18(address pool, Rounding rounding) internal view returns (uint256) {
        (, , , uint256[] memory balancesScaled18) = vault.getPoolTokenInfo(pool);
        return IBasePool(pool).computeInvariant(balancesScaled18, rounding);
    }

    function _syncPoolData(address pool) internal {
        // Ensure the Vault has reloaded rate-provider-driven tokenRates and recomputed balancesLiveScaled18
        // before we compare invariants / BPT rates across operations.
        vault.loadPoolDataUpdatingBalancesAndYieldFees(pool, Rounding.ROUND_DOWN);
    }

    function _sortTokenConfig2(TokenConfig[] memory cfg) internal pure returns (TokenConfig[] memory) {
        // Simple 2-element sort by token address.
        if (cfg.length != 2) return cfg;
        if (cfg[0].token > cfg[1].token) {
            TokenConfig memory tmp = cfg[0];
            cfg[0] = cfg[1];
            cfg[1] = tmp;
        }
        return cfg;
    }
}

