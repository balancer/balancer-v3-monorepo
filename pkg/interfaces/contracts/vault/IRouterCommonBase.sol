// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IWETH } from "../solidity-utils/misc/IWETH.sol";

/// @notice Interface for functions shared across all trusted routers.
interface IRouterCommonBase {
    /// @notice Incoming ETH transfer from an address that is not WETH.
    error EthTransfer();

    /// @notice The swap transaction was not validated before the specified deadline timestamp.
    error SwapDeadline();

    /// @notice Returns WETH contract address.
    function getWeth() external view returns (IWETH);

    /**
     * @notice Get the first sender which initialized the call to Router.
     * @return sender The address of the sender
     */
    function getSender() external view returns (address sender);
}
