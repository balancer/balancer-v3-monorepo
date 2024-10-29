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

    /** @dev Implements a square root algorithm using Newton's method and a first-guess optimization. **/
    function sqrt(uint256 input, uint256 tolerance) internal pure returns (uint256) {
        if (input == 0) {
            return 0;
        }

        uint256 guess = _makeInitialGuess(input);

        // At this point `guess` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iterations to turn our partial result with one bit of precision
        // into the expected uint128 result.
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;
        guess = (guess + ((input * FixedPoint.ONE) / guess)) / 2;

        // Check that squaredGuess (guess * guess) is close enough from input. `guess` has less than 1 wei error, but
        // the loss of precision in the 18 decimal representation causes an error in the squared number, which must be
        // less than `(guess * tolerance) / FixedPoint.ONE`. Tolerance, in this case, is a very small number (< 10),
        // so the tolerance will be very small too.
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
}
