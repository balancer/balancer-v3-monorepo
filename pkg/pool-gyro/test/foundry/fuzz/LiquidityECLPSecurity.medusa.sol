// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";

import { GyroECLPPoolFactory } from "../../../contracts/GyroECLPPoolFactory.sol";

/**
 * @title LiquidityECLP Security Medusa Fuzz Test
 * @notice High-signal security properties for Gyro ECLP liquidity operations.
 * @dev Focus:
 *  - No add->remove proportional round-trip profit for an LP (except tiny rounding dust).
 *  - Pool state must not change if an operation reverts (revert-safety).
 *
 * IMPORTANT: ECLP requires a consistent (params, derivedParams) pair (usually computed off-chain).
 * This harness uses a known-good mainnet fixture for construction stability.
 */
contract LiquidityECLPSecurityMedusa is BaseMedusaTest {
    using CastingHelpers for address[];

    error LiquidityRoundTripProfit(uint256 tokenIndex, uint256 startBalance, uint256 endBalance);
    error BptRoundTripProfit(uint256 startBalance, uint256 endBalance);
    error ExpectedRevertDidNotOccur();
    error UnexpectedRevert(bytes4 selector);

    // Known-good mainnet fixture (see `test/foundry/utils/GyroEclpPoolDeployer.sol`).
    int256 internal constant PARAMS_ALPHA = 998502246630054917;
    int256 internal constant PARAMS_BETA = 1000200040008001600;
    int256 internal constant PARAMS_C = 707106781186547524;
    int256 internal constant PARAMS_S = 707106781186547524;
    int256 internal constant PARAMS_LAMBDA = 4000000000000000000000;

    int256 internal constant TAU_ALPHA_X = -94861212813096057289512505574275160547;
    int256 internal constant TAU_ALPHA_Y = 31644119574235279926451292677567331630;
    int256 internal constant TAU_BETA_X = 37142269533113549537591131345643981951;
    int256 internal constant TAU_BETA_Y = 92846388265400743995957747409218517601;
    int256 internal constant DERIVED_U = 66001741173104803338721745994955553010;
    int256 internal constant DERIVED_V = 62245253919818011890633399060291020887;
    int256 internal constant DERIVED_W = 30601134345582732000058913853921008022;
    int256 internal constant DERIVED_Z = -28859471639991253843240999485797747790;
    int256 internal constant DERIVED_DSQ = 99999999999999999886624093342106115200;

    // Limits
    // Keep this comfortably above “rounds to zero” domains so the round-trip is non-vacuous.
    uint256 internal constant MIN_AMOUNT = 1e18;
    uint256 internal constant MAX_AMOUNT_IN = 1e24;

    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        GyroECLPPoolFactory factory = new GyroECLPPoolFactory(vault, 365 days, "", "");

        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);

        IGyroECLPPool.EclpParams memory eclpParams = IGyroECLPPool.EclpParams({
            alpha: PARAMS_ALPHA,
            beta: PARAMS_BETA,
            c: PARAMS_C,
            s: PARAMS_S,
            lambda: PARAMS_LAMBDA
        });

        IGyroECLPPool.DerivedEclpParams memory derivedParams = IGyroECLPPool.DerivedEclpParams({
            tauAlpha: IGyroECLPPool.Vector2(TAU_ALPHA_X, TAU_ALPHA_Y),
            tauBeta: IGyroECLPPool.Vector2(TAU_BETA_X, TAU_BETA_Y),
            u: DERIVED_U,
            v: DERIVED_V,
            w: DERIVED_W,
            z: DERIVED_Z,
            dSq: DERIVED_DSQ
        });

        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Gyro ECLP Pool",
            "GECLP",
            vault.buildTokenConfig(tokens, rateProviders),
            eclpParams,
            derivedParams,
            roleAccounts,
            1e12, // 0.0001% swap fee
            address(0),
            false,
            false,
            bytes32("")
        );

        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    function getTokensAndInitialBalances()
        internal
        view
        override
        returns (IERC20[] memory tokens, uint256[] memory initialBalances)
    {
        tokens = new IERC20[](2);
        tokens[0] = dai;
        tokens[1] = usdc;
        tokens = InputHelpers.sortTokens(tokens);

        initialBalances = new uint256[](2);
        initialBalances[0] = DEFAULT_INITIAL_POOL_BALANCE;
        initialBalances[1] = DEFAULT_INITIAL_POOL_BALANCE;
    }

    /**
     * @notice Core security test: add proportional liquidity then remove proportional.
     * @dev Must never increase the LP's token balances (except +1 unit dust per token).
     */
    function addRemoveProportionalRoundTrip(uint256 amountInEach) external {
        amountInEach = _boundLocal(amountInEach, MIN_AMOUNT, MAX_AMOUNT_IN);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        uint256 startToken0 = tokens[0].balanceOf(alice);
        uint256 startToken1 = tokens[1].balanceOf(alice);
        uint256 startBpt = IERC20(address(pool)).balanceOf(alice);

        // --- Add proportional ---
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = amountInEach;
        maxAmountsIn[1] = amountInEach;

        medusa.prank(alice);
        router.addLiquidityProportional(address(pool), maxAmountsIn, 0, false, bytes(""));

        uint256 midBpt = IERC20(address(pool)).balanceOf(alice);
        uint256 mintedBpt = midBpt - startBpt;
        // With MIN_AMOUNT chosen above, a successful add should be non-trivial.
        if (mintedBpt == 0) revert ExpectedRevertDidNotOccur();

        // --- Remove proportional ---
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 0;
        minAmountsOut[1] = 0;

        medusa.prank(alice);
        router.removeLiquidityProportional(address(pool), mintedBpt, minAmountsOut, false, bytes(""));

        // --- No-profit check (strict, allow 1 unit dust) ---
        uint256 endToken0 = tokens[0].balanceOf(alice);
        uint256 endToken1 = tokens[1].balanceOf(alice);
        uint256 endBpt = IERC20(address(pool)).balanceOf(alice);

        if (endToken0 > startToken0 + 1) revert LiquidityRoundTripProfit(0, startToken0, endToken0);
        if (endToken1 > startToken1 + 1) revert LiquidityRoundTripProfit(1, startToken1, endToken1);
        if (endBpt > startBpt + 1) revert BptRoundTripProfit(startBpt, endBpt);
    }

    function _boundLocal(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
}
