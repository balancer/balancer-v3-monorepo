// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseMedusaTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseMedusaTest.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StablePoolFactory } from "../../../contracts/StablePoolFactory.sol";

/**
 * @title SwapStableEnhancedPR1607 Medusa Fuzz Test
 * @notice PR1607 snapshot of the enhanced Medusa fuzzing tests for Stable pool swap operations.
 * @dev Differences vs original:
 *  - Max imbalance ratio reduced from 100_000 to 10_000.
 *  - Imbalance check uses raw math for the ratio computation.
 */
contract SwapStableEnhancedPR1607Medusa is BaseMedusaTest {
    // Maximum allowed imbalance ratio (10,000:1) in 18-decimal fixed point.
    uint256 internal constant MAX_IMBALANCE_RATIO = 10_000e18;

    // Stable pool specific parameters.
    uint256 internal constant AMPLIFICATION_PARAMETER = 200;
    uint256 internal constant AMP_PRECISION = StableMath.AMP_PRECISION;

    // Limits
    uint256 internal constant MIN_SWAP_AMOUNT = 1e6;
    // StablePool enforces a non-zero minimum swap fee at registration time. For the "0 fee" scenarios we
    // register the pool with the minimum fee and then force it to 0 via the VaultMock unsafe setter.
    uint256 internal constant MIN_SWAP_FEE = 1e12; // 0.0001%

    // Track state.
    uint256 internal lastKnownInvariant;
    uint256 internal maxRoundTripProfit;

    constructor() BaseMedusaTest() {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        lastKnownInvariant = StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balances);
    }

    function createPool(IERC20[] memory tokens, uint256[] memory initialBalances) internal override returns (address) {
        StablePoolFactory factory = new StablePoolFactory(vault, 365 days, "", "");
        PoolRoleAccounts memory roleAccounts;

        address newPool = factory.create(
            "Stable Pool",
            "STABLE",
            vault.buildTokenConfig(tokens),
            AMPLIFICATION_PARAMETER,
            roleAccounts,
            MIN_SWAP_FEE, // set a valid fee at registration time; forced to 0 below (scenario: 0 fee)
            address(0),
            false,
            false,
            bytes32("")
        );

        // Force effective swap fee to 0 for this scenario (matches `SwapMedusaTest` behavior).
        vault.manualUnsafeSetStaticSwapFeePercentage(newPool, 0);

        medusa.prank(lp);
        router.initialize(newPool, tokens, initialBalances, 0, false, bytes(""));

        return newPool;
    }

    /***************************************************************************
                                   Fuzz Functions
     ***************************************************************************/

    function swapExactIn(uint256 amountIn, uint256 tokenIndexIn) external {
        tokenIndexIn = tokenIndexIn % 2;
        uint256 tokenIndexOut = (tokenIndexIn + 1) % 2;

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        amountIn = _boundValue(amountIn, MIN_SWAP_AMOUNT, balances[tokenIndexIn] / 4);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        uint256 invariantBefore = StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balances);

        medusa.prank(alice);
        uint256 amountOut = router.swapSingleTokenExactIn(
            address(pool),
            tokens[tokenIndexIn],
            tokens[tokenIndexOut],
            amountIn,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        assert(amountOut > 0);

        (, , uint256[] memory balancesAfter, ) = vault.getPoolTokenInfo(address(pool));
        uint256 invariantAfter = StableMath.computeInvariant(
            AMPLIFICATION_PARAMETER * AMP_PRECISION,
            balancesAfter
        );

        assert(invariantAfter >= invariantBefore);

        if (invariantAfter > lastKnownInvariant) {
            lastKnownInvariant = invariantAfter;
        }
    }

    function roundTripSwap(uint256 amountIn, uint256 startTokenIndex) external {
        startTokenIndex = startTokenIndex % 2;
        uint256 otherTokenIndex = (startTokenIndex + 1) % 2;

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        amountIn = _boundValue(amountIn, MIN_SWAP_AMOUNT, balances[startTokenIndex] / 10);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(alice);
        uint256 amountOut1 = router.swapSingleTokenExactIn(
            address(pool),
            tokens[startTokenIndex],
            tokens[otherTokenIndex],
            amountIn,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        if (amountOut1 < MIN_SWAP_AMOUNT) return;

        medusa.prank(alice);
        uint256 amountOut2 = router.swapSingleTokenExactIn(
            address(pool),
            tokens[otherTokenIndex],
            tokens[startTokenIndex],
            amountOut1,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
        if (amountOut2 > amountIn) {
            uint256 profit = amountOut2 - amountIn;
            if (profit > maxRoundTripProfit) {
                maxRoundTripProfit = profit;
            }
        }
    }

    /***************************************************************************
                                Invariant Properties
     ***************************************************************************/

    function property_invariantNonDecreasing() external view returns (bool) {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        uint256 currentInvariant = StableMath.computeInvariant(AMPLIFICATION_PARAMETER * AMP_PRECISION, balances);
        return currentInvariant >= lastKnownInvariant;
    }

    function property_noRoundTripProfit() external view returns (bool) {
        return maxRoundTripProfit == 0;
    }

    function property_balancesPositive() external view returns (bool) {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] == 0) return false;
        }
        return true;
    }

    function property_imbalanceWithinLimits() external view returns (bool) {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        (uint256 minBalance, uint256 maxBalance) = _getMinAndMaxBalances(balances);
        if (minBalance == 0) return false;

        // Raw math (instead of FixedPoint.divDown) for this ratio computation:
        // imbalance = (max / min) in 18-dec fixed point.
        uint256 imbalance = (maxBalance * 1e18) / minBalance;
        return imbalance < MAX_IMBALANCE_RATIO;
    }

    function _getMinAndMaxBalances(
        uint256[] memory balances
    ) internal pure returns (uint256 minBalance, uint256 maxBalance) {
        minBalance = type(uint256).max;
        maxBalance = 0;
        for (uint256 i = 0; i < balances.length; ++i) {
            uint256 b = balances[i];
            if (b < minBalance) minBalance = b;
            if (b > maxBalance) maxBalance = b;
        }
    }

    function _boundValue(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (x % (max - min + 1));
    }
}
