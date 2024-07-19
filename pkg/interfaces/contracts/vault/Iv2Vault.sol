// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IAuthorizer } from "./IAuthorizer.sol";

interface Iv2Vault {
    /**
     * @notice Returns the v2 Vault's Authorizer, as we are using the same contract for v3.
     * @return Address of the authorizer
     */
    function getAuthorizer() external view returns (IAuthorizer);
}
