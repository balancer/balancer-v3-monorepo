// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

library AddressHelpers {
    /**
     * @dev
     */
    error NotStaticCall();

    /// @dev Detects if call is static
    function isStaticCall() internal view returns (bool) {
        return tx.origin == address(0);
        // solhint-disable-previous-line avoid-tx-origin
    }
}
