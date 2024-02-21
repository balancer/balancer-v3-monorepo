// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtensionMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultExtensionMock.sol";

import "../VaultExtension.sol";

contract VaultExtensionMock is IVaultExtensionMock, VaultExtension {
    using PoolConfigLib for PoolConfig;

    // Keep track of old swap fees, so that they can be restored in setSwapFeeDisabled.
    mapping(address => uint64) private _poolSwapFees;

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

    function setSwapFeeDisabled(address pool, bool swapFeeDisabled) external {
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        uint64 newSwapFee = 0;

        if (swapFeeDisabled) {
            // Store current fee.
            _poolSwapFees[pool] = config.staticSwapFeePercentage;
        } else {
            // Recover original fee, if re-enabling.
            newSwapFee = _poolSwapFees[pool];
        }
        config.staticSwapFeePercentage = newSwapFee;

        // Write back to the poolConfig.
        _poolConfig[pool] = config.fromPoolConfig();
    }
}
