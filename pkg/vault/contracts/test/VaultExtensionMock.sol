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

    function getRouterApprovalDigest(
        address sender,
        address router,
        bool approved,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        SET_RELAYER_APPROVAL_TYPEHASH,
                        sender,
                        router,
                        approved,
                        nonces(sender) + nonce,
                        deadline
                    )
                )
            );
    }

    function hashTypedDataV4(bytes32 data) public view returns (bytes32) {
        return _hashTypedDataV4(data);
    }
}
