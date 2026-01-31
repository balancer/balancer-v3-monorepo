// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";

import { Gyro2CLPPoolFactory } from "../../../contracts/Gyro2CLPPoolFactory.sol";

/**
 * @title Liquidity2CLP Security Medusa Fuzz Test
 * @notice High-signal security properties for Gyro 2CLP liquidity operations.
 * @dev Focus:
 *  - No add->remove proportional round-trip profit for an LP (except tiny rounding dust).
 */
contract Liquidity2CLPSecurityMedusa is BaseMedusaTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    error LiquidityRoundTripProfit(uint256 tokenIndex, uint256 startBalance, uint256 endBalance);
    error BptRoundTripProfit(uint256 startBalance, uint256 endBalance);
    error TokenBalanceIncreasedOnJoin(uint256 tokenIndex, uint256 beforeBal, uint256 afterBal);
    error MintedBptWithoutPayingTokens(uint256 mintedBpt, uint256 spent0, uint256 spent1);
    error ExpectedNonTrivialBptMint();

    // Gyro 2-CLP specific parameters
    uint256 internal constant SQRT_ALPHA = 997496867163000167; // alpha = 0.995
    uint256 internal constant SQRT_BETA = 1002496882788171068; // beta = 1.005

    // Limits
    // Keep this comfortably above “rounds to zero” domains so the test doesn't become vacuous.
    uint256 internal constant MIN_AMOUNT = 1e18;
    uint256 internal constant MAX_AMOUNT_IN = 1e24;

    function createPool(
        IERC20[] memory tokens,
        uint256[] memory initialBalances
    ) internal override returns (address newPool) {
        Gyro2CLPPoolFactory factory = new Gyro2CLPPoolFactory(vault, 365 days, "", "");

        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);
        PoolRoleAccounts memory roleAccounts;

        newPool = factory.create(
            "Gyro 2-CLP Pool",
            "G2CLP",
            vault.buildTokenConfig(tokens, rateProviders),
            SQRT_ALPHA,
            SQRT_BETA,
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
        if (mintedBpt == 0) revert ExpectedNonTrivialBptMint();

        // If BPT was minted, Alice must have paid (and never gained) tokens.
        uint256 midToken0 = tokens[0].balanceOf(alice);
        uint256 midToken1 = tokens[1].balanceOf(alice);
        if (midToken0 > startToken0) revert TokenBalanceIncreasedOnJoin(0, startToken0, midToken0);
        if (midToken1 > startToken1) revert TokenBalanceIncreasedOnJoin(1, startToken1, midToken1);
        uint256 spent0 = startToken0 - midToken0;
        uint256 spent1 = startToken1 - midToken1;
        if (spent0 == 0 && spent1 == 0) revert MintedBptWithoutPayingTokens(mintedBpt, spent0, spent1);

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
