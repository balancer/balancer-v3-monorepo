// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IVaultAdminMock {
    function manualPauseVault() external;

    function manualUnpauseVault() external;
}
