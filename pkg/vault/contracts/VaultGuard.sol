// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

/// @notice Contract that shares the modifier `onlyVault`.
contract VaultGuard {
    IVault internal immutable _vault;

    constructor(IVault vault) {
        _vault = vault;
    }

    modifier onlyVault() {
        _ensureOnlyVault();
        _;
    }

    function _ensureOnlyVault() private view {
        if (msg.sender != address(_vault)) {
            revert IVaultErrors.SenderIsNotVault(msg.sender);
        }
    }
}
