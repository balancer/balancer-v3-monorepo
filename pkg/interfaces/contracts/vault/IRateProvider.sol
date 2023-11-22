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
     */
    function getUnderlyingToken() external view returns (IERC20);
}
