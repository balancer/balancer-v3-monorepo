// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;

import "../helpers/OptionalOnlyCaller.sol";

/**
 * @dev Mock with an external method that affects an address.
 *
 * The user can opt in to a verification, so that the method becomes callable
 * only by their address.
 */
contract OptionalOnlyCallerMock is OptionalOnlyCaller {
    constructor() EIP712("OptionalOnlyCallerMock", "1") {}

    event CheckFunctionCalled();

    function checkFunction(address user) external optionalOnlyCaller(user) {
        emit CheckFunctionCalled();
    }
}
