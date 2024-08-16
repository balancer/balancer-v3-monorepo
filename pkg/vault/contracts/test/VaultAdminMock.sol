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

    function manualReentrancyInitializeBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
        address sharesOwner
    ) external nonReentrant {
        IVault(address(this)).initializeBuffer(wrappedToken, amountUnderlying, amountWrapped, sharesOwner);
    }

    function manualReentrancyAddLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
        address sharesOwner
    ) external nonReentrant {
        IVault(address(this)).addLiquidityToBuffer(wrappedToken, amountUnderlying, amountWrapped, sharesOwner);
    }

    function manualReentrancyRemoveLiquidityFromBufferHook(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    ) external nonReentrant {
        this.removeLiquidityFromBufferHook(wrappedToken, sharesToRemove, sharesOwner);
    }

    function mockWithValidPercentage(uint256 percentage) external pure withValidPercentage(percentage) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function mockEnsurePoolNotInRecoveryMode(address pool) external view {
        _ensurePoolNotInRecoveryMode(pool);
    }

    function manualMintBufferShares(IERC4626 wrappedToken, address to, uint256 amount) external {
        _mintBufferShares(wrappedToken, to, amount);
    }

    function manualMintMinimumBufferSupplyReserve(IERC4626 wrappedToken) external {
        _mintMinimumBufferSupplyReserve(wrappedToken);
    }
}
