// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtensionMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultExtensionMock.sol";

import "../VaultExtension.sol";

contract VaultExtensionMock is IVaultExtensionMock, VaultExtension {
    constructor(
        IVault vault,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) VaultExtension(vault, pauseWindowDuration, bufferPeriodDuration) {}

    function mockExtensionHash(bytes calldata input) external payable returns (bytes32) {
        return keccak256(input);
    }

    function manualPauseVault() external override {
        _setVaultPaused(true);
    }

    function manualUnpauseVault() external override {
        _setVaultPaused(false);
    }
}
