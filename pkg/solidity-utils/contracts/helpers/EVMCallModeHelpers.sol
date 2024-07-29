// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Library used to check whether the current operation was initiated through a static call.
library EVMCallModeHelpers {
    /// @dev A state-changing transaction was initiated in a context that only allows static calls.
    error NotStaticCall();

    /**
     * @dev Detects whether the current transaction is a static call.
     * A static call is one where `tx.origin` equals 0x0 for most implementations.
     * See this tweet for a table on how transaction parameters are set on different platforms:
     * https://twitter.com/0xkarmacoma/status/1493380279309717505
     *
     * Solidity eth_call reference docs are here: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_call
     */
    function isStaticCall() internal view returns (bool) {
        return tx.origin == address(0);
        // solhint-disable-previous-line avoid-tx-origin
    }
}
