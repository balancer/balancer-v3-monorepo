// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Interface for functions shared across all trusted routers.
interface ISenderGuard {
    /// @notice Incoming ETH transfer from an address that is not WETH.
    error EthTransfer();

    /// @notice The swap transaction was not validated before the specified deadline timestamp.
    error SwapDeadline();

    /**
     * @notice Get the sender stored for the current Router operation.
     * @dev Note that the stored value depends on the entry point. Execution entry points store the account that called
     * the router. Query entry points store the address passed as their `sender` argument, which need not be the
     * caller. Queries intentionally accept any address so that a quote can be requested for a third-party account.
     * The consequence is that a hook that prices by sender identity will quote for the address passed in, and execute
     * for the actual router caller.
     *
     * @return sender The address stored for the current operation
     */
    function getSender() external view returns (address sender);
}
