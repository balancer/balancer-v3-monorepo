// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../vault/VaultTypes.sol";

interface IVaultUnitTestsMock {
    function manualSetLockers(address[] memory lockers) external;

    function manualSetInitializedPool(address pool, bool isPoolInitialized) external;

    function manualSetPoolPaused(address, bool, uint256) external;

    function manualSetVaultState(bool, bool, uint256, uint256) external;

    function testWithLocker() external view;

    function testWithInitializedPool(address pool) external view;

    function testEnsurePoolNotPaused(address) external view;

    function testEnsureUnpausedAndGetVaultState(address) external view returns (VaultState memory);
}
