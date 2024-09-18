// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVaultAdminMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultAdminMock.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { VaultAdmin } from "../VaultAdmin.sol";

contract VaultAdminMock is IVaultAdminMock, VaultAdmin {
    using PackedTokenBalance for bytes32;

    constructor(
        IVault mainVault,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration,
        uint256 minTradeAmount,
        uint256 minWrapAmount
    ) VaultAdmin(mainVault, pauseWindowDuration, bufferPeriodDuration, minTradeAmount, minWrapAmount) {}

    function manualPauseVault() external {
        _setVaultPaused(true);
    }

    function manualUnpauseVault() external {
        _setVaultPaused(false);
    }

    function manualPausePool(address pool) external {
        _poolRoleAccounts[pool].pauseManager = msg.sender;
        _setPoolPaused(pool, true);
    }

    function manualUnpausePool(address pool) external {
        _poolRoleAccounts[pool].pauseManager = msg.sender;
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

    function manualAddLiquidityToBuffer(IERC4626 wrappedToken, uint256 underlyingAmount, uint256 wrappedAmount) public {
        bytes32 bufferBalances = _bufferTokenBalances[wrappedToken];

        if (underlyingAmount > 0) {
            IERC20(wrappedToken.asset()).transferFrom(msg.sender, address(this), underlyingAmount);
            _reservesOf[IERC20(wrappedToken.asset())] += underlyingAmount;
            // Issued shares amount = underlying amount.
            _bufferTotalShares[wrappedToken] += underlyingAmount;
            _bufferLpShares[wrappedToken][msg.sender] += underlyingAmount;
        }
        if (wrappedAmount > 0) {
            IERC20(address(wrappedToken)).transferFrom(msg.sender, address(this), wrappedAmount);
            _reservesOf[IERC20(address(wrappedToken))] += wrappedAmount;
            uint256 issuedSharesAmount = wrappedToken.previewRedeem(wrappedAmount);
            _bufferTotalShares[wrappedToken] += issuedSharesAmount;
            _bufferLpShares[wrappedToken][msg.sender] += issuedSharesAmount;
        }

        bufferBalances = PackedTokenBalance.toPackedBalance(
            bufferBalances.getBalanceRaw() + underlyingAmount,
            bufferBalances.getBalanceDerived() + wrappedAmount
        );
        _bufferTokenBalances[wrappedToken] = bufferBalances;
    }

    function manualReentrancyAddLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 exactSharesToIssue,
        address sharesOwner
    ) external nonReentrant {
        IVault(address(this)).addLiquidityToBuffer(wrappedToken, exactSharesToIssue, sharesOwner);
    }

    function manualReentrancyRemoveLiquidityFromBufferHook(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    ) external nonReentrant {
        this.removeLiquidityFromBufferHook(wrappedToken, sharesToRemove, sharesOwner);
    }

    function manualReentrancyDisableRecoveryMode(address pool) external nonReentrant {
        this.disableRecoveryMode(pool);
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

    function manualBurnBufferShares(IERC4626 wrappedToken, address from, uint256 amount) external {
        _burnBufferShares(wrappedToken, from, amount);
    }

    function manualMintMinimumBufferSupplyReserve(IERC4626 wrappedToken) external {
        _mintMinimumBufferSupplyReserve(wrappedToken);
    }
}
