// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdminMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultAdminMock.sol";

import "../VaultAdmin.sol";

contract VaultAdminMock is IVaultAdminMock, VaultAdmin {
    constructor(
        IVault mainVault,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration
    ) VaultAdmin(mainVault, pauseWindowDuration, bufferPeriodDuration) {}

    function manualPauseVault() external {
        _setVaultPaused(true);
    }

    function manualUnpauseVault() external {
        _setVaultPaused(false);
    }

    function manualPausePool(address pool) external {
        _setPoolPaused(pool, true);
    }

    function manualUnpausePool(address pool) external {
        _setPoolPaused(pool, false);
    }

    function manualEnableRecoveryMode(address pool) external {
        _ensurePoolNotInRecoveryMode(pool);
        _setPoolRecoveryMode(pool, true);
    }

    function manualDisableRecoveryMode(address pool) external {
        _ensurePoolInRecoveryMode(pool);
        _setPoolRecoveryMode(pool, false);
    }
}
