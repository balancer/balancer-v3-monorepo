// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/BalancerErrors.sol";

contract BalancerErrorsMock {
    function fail(uint256 code) external pure {
        _revert(code);
    }

    function failWithPrefix(uint256 code, bytes3 prefix) external pure {
        _revert(code, prefix);
    }
}
