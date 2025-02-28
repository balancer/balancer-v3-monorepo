// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CommonAuthentication } from "@balancer-labs/v3-vault/contracts/CommonAuthentication.sol";

/// @dev Base contract for performing access control on external functions within pools.
abstract contract BasePoolAuthentication is CommonAuthentication {
    IVault private immutable _vault;

    /**
     * @dev Pools should use the pool factory as the disambiguator passed into the base Authentication contract.
     * Otherwise, permissions would conflict if different pools reused function names.
     */
    constructor(IVault vault, address factory) CommonAuthentication(vault, bytes32(uint256(uint160(factory)))) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
