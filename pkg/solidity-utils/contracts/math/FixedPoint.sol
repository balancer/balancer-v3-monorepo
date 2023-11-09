// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./LogExpMath.sol";

/* solhint-disable private-vars-leading-underscore */

library FixedPoint {
    /// @dev Attempted division by zero.
    error ZeroDivision();

    // solhint-disable no-inline-assembly

    uint256 internal constant ONE = 1e18; // 18 decimal places
    uint256 internal constant TWO = 2 * ONE;
    uint256 internal constant FOUR = 4 * ONE;
    uint256 internal constant MAX_POW_RELATIVE_ERROR = 10000; // 10^(-14)

    // Minimum base for the power function when the exponent is 'free' (larger than ONE).
    uint256 internal constant MIN_POW_BASE_FREE_EXPONENT = 0.7e18;

    function mulDown(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256) {
        // Multiplication overflow protection is provided by Solidity 0.8.x
        uint256 product = a * b;

        return product / unit;
    }

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulDown(a, b, ONE);
    }

    function mulUp(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256 result) {
        // Multiplication overflow protection is provided by Solidity 0.8.x
        uint256 product = a * b;

        // The traditional divUp formula is:
        // divUp(x, y) := (x + y - 1) / y
        // To avoid intermediate overflow in the addition, we distribute the division and get:
        // divUp(x, y) := (x - 1) / y + 1
        // Note that this requires x != 0, if x == 0 then the result is zero
        //
        // Equivalent to:
        // result = product == 0 ? 0 : ((product - 1) / FixedPoint.ONE) + 1;
        assembly {
            result := mul(iszero(iszero(product)), add(div(sub(product, 1), unit), 1))
        }
    }

    function mulUp(uint256 a, uint256 b) internal pure returns (uint256 result) {
        return mulUp(a, b, ONE);
    }

    function divDown(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256) {
        // Solidity 0.8 reverts with a Panic code (0x11) if the multiplication overflows.
        uint256 aInflated = a * unit;

        // Solidity 0.8 reverts with a "Division by Zero" Panic code (0x12) if b is zero
        return aInflated / b;
    }

    function divDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return divDown(a, b, ONE);
    }

    function divUp(uint256 a, uint256 b, uint256 unit) internal pure returns (uint256 result) {
        // This check is required because Yul's `div` doesn't revert on b==0
        if (b == 0) {
            revert ZeroDivision();
        }

        // Multiple overflow protection is done by Solidity 0.8x
        uint256 aInflated = a * unit;

        // The traditional divUp formula is:
        // divUp(x, y) := (x + y - 1) / y
        // To avoid intermediate overflow in the addition, we distribute the division and get:
        // divUp(x, y) := (x - 1) / y + 1
        // Note that this requires x != 0, if x == 0 then the result is zero
        //
        // Equivalent to:
        // result = a == 0 ? 0 : (a * unit - 1) / b + 1;
        assembly {
            result := mul(iszero(iszero(aInflated)), add(div(sub(aInflated, 1), b), 1))
        }
    }

    function divUp(uint256 a, uint256 b) internal pure returns (uint256 result) {
        return divUp(a, b, ONE);
    }

    /**
     * @dev Returns x^y, assuming both are fixed point numbers, rounding down. The result is guaranteed to not be above
     * the true value (that is, the error function expected - actual is always positive).
     */
    function powDown(uint256 x, uint256 y) internal pure returns (uint256) {
        // Optimize for when y equals 1.0, 2.0 or 4.0, as those are very simple to implement and occur often in 50/50
        // and 80/20 Weighted Pools
        if (y == ONE) {
            return x;
        } else if (y == TWO) {
            return mulDown(x, x);
        } else if (y == FOUR) {
            uint256 square = mulDown(x, x);
            return mulDown(square, square);
        } else {
            uint256 raw = LogExpMath.pow(x, y);
            uint256 maxError = mulUp(raw, MAX_POW_RELATIVE_ERROR) + 1;

            if (raw < maxError) {
                return 0;
            } else {
                unchecked {
                    return raw - maxError;
                }
            }
        }
    }

    /**
     * @dev Returns x^y, assuming both are fixed point numbers, rounding up. The result is guaranteed to not be below
     * the true value (that is, the error function expected - actual is always negative).
     */
    function powUp(uint256 x, uint256 y) internal pure returns (uint256) {
        // Optimize for when y equals 1.0, 2.0 or 4.0, as those are very simple to implement and occur often in 50/50
        // and 80/20 Weighted Pools
        if (y == ONE) {
            return x;
        } else if (y == TWO) {
            return mulUp(x, x);
        } else if (y == FOUR) {
            uint256 square = mulUp(x, x);
            return mulUp(square, square);
        } else {
            uint256 raw = LogExpMath.pow(x, y);
            uint256 maxError = mulUp(raw, MAX_POW_RELATIVE_ERROR) + 1;

            return raw + maxError;
        }
    }

    function complement(uint256 x, uint256 unit) internal pure returns (uint256 result) {
        // Equivalent to:
        // result = (x < unit) ? (unit - x) : 0;
        assembly {
            result := mul(lt(x, unit), sub(unit, x))
        }
    }

    /**
     * @dev Returns the complement of a value (1 - x), capped to 0 if x is larger than 1.
     *
     * Useful when computing the complement for values with some level of relative error, as it strips this error and
     * prevents intermediate negative values.
     */
    function complement(uint256 x) internal pure returns (uint256 result) {
        return complement(x, ONE);
    }
}
