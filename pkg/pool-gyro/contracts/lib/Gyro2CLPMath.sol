// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import "./GyroPoolMath.sol";

/** @dev Math routines for the 2CLP. Parameters are price bounds [alpha, beta] and sqrt(alpha), sqrt(beta) are used as
 * parameters.
 */
library Gyro2CLPMath {
    using FixedPoint for uint256;

    error AssetBoundsExceeded();

    // Invariant is used to calculate the virtual offsets used in swaps.
    // It is also used to collect protocol swap fees by comparing its value between two times.
    // We can always round in the same direction. It is also used to initialize the BPT amount and,
    // because there is a minimum BPT, we round the invariant down.
    function calculateInvariant(
        uint256[] memory balances,
        uint256 sqrtAlpha,
        uint256 sqrtBeta,
        Rounding rounding
    ) internal pure returns (uint256) {
        /**********************************************************************************************
        // Calculate with quadratic formula
        // 0 = (1-sqrt(alpha/beta)*L^2 - (y/sqrt(beta)+x*sqrt(alpha))*L - x*y)
        // 0 = a*L^2 + b*L + c
        // here a > 0, b < 0, and c < 0, which is a special case that works well w/o negative numbers
        // taking mb = -b and mc = -c:                               (1/2)
        //                                  mb + (mb^2 + 4 * a * mc)^                   //
        //                   L =    ------------------------------------------          //
        //                                          2 * a                               //
        //                                                                              //
        **********************************************************************************************/
        (uint256 a, uint256 mb, uint256 bSquare, uint256 mc) = calculateQuadraticTerms(
            balances,
            sqrtAlpha,
            sqrtBeta,
            rounding
        );

        return calculateQuadratic(a, mb, bSquare, mc);
    }

    /**
     * @notice Prepares quadratic terms for input to _calculateQuadratic.
     * @dev It uses a special case of the quadratic formula that works nicely without negative numbers, and
     * assumes a > 0, b < 0, and c <= 0.
     *
     * @param balances Pool balances
     * @param sqrtAlpha Square root of Gyro's 2CLP alpha parameter
     * @param sqrtBeta Square root of Gyro's 2CLP beta parameter
     * @param rounding Rounding direction of the invariant, which will be calculated using the quadratic terms
     * @return a Bhaskara's `a` term
     * @return mb Bhaskara's `b` term, negative (stands for minus b)
     * @return bSquare Bhaskara's `b^2` term. The calculation is optimized to be more precise than just b*b
     * @return mc Bhaskara's `c` term, negative (stands for minus c)
     */
    function calculateQuadraticTerms(
        uint256[] memory balances,
        uint256 sqrtAlpha,
        uint256 sqrtBeta,
        Rounding rounding
    ) internal pure returns (uint256 a, uint256 mb, uint256 bSquare, uint256 mc) {
        function(uint256, uint256) pure returns (uint256) _divUpOrDown = rounding == Rounding.ROUND_DOWN
            ? FixedPoint.divDown
            : FixedPoint.divUp;
        function(uint256, uint256) pure returns (uint256) _mulUpOrDown = rounding == Rounding.ROUND_DOWN
            ? FixedPoint.mulDown
            : FixedPoint.mulUp;

        // This is the inverse of mulUpAndDown, used to round denominator terms.
        function(uint256, uint256) pure returns (uint256) _mulDownOrUp = rounding == Rounding.ROUND_DOWN
            ? FixedPoint.mulUp
            : FixedPoint.mulDown;

        {
            // `a` follows the opposite rounding than `b` and `c`, since the most significant term is in the
            // denominator of Bhaskara's formula. To round the invariant up, we need to round `a` down, which means that
            // the division `sqrtAlpha/sqrtBeta` needs to be rounded up. In other words, if the given rounding
            // direction is UP, 'a' will be rounded DOWN and vice versa.
            a = FixedPoint.ONE - _divUpOrDown(sqrtAlpha, sqrtBeta);

            // `b` is a term in the numerator and should be rounded up if we want to increase the invariant.
            uint256 bterm0 = _divUpOrDown(balances[1], sqrtBeta);
            uint256 bterm1 = _mulUpOrDown(balances[0], sqrtAlpha);
            mb = bterm0 + bterm1;
            // `c` is a term in the numerator and should be rounded up if we want to increase the invariant.
            mc = _mulUpOrDown(balances[0], balances[1]);
        }
        // For better fixed point precision, calculate in expanded form, re-ordering multiplications.
        // `b^2 = x^2 * alpha + x*y*2*sqrt(alpha/beta) + y^2 / beta`
        bSquare = _mulUpOrDown(_mulUpOrDown(_mulUpOrDown(balances[0], balances[0]), sqrtAlpha), sqrtAlpha);
        uint256 bSq2 = _divUpOrDown(2 * _mulUpOrDown(_mulUpOrDown(balances[0], balances[1]), sqrtAlpha), sqrtBeta);
        uint256 bSq3 = _divUpOrDown(_mulUpOrDown(balances[1], balances[1]), _mulDownOrUp(sqrtBeta, sqrtBeta));
        bSquare = bSquare + bSq2 + bSq3;
    }

    /** @dev Calculates the quadratic root for a special case of the quadratic formula
     *   assumes a > 0, b < 0, and c <= 0, which is the case for a L^2 + b L + c = 0
     *   where   a = 1 - sqrt(alpha/beta)
     *           b = -(y/sqrt(beta) + x*sqrt(alpha))
     *           c = -x*y
     *   The special case works nicely without negative numbers.
     *   The args use the notation "mb" to represent -b, and "mc" to represent -c
     *   Note that this calculation underestimates the solution.
     */
    function calculateQuadratic(
        uint256 a,
        uint256 mb,
        uint256 bSquare, // b^2 can be calculated separately with more precision
        uint256 mc
    ) internal pure returns (uint256 invariant) {
        uint256 denominator = a.mulUp(2 * FixedPoint.ONE);
        // Order multiplications for fixed point precision.
        uint256 addTerm = (mc.mulDown(4 * FixedPoint.ONE)).mulDown(a);
        // The minus sign in the radicand cancels out in this special case.
        uint256 radicand = bSquare + addTerm;
        uint256 sqrResult = GyroPoolMath.sqrt(radicand, 5);
        // The minus sign in the numerator cancels out in this special case.
        uint256 numerator = mb + sqrResult;
        invariant = numerator.divDown(denominator);
    }

    /** @dev Computes how many tokens can be taken out of a pool if `amountIn' are sent, given current balances
     *   balanceIn = existing balance of input token
     *   balanceOut = existing balance of requested output token
     *   virtualParamIn = virtual reserve offset for input token
     *   virtualParamOut = virtual reserve offset for output token
     *   Offsets are L/sqrt(beta) and L*sqrt(alpha) depending on what the `in' and `out' tokens are respectively
     *   Note signs are changed compared to Prop. 4 in Section 2.2.4 Trade (Swap) Execution to account for dy < 0
     *
     *   The virtualOffset argument depends on the computed invariant. We add a very small margin to ensure that
     *   potential small errors are not to the detriment of the pool.
     *
     *   There is a corresponding function in the 3CLP, except that there we allow two different virtual "in" and
     *   "out" assets.
     *   SOMEDAY: This could be made literally the same function in the pool math library.
     */
    function calcOutGivenIn(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountIn,
        uint256 virtualOffsetIn,
        uint256 virtualOffsetOut
    ) internal pure returns (uint256 amountOut) {
        /**********************************************************************************************
      // Described for X = `in' asset and Y = `out' asset, but equivalent for the other case       //
      // dX = incrX  = amountIn  > 0                                                               //
      // dY = incrY = amountOut < 0                                                                //
      // x = balanceIn             x' = x +  virtualParamX                                         //
      // y = balanceOut            y' = y +  virtualParamY                                         //
      // L  = inv.Liq                   /            x' * y'          \          y' * dX           //
      //                   |dy| = y' - |   --------------------------  |   = --------------  -     //
      //  x' = virtIn                   \          ( x' + dX)         /          x' + dX           //
      //  y' = virtOut                                                                             //
      // Note that -dy > 0 is what the trader receives.                                            //
      // We exploit the fact that this formula is symmetric up to virtualOffset{X,Y}.               //
      // We do not use L^2, but rather x' * y', to prevent a potential accumulation of errors.      //
      // We add a very small safety margin to compensate for potential errors in the invariant.     //
      **********************************************************************************************/

        {
            // The factors in total lead to a multiplicative "safety margin" between the employed virtual offsets
            // that is very slightly larger than 3e-18.
            uint256 virtInOver = balanceIn + virtualOffsetIn.mulUp(FixedPoint.ONE + 2);
            uint256 virtOutUnder = balanceOut + (virtualOffsetOut).mulDown(FixedPoint.ONE - 1);

            amountOut = virtOutUnder.mulDown(amountIn).divDown(virtInOver + amountIn);
        }

        // This ensures amountOut < balanceOut.
        if (!(amountOut <= balanceOut)) {
            revert AssetBoundsExceeded();
        }
    }

    /** @dev Computes how many tokens must be sent to a pool in order to take `amountOut`, given current balances.
     * See also _calcOutGivenIn(). Adapted for negative values. */
    function calcInGivenOut(
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountOut,
        uint256 virtualOffsetIn,
        uint256 virtualOffsetOut
    ) internal pure returns (uint256 amountIn) {
        /**********************************************************************************************
      // dX = incrX  = amountIn  > 0                                                                 //
      // dY = incrY  = amountOut < 0                                                                 //
      // x = balanceIn             x' = x +  virtualParamX                                           //
      // y = balanceOut            y' = y +  virtualParamY                                           //
      // x = balanceIn                                                                               //
      // L  = inv.Liq               /            x' * y'          \                x' * dy           //
      //                     dx =  |   --------------------------  |  -  x'  = - -----------         //
      // x' = virtIn               \             y' + dy          /                y' + dy           //
      // y' = virtOut                                                                                //
      // Note that dy < 0 < dx.                                                                      //
      // We exploit the fact that this formula is symmetric up to virtualOffset{X,Y}.                //
      // We do not use L^2, but rather x' * y', to prevent a potential accumulation of errors.       //
      // We add a very small safety margin to compensate for potential errors in the invariant.      //
      **********************************************************************************************/
        if (!(amountOut <= balanceOut)) {
            revert AssetBoundsExceeded();
        }

        {
            // The factors in total lead to a multiplicative "safety margin" between the employed virtual offsets
            // that is very slightly larger than 3e-18.
            uint256 virtInOver = balanceIn + virtualOffsetIn.mulUp(FixedPoint.ONE + 2);
            uint256 virtOutUnder = balanceOut + virtualOffsetOut.mulDown(FixedPoint.ONE - 1);

            amountIn = virtInOver.mulUp(amountOut).divUp(virtOutUnder - amountOut);
        }
    }

    /** @dev Calculate the virtual offset `a` for reserves `x`, as in (x+a)*(y+b)=L^2
     */
    function calculateVirtualParameter0(uint256 invariant, uint256 _sqrtBeta) internal pure returns (uint256) {
        return invariant.divDown(_sqrtBeta);
    }

    /** @dev Calculate the virtual offset `b` for reserves `y`, as in (x+a)*(y+b)=L^2
     */
    function calculateVirtualParameter1(uint256 invariant, uint256 _sqrtAlpha) internal pure returns (uint256) {
        return invariant.mulDown(_sqrtAlpha);
    }

    /** @dev Calculates the spot price of token A in units of token B.
     *
     * The spot price is bounded by pool parameters due to virtual reserves. Aside from being instantaneously
     * manipulable within a transaction, it may also not be accurate if the true price is outside of these bounds.
     */
    function calcSpotPriceAinB(
        uint256 balanceA,
        uint256 virtualParameterA,
        uint256 balanceB,
        uint256 virtualParameterB
    ) internal pure returns (uint256) {
        return (balanceB + virtualParameterB).divUp((balanceA + virtualParameterA));
    }
}
