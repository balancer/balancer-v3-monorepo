// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IRateProvider {
    /**
     * @dev Returns an 18 decimal fixed point number that is the exchange rate of the token to some other underlying
     * token. The meaning of this rate depends on the context. We expect the rate to be constant over a wide range,
     * but some rate providers may behave differently when extremely unbalanced. To mitigate this effect, we allow
     * passing in a value when calculating the rate, vs. assuming it is always flat, in which case we could simply
     * pass in a constant FixedPoint.ONE or similar value.
     *
     * @param shares The number of shares
     * @return rate The calculated exchange rate given the number of shares
     */
    function getRate(uint256 shares) external view returns (uint256);
}
