// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IVaultAdminMock {
    function manualPauseVault() external;

    function manualUnpauseVault() external;

    function manualPausePool(address pool) external;

    function manualUnpausePool(address pool) external;

    function manualEnableRecoveryMode(address pool) external;

    function manualDisableRecoveryMode(address pool) external;

    function hashTypedDataV4(bytes32 data) external view returns (bytes32);

    function getRouterApprovalDigest(
        address sender,
        address router,
        bool approved,
        uint256 nonce,
        uint256 deadline
    ) external view returns (bytes32);
}
