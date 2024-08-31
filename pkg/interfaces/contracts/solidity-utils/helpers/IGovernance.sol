// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "./IAuthorizer.sol";

/// @notice Get the Authorizer of a Balancer goverance controlled contract (e.g., the Vault).
interface IGovernance {
    /**
     * @notice Returns the address of the Authorizer contract, which stores permissions granted by governance.
     * @return Address of the Authorizer
     */
    function getAuthorizer() external view returns (IAuthorizer);
}
