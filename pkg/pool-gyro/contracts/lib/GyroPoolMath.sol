// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository
// <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

library GyroPoolMath {
    using FixedPoint for uint256;

    uint256 private constant _SQRT_1E_NEG_1 = 316227766016837933;
    uint256 private constant _SQRT_1E_NEG_3 = 31622776601683793;
    uint256 private constant _SQRT_1E_NEG_5 = 3162277660168379;
    uint256 private constant _SQRT_1E_NEG_7 = 316227766016837;
    uint256 private constant _SQRT_1E_NEG_9 = 31622776601683;
    uint256 private constant _SQRT_1E_NEG_11 = 3162277660168;
    uint256 private constant _SQRT_1E_NEG_13 = 316227766016;
    uint256 private constant _SQRT_1E_NEG_15 = 31622776601;
    uint256 private constant _SQRT_1E_NEG_17 = 3162277660;

    // Note: this function is identical to that in WeightedMath.sol audited by Balancer
    function calcAllTokensInGivenExactBptOut(
        uint256[] memory balances,
        uint256 bptOut,
        uint256 totalBPT
    ) internal pure returns (uint256[] memory amountsIn) {
        /************************************************************************************
        // tokensInForExactBptOut                                                          //
        //                              /   bptOut   \                                     //
        // amountsIn[i] = balances[i] * | ------------ |                                   //
        //                              \  totalBPT  /                                     //
        ************************************************************************************/
        // We adjust the order of operations to minimize error amplification, assuming that
        // balances[i], totalBPT > 1 (which is usually the case).
        // Tokens in, so we round up overall.

        amountsIn = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            amountsIn[i] = balances[i].mulUp(bptOut).divUp(totalBPT);
        }

        return amountsIn;
    }

    // Note: this function is identical to that in WeightedMath.sol audited by Balancer
    function calcTokensOutGivenExactBptIn(
        uint256[] memory balances,
        uint256 bptIn,
        uint256 totalBPT
    ) internal pure returns (uint256[] memory amountsOut) {
        /**********************************************************************************************
        // exactBPTInForTokensOut                                                                    //
        // (per token)                                                                               //
        //                                /        bptIn         \                                   //
        // amountsOut[i] = balances[i] * | ---------------------  |                                  //
        //                                \       totalBPT       /                                   //
        **********************************************************************************************/
        // We adjust the order of operations to minimize error amplification, assuming that
        // balances[i], totalBPT > 1 (which is usually the case).
        // Since we're computing an amount out, we round down overall. This means rounding down on both the
        // multiplication and division.

        amountsOut = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            amountsOut[i] = balances[i].mulDown(bptIn).divDown(totalBPT);
        }

        return amountsOut;
    }

    /** @dev Calculates protocol fees due to Gyro and Balancer
     *   Note: we do this differently than normal Balancer pools by paying fees in BPT tokens
     *   b/c this is much more gas efficient than doing many transfers of underlying assets
     *   This function gets protocol fee parameters from GyroConfig
     */
    function calcProtocolFees(
        uint256 previousInvariant,
        uint256 currentInvariant,
        uint256 currentBptSupply,
        uint256 protocolSwapFeePerc,
        uint256 protocolFeeGyroPortion
    ) internal pure returns (uint256, uint256) {
        /*********************************************************************************
        /*  Protocol fee collection should decrease the invariant L by
        *        Delta L = protocolSwapFeePerc * (currentInvariant - previousInvariant)
        *   To take these fees in BPT LP shares, the protocol mints Delta S new LP shares where
        *        Delta S = S * Delta L / ( currentInvariant - Delta L )
        *   where S = current BPT supply
        *   The protocol then splits the fees (in BPT) considering protocolFeeGyroPortion
        *   See also the write-up, Proposition 7.
        *********************************************************************************/

        if (currentInvariant <= previousInvariant) {
            // This shouldn't happen outside of rounding errors, but have this safeguard nonetheless to prevent the
            // Pool from entering a locked state in which joins and exits revert while computing accumulated swap fees.
            // NB: This condition is also used by the pools to indicate that _lastInvariant is invalid and should be
            // ignored.
            return (0, 0);
        }

        // Calculate due protocol fees in BPT terms
        // We round down to prevent issues in the Pool's accounting, even if it means paying slightly less in protocol
        // fees to the Vault.
        // For the numerator, we need to round down delta L. Also for the denominator b/c subtracted
        // Ordering multiplications for best fixed point precision considering that S and
        // currentInvariant-previousInvariant could be large
        uint256 numerator = (currentBptSupply.mulDown(currentInvariant - previousInvariant)).mulDown(
            protocolSwapFeePerc
        );
        uint256 diffInvariant = protocolSwapFeePerc.mulDown(currentInvariant - previousInvariant);
        uint256 denominator = currentInvariant - diffInvariant;
        uint256 deltaS = numerator.divDown(denominator);

        // numerator = totalSupply * (currentInvariant - previousInvariant) * protocolSwapFeePercentage
        // diffInvariant = protocolSwapFeePercentage * (currentInvariant - previousInvariant)
        // deonminator = currentInvariant - diffInvariant

        // owedBpt =        totalSupply * (currentInvariant - previousInvariant) * protocolSwapFeePercentage
        //                  --------------------------------------------------------------------------------
        //                  currentInvariant - (protocolSwapFeePercentage * (currentInvariant - previousInvariant))

        // Split fees between Gyro and Balancer
        uint256 gyroFees = protocolFeeGyroPortion.mulDown(deltaS);
        uint256 balancerFees = deltaS - gyroFees;

        return (gyroFees, balancerFees);
    }

    /** @dev Implements square root algorithm using Newton's method and a first-guess optimisation **/
    function sqrt(uint256 input, uint256 tolerance) internal pure returns (uint256) {
        if (input == 0) {
            return 0;
        }

        uint256 guess = _makeInitialGuess(input);

        // 7 iterations
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;

        // Check in some epsilon range
        // Check square is more or less correct
        uint256 guessSquared = guess.mulDown(guess);
        require(
            guessSquared <= input + guess.mulUp(tolerance) && guessSquared >= input - guess.mulUp(tolerance),
            "_sqrt FAILED"
        );

        return guess;
    }

    function _makeInitialGuess(uint256 input) private pure returns (uint256) {
        if (input >= FixedPoint.ONE) {
            return (1 << (_intLog2Halved(input / FixedPoint.ONE))) * FixedPoint.ONE;
        } else {
            if (input <= 10) {
                return _SQRT_1E_NEG_17;
            }
            if (input <= 1e2) {
                return 1e10;
            }
            if (input <= 1e3) {
                return _SQRT_1E_NEG_15;
            }
            if (input <= 1e4) {
                return 1e11;
            }
            if (input <= 1e5) {
                return _SQRT_1E_NEG_13;
            }
            if (input <= 1e6) {
                return 1e12;
            }
            if (input <= 1e7) {
                return _SQRT_1E_NEG_11;
            }
            if (input <= 1e8) {
                return 1e13;
            }
            if (input <= 1e9) {
                return _SQRT_1E_NEG_9;
            }
            if (input <= 1e10) {
                return 1e14;
            }
            if (input <= 1e11) {
                return _SQRT_1E_NEG_7;
            }
            if (input <= 1e12) {
                return 1e15;
            }
            if (input <= 1e13) {
                return _SQRT_1E_NEG_5;
            }
            if (input <= 1e14) {
                return 1e16;
            }
            if (input <= 1e15) {
                return _SQRT_1E_NEG_3;
            }
            if (input <= 1e16) {
                return 1e17;
            }
            if (input <= 1e17) {
                return _SQRT_1E_NEG_1;
            }
            return input;
        }
    }

    function _intLog2Halved(uint256 x) private pure returns (uint256 n) {
        if (x >= 1 << 128) {
            x >>= 128;
            n += 64;
        }
        if (x >= 1 << 64) {
            x >>= 64;
            n += 32;
        }
        if (x >= 1 << 32) {
            x >>= 32;
            n += 16;
        }
        if (x >= 1 << 16) {
            x >>= 16;
            n += 8;
        }
        if (x >= 1 << 8) {
            x >>= 8;
            n += 4;
        }
        if (x >= 1 << 4) {
            x >>= 4;
            n += 2;
        }
        if (x >= 1 << 2) {
            x >>= 2;
            n += 1;
        }
    }

    /*
     *  @dev If liquidity update is proportional so that price stays the same ("balanced liquidity update"), then this
     *  returns the invariant after that change. This is more efficient than calling `calculateInvariant()` on the
     *  updated balances.
     *  `isIncreaseLiq` denotes the sign of the update. See the writeup, Corollary 3 in Section 3.1.3.
     */
    function liquidityInvariantUpdate(
        uint256 uinvariant,
        uint256 changeBptSupply,
        uint256 currentBptSupply,
        bool isIncreaseLiq
    ) internal pure returns (uint256 unewInvariant) {
        //  change in invariant
        if (isIncreaseLiq) {
            // round new invariant up so that protocol fees not triggered
            uint256 dL = uinvariant.mulUp(changeBptSupply).divUp(currentBptSupply);
            unewInvariant = uinvariant + dL;
        } else {
            // round new invariant up (and so round dL down) so that protocol fees not triggered
            uint256 dL = uinvariant.mulDown(changeBptSupply).divDown(currentBptSupply);
            unewInvariant = uinvariant - dL;
        }
    }

    /** @dev If `deltaBalances` are such that, when changing `balances` by it, the price stays the same ("balanced
     * liquidity update"), then this returns the invariant after that change. This is more efficient than calling
     * `calculateInvariant()` on the updated balances. `isIncreaseLiq` denotes the sign of the update.
     * See the writeup, Corollary 3 in Section 3.1.3.
     *
     * DEPRECATED and will go out of use and be removed once pending changes to the ECLP are merged. Use the other
     * liquidityInvariantUpdate() function instead!
     */
    function liquidityInvariantUpdate(
        uint256[] memory balances,
        uint256 uinvariant,
        uint256[] memory deltaBalances,
        bool isIncreaseLiq
    ) internal pure returns (uint256 unewInvariant) {
        uint256 largestBalanceIndex;
        uint256 largestBalance;
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] > largestBalance) {
                largestBalance = balances[i];
                largestBalanceIndex = i;
            }
        }

        uint256 deltaInvariant = uinvariant.mulDown(deltaBalances[largestBalanceIndex]).divDown(
            balances[largestBalanceIndex]
        );
        unewInvariant = isIncreaseLiq ? uinvariant + deltaInvariant : uinvariant - deltaInvariant;
    }
}
