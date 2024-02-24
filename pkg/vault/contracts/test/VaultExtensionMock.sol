// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtensionMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultExtensionMock.sol";

import "../VaultExtension.sol";

contract VaultExtensionMock is IVaultExtensionMock, VaultExtension {
    using PoolConfigLib for PoolConfig;
    using SafeCast for uint256;

    constructor(
        IVault vault,
        IVaultAdmin vaultAdmin,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) VaultExtension(vault, vaultAdmin, pauseWindowDuration, bufferPeriodDuration) {}

    function mockExtensionHash(bytes calldata input) external payable returns (bytes32) {
        return keccak256(input);
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

    function manuallySetSwapFee(address pool, uint256 newSwapFee) external {
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        config.staticSwapFeePercentage = newSwapFee.toUint64();
        _poolConfig[pool] = config.fromPoolConfig();
    }
}
