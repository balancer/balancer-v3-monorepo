// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CommonAuthentication } from "../CommonAuthentication.sol";

contract CommonAuthenticationMock is CommonAuthentication {
    constructor(IVault vault, bytes32 actionIdDisambiguator) CommonAuthentication(vault, actionIdDisambiguator) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function ensureAuthenticatedByExclusiveRole(address where, address roleAccount) external view {
        _ensureAuthenticatedByExclusiveRole(where, roleAccount);
    }

    function ensureAuthenticatedByRole(address where, address roleAccount) external view {
        _ensureAuthenticatedByRole(where, roleAccount);
    }
}
