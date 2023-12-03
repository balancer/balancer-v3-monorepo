// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRateProvider {
    /**
     * @dev Returns an 18 decimal fixed point number that is the exchange rate of the token to some other underlying
     * token. The meaning of this rate depends on the context.
     */
    function getRate() external view returns (uint256);

    /**
     * @dev Return the underlying token, if the associated token is a wrapper, or zero otherwise.
     * @return The underlying token address, when supported
     */
    function getUnderlyingToken() external view returns (IERC20);

    /**
     * @dev Flag indicating whether the associated token supports wrapping/unwrapping (e.g., aDAI/DAI).
     * @return True if this token supports direct wrapping/unwrapping
     */
    function isWrappedToken() external view returns (bool);

    /**
     * @dev Flag indicating whether the associated token should be exempt from yield fees. Most commonly, this would
     * be set in cases where the rate does not represent a yield (e.g., EUR/USD). It could also be used for nested
     * pools, or for tokens where the rate is very volatile (e.g., to avoid double dipping when the rate goes down
     * and then back up).
     *
     * @return True if this token is yield exempt
     */
    function isExemptFromYieldProtocolFee() external view returns (bool);
}
