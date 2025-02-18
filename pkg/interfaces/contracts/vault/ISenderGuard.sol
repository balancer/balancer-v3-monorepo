// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Interface for functions shared across all trusted routers.
interface ISenderGuard {
    /// @notice Incoming ETH transfer from an address that is not WETH.
    error EthTransfer();

    /// @notice The swap transaction was not validated before the specified deadline timestamp.
    error SwapDeadline();

    /**
     * @notice Get the first sender which initialized the call to Router.
     * @return sender The address of the sender
     */
    function getSender() external view returns (address sender);
}
