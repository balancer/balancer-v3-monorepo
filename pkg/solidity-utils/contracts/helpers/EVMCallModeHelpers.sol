// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

library EVMCallModeHelpers {
    /// @dev Indicates a state-changing transaction was initiated in a context that only allows static calls.
    error NotStaticCall();

    /// @dev Detects whether the current transaction is a static call.
    function isStaticCall() internal view returns (bool) {
        return tx.origin == address(0);
        // solhint-disable-previous-line avoid-tx-origin
    }
}
