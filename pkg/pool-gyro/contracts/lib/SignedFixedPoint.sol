// SPDX-License-Identifier: LicenseRef-Gyro-1.0
// for information on licensing please see the README in the GitHub repository <https://github.com/gyrostable/concentrated-lps>.

pragma solidity ^0.8.24;

/* solhint-disable private-vars-leading-underscore */

/// @dev Signed fixed point operations based on Balancer's FixedPoint library.
/// Note: The `{mul,div}{UpMag,DownMag}()` functions do *not* round up or down, respectively,
/// in a signed fashion (like ceil and floor operations), but *in absolute value* (or *magnitude*), i.e.,
/// towards 0. This is useful in some applications.
library SignedFixedPoint {
    error AddOverflow();
    error SubOverflow();
    error MulOverflow();
    error ZeroDivision();
    error DivInterval();

    int256 internal constant ONE = 1e18; // 18 decimal places
    // setting extra precision at 38 decimals, which is the most we can get w/o overflowing on normal multiplication
    // this allows 20 extra digits to absorb error when multiplying by large numbers
    int256 internal constant ONE_XP = 1e38; // 38 decimal places

    function add(int256 a, int256 b) internal pure returns (int256) {
        // Fixed Point addition is the same as regular checked addition

        int256 c = a + b;
        if (!(b >= 0 ? c >= a : c < a)) revert AddOverflow();
        return c;
    }

    function addMag(int256 a, int256 b) internal pure returns (int256 c) {
        // add b in the same signed direction as a, i.e. increase the magnitude of a by b
        c = a > 0 ? add(a, b) : sub(a, b);
    }

    function sub(int256 a, int256 b) internal pure returns (int256) {
        // Fixed Point subtraction is the same as regular checked subtraction

        int256 c = a - b;
        if (!(b <= 0 ? c >= a : c < a)) revert SubOverflow();
        return c;
    }

    /// @dev This rounds towards 0, i.e., down *in absolute value*!
    function mulDownMag(int256 a, int256 b) internal pure returns (int256) {
        int256 product = a * b;
        if (!(a == 0 || product / a == b)) revert MulOverflow();

        return product / ONE;
    }

    /// @dev this implements mulDownMag w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function mulDownMagU(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / ONE;
    }

    /// @dev This rounds away from 0, i.e., up *in absolute value*!
    function mulUpMag(int256 a, int256 b) internal pure returns (int256) {
        int256 product = a * b;
        if (!(a == 0 || product / a == b)) revert MulOverflow();

        // If product > 0, the result should be ceil(p/ONE) = floor((p-1)/ONE) + 1, where floor() is implicit. If
        // product < 0, the result should be floor(p/ONE) = ceil((p+1)/ONE) - 1, where ceil() is implicit.
        // Addition for signed numbers: Case selection so we round away from 0, not always up.
        if (product > 0) return ((product - 1) / ONE) + 1;
        else if (product < 0) return ((product + 1) / ONE) - 1;
        // product == 0
        return 0;
    }

    /// @dev this implements mulUpMag w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function mulUpMagU(int256 a, int256 b) internal pure returns (int256) {
        int256 product = a * b;

        // If product > 0, the result should be ceil(p/ONE) = floor((p-1)/ONE) + 1, where floor() is implicit. If
        // product < 0, the result should be floor(p/ONE) = ceil((p+1)/ONE) - 1, where ceil() is implicit.
        // Addition for signed numbers: Case selection so we round away from 0, not always up.
        if (product > 0) return ((product - 1) / ONE) + 1;
        else if (product < 0) return ((product + 1) / ONE) - 1;
        // product == 0
        return 0;
    }

    /// @dev Rounds towards 0, i.e., down in absolute value.
    function divDownMag(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert ZeroDivision();

        if (a == 0) {
            return 0;
        }

        int256 aInflated = a * ONE;
        if (aInflated / a != ONE) revert DivInterval();

        return aInflated / b;
    }

    /// @dev this implements divDownMag w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function divDownMagU(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert ZeroDivision();
        return (a * ONE) / b;
    }

    /// @dev Rounds away from 0, i.e., up in absolute value.
    function divUpMag(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert ZeroDivision();

        if (a == 0) {
            return 0;
        }

        if (b < 0) {
            // Required so the below is correct.
            b = -b;
            a = -a;
        }

        int256 aInflated = a * ONE;
        if (aInflated / a != ONE) revert DivInterval();

        if (aInflated > 0) return ((aInflated - 1) / b) + 1;
        return ((aInflated + 1) / b) - 1;
    }

    /// @dev this implements divUpMag w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function divUpMagU(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert ZeroDivision();

        if (a == 0) {
            return 0;
        }

        // SOMEDAY check if we can shave off some gas by logically refactoring this vs the below case distinction into one (on a * b or so).
        if (b < 0) {
            // Ensure b > 0 so the below is correct.
            b = -b;
            a = -a;
        }

        if (a > 0) return ((a * ONE - 1) / b) + 1;
        return ((a * ONE + 1) / b) - 1;
    }

    /// @dev multiplies two extra precision numbers (with 38 decimals)
    /// rounds down in magnitude but this shouldn't matter
    /// multiplication can overflow if a,b are > 2 in magnitude
    function mulXp(int256 a, int256 b) internal pure returns (int256) {
        int256 product = a * b;
        if (!(a == 0 || product / a == b)) revert MulOverflow();

        return product / ONE_XP;
    }

    /// @dev multiplies two extra precision numbers (with 38 decimals)
    /// rounds down in magnitude but this shouldn't matter
    /// multiplication can overflow if a,b are > 2 in magnitude
    /// this implements mulXp w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function mulXpU(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / ONE_XP;
    }

    /// @dev divides two extra precision numbers (with 38 decimals)
    /// rounds down in magnitude but this shouldn't matter
    /// can overflow if a > 2 or b << 1 in magnitude
    function divXp(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert ZeroDivision();

        if (a == 0) {
            return 0;
        }

        int256 aInflated = a * ONE_XP;
        if (aInflated / a != ONE_XP) revert DivInterval();

        return aInflated / b;
    }

    /// @dev divides two extra precision numbers (with 38 decimals)
    /// rounds down in magnitude but this shouldn't matter
    /// can overflow if a > 2 or b << 1 in magnitude
    /// this implements divXp w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function divXpU(int256 a, int256 b) internal pure returns (int256) {
        if (b == 0) revert ZeroDivision();

        return (a * ONE_XP) / b;
    }

    /// @dev multiplies normal precision a with extra precision b (with 38 decimals)
    /// Rounds down in signed direction
    /// returns normal precision of the product
    function mulDownXpToNp(int256 a, int256 b) internal pure returns (int256) {
        int256 b1 = b / 1e19;
        int256 prod1 = a * b1;
        if (!(a == 0 || prod1 / a == b1)) revert MulOverflow();
        int256 b2 = b % 1e19;
        int256 prod2 = a * b2;
        if (!(a == 0 || prod2 / a == b2)) revert MulOverflow();
        return prod1 >= 0 && prod2 >= 0 ? (prod1 + prod2 / 1e19) / 1e19 : (prod1 + prod2 / 1e19 + 1) / 1e19 - 1;
    }

    /// @dev multiplies normal precision a with extra precision b (with 38 decimals)
    /// Rounds down in signed direction
    /// returns normal precision of the product
    /// this implements mulDownXpToNp w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function mulDownXpToNpU(int256 a, int256 b) internal pure returns (int256) {
        int256 b1 = b / 1e19;
        int256 b2 = b % 1e19;
        // SOMEDAY check if we eliminate these vars and save some gas (by only checking the sign of prod1, say)
        int256 prod1 = a * b1;
        int256 prod2 = a * b2;
        return prod1 >= 0 && prod2 >= 0 ? (prod1 + prod2 / 1e19) / 1e19 : (prod1 + prod2 / 1e19 + 1) / 1e19 - 1;
    }

    /// @dev multiplies normal precision a with extra precision b (with 38 decimals)
    /// Rounds up in signed direction
    /// returns normal precision of the product
    function mulUpXpToNp(int256 a, int256 b) internal pure returns (int256) {
        int256 b1 = b / 1e19;
        int256 prod1 = a * b1;
        if (!(a == 0 || prod1 / a == b1)) revert MulOverflow();
        int256 b2 = b % 1e19;
        int256 prod2 = a * b2;
        if (!(a == 0 || prod2 / a == b2)) revert MulOverflow();
        return prod1 <= 0 && prod2 <= 0 ? (prod1 + prod2 / 1e19) / 1e19 : (prod1 + prod2 / 1e19 - 1) / 1e19 + 1;
    }

    /// @dev multiplies normal precision a with extra precision b (with 38 decimals)
    /// Rounds up in signed direction
    /// returns normal precision of the product
    /// this implements mulUpXpToNp w/o checking for over/under-flows, which saves significantly on gas if these aren't needed
    function mulUpXpToNpU(int256 a, int256 b) internal pure returns (int256) {
        int256 b1 = b / 1e19;
        int256 b2 = b % 1e19;
        // SOMEDAY check if we eliminate these vars and save some gas (by only checking the sign of prod1, say)
        int256 prod1 = a * b1;
        int256 prod2 = a * b2;
        return prod1 <= 0 && prod2 <= 0 ? (prod1 + prod2 / 1e19) / 1e19 : (prod1 + prod2 / 1e19 - 1) / 1e19 + 1;
    }

    // not implementing the pow functions right now b/c it's annoying and slightly ill-defined, and we don't use them.

    /**
     * @dev Returns the complement of a value (1 - x), capped to 0 if x is larger than 1.
     *
     * Useful when computing the complement for values with some level of relative error, as it strips this error and
     * prevents intermediate negative values.
     */
    function complement(int256 x) internal pure returns (int256) {
        if (x >= ONE || x <= 0) return 0;
        return ONE - x;
    }
}
