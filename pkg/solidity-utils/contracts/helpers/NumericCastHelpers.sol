// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

library NumericCastHelpers {
    function negateUint256(uint256 a) internal pure returns (int256) {
        _require(a > 0, Errors.ZERO_NEGATION);

        return int256(type(uint256).max - a + 1);
    }
}
