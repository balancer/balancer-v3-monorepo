// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { PoolData, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";
import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { PoolConfigBits, PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultStorage } from "./VaultStorage.sol";
import { ERC20MultiToken } from "./token/ERC20MultiToken.sol";
import { PoolDataLib } from "./lib/PoolDataLib.sol";

/**
 * @notice Functions and modifiers shared between the main Vault and its extension contracts.
 * @dev This contract contains common utilities in the inheritance chain that require storage to work,
 * and will be required in both the main Vault and its extensions.
 */
abstract contract VaultCommon is IVaultEvents, IVaultErrors, VaultStorage, ReentrancyGuardTransient, ERC20MultiToken {
    using PoolConfigLib for PoolConfigBits;
    using VaultStateLib for VaultStateBits;
    using SafeCast for *;
    using TransientStorageHelpers for *;
    using StorageSlotExtension for *;
    using PoolDataLib for PoolData;

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @dev This modifier ensures that the function it modifies can only be called
     * when a tab has been opened.
     */
    modifier onlyWhenUnlocked() {
        _ensureUnlocked();
        _;
    }

    function _ensureUnlocked() internal view {
        if (_isUnlocked().tload() == false) {
            revert VaultIsNotUnlocked();
        }
    }

    /**
     * @notice Expose the state of the Vault's reentrancy guard.
     * @return True if the Vault is currently executing a nonReentrant function
     */
    function reentrancyGuardEntered() public view returns (bool) {
        return _reentrancyGuardEntered();
    }

    /**
     * @notice Records the `credit` for a given token.
     * @param token The ERC20 token for which the 'credit' will be accounted
     * @param credit The amount of `token` supplied to the Vault in favor of the caller
     */
    function _supplyCredit(IERC20 token, uint256 credit) internal {
        _accountDelta(token, -credit.toInt256());
    }

    /**
     * @notice Records the `debt` for a given token.
     * @param token The ERC20 token for which the `debt` will be accounted
     * @param debt The amount of `token` taken from the Vault in favor of the caller
     */
    function _takeDebt(IERC20 token, uint256 debt) internal {
        _accountDelta(token, debt.toInt256());
    }

    /**
     * @dev Accounts the delta for the given token. A positive delta represents debt,
     * while a negative delta represents surplus.
     *
     * @param token The ERC20 token for which the delta is being accounted
     * @param delta The difference in the token balance
     * Positive indicates a debit or a decrease in Vault's tokens,
     * negative indicates a credit or an increase in Vault's tokens.
     */
    function _accountDelta(IERC20 token, int256 delta) internal {
        // If the delta is zero, there's nothing to account for.
        if (delta == 0) return;

        // Get the current recorded delta for this token.
        int256 current = _tokenDeltas().tGet(token);

        // Calculate the new delta after accounting for the change.
        int256 next = current + delta;

        unchecked {
            // If the resultant delta becomes zero after this operation,
            // decrease the count of non-zero deltas.
            if (next == 0) {
                _nonZeroDeltaCount().tDecrement();
            }
            // If there was no previous delta (i.e., it was zero) and now we have one,
            // increase the count of non-zero deltas.
            else if (current == 0) {
                _nonZeroDeltaCount().tIncrement();
            }
        }

        // Update the delta for this token.
        _tokenDeltas().tSet(token, next);
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @dev Modifier to make a function callable only when the Vault is not paused.
    modifier whenVaultNotPaused() {
        _ensureVaultNotPaused();
        _;
    }

    /// @dev Reverts if the Vault is paused.
    function _ensureVaultNotPaused() internal view {
        if (_isVaultPaused()) {
            revert VaultPaused();
        }
    }

    /// @dev Reverts if the Vault or the given pool are paused.
    function _ensureUnpaused(address pool) internal view {
        _ensureVaultNotPaused();
        _ensurePoolNotPaused(pool);
    }

    /**
     * @dev For gas efficiency, storage is only read before `_vaultBufferPeriodEndTime`. Once we're past that
     * timestamp, the expression short-circuits false, and the Vault is permanently unpaused.
     */
    function _isVaultPaused() internal view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp <= _vaultBufferPeriodEndTime && _vaultStateBits.isVaultPaused();
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /**
     * @dev Reverts if the pool is paused.
     * @param pool The pool
     */
    function _ensurePoolNotPaused(address pool) internal view {
        if (_isPoolPaused(pool)) {
            revert PoolPaused(pool);
        }
    }

    /// @dev Check both the flag and timestamp to determine whether the pool is paused.
    function _isPoolPaused(address pool) internal view returns (bool) {
        (bool paused, ) = _getPoolPausedState(pool);

        return paused;
    }

    /// @dev Lowest level routine that plucks only the minimum necessary parts from storage.
    function _getPoolPausedState(address pool) internal view returns (bool, uint32) {
        PoolConfigBits config = _poolConfigBits[pool];

        bool isPoolPaused = config.isPoolPaused();
        uint32 pauseWindowEndTime = config.getPauseWindowEndTime();

        // Use the Vault's buffer period.
        // solhint-disable-next-line not-rely-on-time
        return (isPoolPaused && block.timestamp <= pauseWindowEndTime + _vaultBufferPeriodDuration, pauseWindowEndTime);
    }

    /*******************************************************************************
                                     Buffer Pausing
    *******************************************************************************/
    /// @dev Modifier to make a function callable only when vault buffers are not paused.
    modifier whenVaultBuffersAreNotPaused() {
        _ensureVaultBuffersAreNotPaused();
        _;
    }

    /// @dev Reverts if vault buffers are paused.
    function _ensureVaultBuffersAreNotPaused() internal view {
        if (_vaultStateBits.areBuffersPaused()) {
            revert VaultBuffersArePaused();
        }
    }

    /*******************************************************************************
                            Pool Registration and Initialization
    *******************************************************************************/

    /// @dev Reverts unless `pool` is a registered Pool.
    modifier withRegisteredPool(address pool) {
        _ensureRegisteredPool(pool);
        _;
    }

    /// @dev Reverts unless `pool` is an initialized Pool.
    modifier withInitializedPool(address pool) {
        _ensureInitializedPool(pool);
        _;
    }

    function _ensureRegisteredPool(address pool) internal view {
        if (!_isPoolRegistered(pool)) {
            revert PoolNotRegistered(pool);
        }
    }

    /// @dev See `isPoolRegistered`
    function _isPoolRegistered(address pool) internal view returns (bool) {
        PoolConfigBits config = _poolConfigBits[pool];
        return config.isPoolRegistered();
    }

    function _ensureInitializedPool(address pool) internal view {
        if (!_isPoolInitialized(pool)) {
            revert PoolNotInitialized(pool);
        }
    }

    /// @dev See `isPoolInitialized`
    function _isPoolInitialized(address pool) internal view returns (bool) {
        PoolConfigBits config = _poolConfigBits[pool];
        return config.isPoolInitialized();
    }

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /**
     * @dev Packs and sets the raw and live balances of a Pool's tokens to the current values in poolData.balancesRaw
     * and poolData.liveBalances in the same storage slot.
     */
    function _writePoolBalancesToStorage(address pool, PoolData memory poolData) internal {
        mapping(uint256 => bytes32) storage poolBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < poolData.balancesRaw.length; ++i) {
            // Since we assume all newBalances are properly ordered
            poolBalances[i] = PackedTokenBalance.toPackedBalance(
                poolData.balancesRaw[i],
                poolData.balancesLiveScaled18[i]
            );
        }
    }

    function _loadPoolData(address pool, Rounding roundingDirection) internal view returns (PoolData memory poolData) {
        poolData.load(
            _poolTokenBalances[pool],
            _poolConfigBits[pool],
            _poolTokenInfo[pool],
            _poolTokens[pool],
            roundingDirection
        );
    }

    /**
     * @dev Fill in PoolData, including paying protocol yield fees and computing final raw and live balances.
     * This function modifies protocol fees and balance storage. Since it modifies storage and makes external
     * calls, it must be nonReentrant.
     * Side effects: updates `_aggregateFeeAmounts` and `_poolTokenBalances` in storage.
     */
    function _loadPoolDataUpdatingBalancesAndYieldFees(
        address pool,
        Rounding roundingDirection
    ) internal nonReentrant returns (PoolData memory poolData) {
        // Initialize poolData with base information for subsequent calculations.
        poolData.load(
            _poolTokenBalances[pool],
            _poolConfigBits[pool],
            _poolTokenInfo[pool],
            _poolTokens[pool],
            roundingDirection
        );

        PoolDataLib.syncPoolBalancesAndFees(poolData, _poolTokenBalances[pool], _aggregateFeeAmounts[pool]);
    }

    /**
     * @dev Updates the raw and live balance of a given token in poolData, scaling the given raw balance by both decimal
     * and token rates, and rounding the result in the given direction. Assumes scaling factors and rates are current
     * in PoolData.
     */
    function _updateRawAndLiveTokenBalancesInPoolData(
        PoolData memory poolData,
        uint256 newRawBalance,
        Rounding roundingDirection,
        uint256 tokenIndex
    ) internal pure returns (uint256) {
        poolData.balancesRaw[tokenIndex] = newRawBalance;

        function(uint256, uint256, uint256) internal pure returns (uint256) _upOrDown = roundingDirection ==
            Rounding.ROUND_UP
            ? ScalingHelpers.toScaled18ApplyRateRoundUp
            : ScalingHelpers.toScaled18ApplyRateRoundDown;

        poolData.balancesLiveScaled18[tokenIndex] = _upOrDown(
            newRawBalance,
            poolData.decimalScalingFactors[tokenIndex],
            poolData.tokenRates[tokenIndex]
        );

        return _upOrDown(newRawBalance, poolData.decimalScalingFactors[tokenIndex], poolData.tokenRates[tokenIndex]);
    }

    function _setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) internal {
        // These cannot be called during pool construction. Pools must be deployed first, then registered.
        if (swapFeePercentage < ISwapFeePercentageBounds(pool).getMinimumSwapFeePercentage()) {
            revert SwapFeePercentageTooLow();
        }

        if (swapFeePercentage > ISwapFeePercentageBounds(pool).getMaximumSwapFeePercentage()) {
            revert SwapFeePercentageTooHigh();
        }

        // The library also checks that the percentage is <= FP(1), regardless of what the pool defines.
        _poolConfigBits[pool] = _poolConfigBits[pool].setStaticSwapFeePercentage(swapFeePercentage);

        emit SwapFeePercentageChanged(pool, swapFeePercentage);
    }

    /// @dev Find the index of a token in a token array. Reverts if not found.
    function _findTokenIndex(IERC20[] memory tokens, IERC20 token) internal pure returns (uint256) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }

        revert TokenNotRegistered(token);
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /**
     * @dev Place on functions that may only be called when the associated pool is in recovery mode.
     * @param pool The pool
     */
    modifier onlyInRecoveryMode(address pool) {
        _ensurePoolInRecoveryMode(pool);
        _;
    }

    /**
     * @dev Reverts if the pool is not in recovery mode.
     * @param pool The pool
     */
    function _ensurePoolInRecoveryMode(address pool) internal view {
        if (!_isPoolInRecoveryMode(pool)) {
            revert PoolNotInRecoveryMode(pool);
        }
    }

    /**
     * @notice Checks whether a pool is in recovery mode.
     * @param pool Address of the pool to check
     * @return True if the pool is initialized, false otherwise
     */
    function _isPoolInRecoveryMode(address pool) internal view returns (bool) {
        return _poolConfigBits[pool].isPoolInRecoveryMode();
    }
}
