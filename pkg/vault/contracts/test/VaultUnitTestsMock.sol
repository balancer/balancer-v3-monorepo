// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVaultUnitTestsMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultUnitTestsMock.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultStateLib } from "../lib/VaultStateLib.sol";
import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

import { Vault } from "../Vault.sol";

contract VaultUnitTestsMock is IVaultUnitTestsMock, Vault {
    using PoolConfigLib for PoolConfig;
    using VaultStateLib for VaultState;

    constructor(IVaultExtension vaultExtension, IAuthorizer authorizer) Vault(vaultExtension, authorizer) {}

    function manualSetLockers(address[] memory lockers) public {
        _lockers = lockers;
    }

    function manualSetInitializedPool(address pool, bool isPoolInitialized) public {
        PoolConfig memory poolConfig = _poolConfig[pool].toPoolConfig();
        poolConfig.isPoolInitialized = isPoolInitialized;
        _poolConfig[pool] = poolConfig.fromPoolConfig();
    }

    function manualSetPoolPaused(address pool, bool isPoolPaused, uint256 pauseWindowEndTime) public {
        PoolConfig memory poolConfig = _poolConfig[pool].toPoolConfig();
        poolConfig.isPoolPaused = isPoolPaused;
        poolConfig.pauseWindowEndTime = pauseWindowEndTime;
        _poolConfig[pool] = poolConfig.fromPoolConfig();
    }

    function manualSetVaultState(
        bool isVaultPaused,
        bool isQueryDisabled,
        uint256 protocolSwapFeePercentage,
        uint256 protocolYieldFeePercentage
    ) public {
        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.isVaultPaused = isVaultPaused;
        vaultState.isQueryDisabled = isQueryDisabled;
        vaultState.protocolSwapFeePercentage = protocolSwapFeePercentage;
        vaultState.protocolYieldFeePercentage = protocolYieldFeePercentage;
        _vaultState = vaultState.fromVaultState();
    }

    function testWithLocker() public view withLocker {}

    function testWithInitializedPool(address pool) public view withInitializedPool(pool) {}

    function testEnsurePoolNotPaused(address pool) public view {
        _ensurePoolNotPaused(pool);
    }

    function testEnsureUnpausedAndGetVaultState(address pool) public view returns (VaultState memory vaultState) {
        vaultState = _ensureUnpausedAndGetVaultState(pool);
    }
}