// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { PoolFunctionPermission, Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { VaultExtensionsLib } from "./lib/VaultExtensionsLib.sol";
import { PoolConfigLib, PoolConfigBits } from "./lib/PoolConfigLib.sol";
import { VaultCommon } from "./VaultCommon.sol";

/**
 * @dev Bytecode extension for the Vault containing permissioned functions. Complementary to `VaultExtension`,
 * it has access to the same storage layout as the main vault.
 *
 * The functions in this contract are not meant to be called directly. They must only be called by the Vault
 * via delegate calls, so that any state modifications produced by this contract's code will actually target
 * the main Vault's state.
 *
 * The storage of this contract is in practice unused.
 */
contract VaultAdmin is IVaultAdmin, VaultCommon, Authentication {
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfigBits;
    using VaultStateLib for VaultStateBits;
    using VaultExtensionsLib for IVault;
    using SafeERC20 for IERC20;

    IVault private immutable _vault;

    /// @dev Functions with this modifier can only be delegate-called by the vault.
    modifier onlyVaultDelegateCall() {
        _vault.ensureVaultDelegateCall();
        _;
    }

    /// @dev Functions with this modifier can only be called by the pool creator.
    modifier onlyProtocolFeeController() {
        if (msg.sender != address(_protocolFeeController)) {
            revert SenderNotAllowed();
        }
        _;
    }

    /// @dev Validate aggregate percentage values.
    modifier withValidPercentage(uint256 aggregatePercentage) {
        if (aggregatePercentage > FixedPoint.ONE) {
            revert ProtocolFeesExceedTotalCollected();
        }
        _;
    }

    /// @dev Use with permissioned functions that use `PoolRoleAccounts`.
    modifier authenticateByRole(address pool) {
        _ensureAuthenticatedByRole(pool);
        _;
    }

    function _ensureAuthenticatedByRole(address pool) private view {
        bytes32 actionId = getActionId(msg.sig);

        PoolFunctionPermission memory roleAssignment = _poolFunctionPermissions[pool][actionId];

        // If there is no role assignment, fall through and delegate to governance.
        if (roleAssignment.account != address(0)) {
            // If the sender matches the permissioned account, all good; just return.
            if (msg.sender == roleAssignment.account) {
                return;
            }

            // If it doesn't, check whether it's onlyOwner. onlyOwner means *only* the permissioned account
            // may call the function, so revert if this is the case. Otherwise, fall through and check
            // governance.
            if (roleAssignment.onlyOwner) {
                revert SenderNotAllowed();
            }
        }

        // Delegate to governance.
        if (_canPerform(actionId, msg.sender, pool) == false) {
            revert SenderNotAllowed();
        }
    }

    constructor(
        IVault mainVault,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration
    ) Authentication(bytes32(uint256(uint160(address(mainVault))))) {
        if (pauseWindowDuration > _MAX_PAUSE_WINDOW_DURATION) {
            revert VaultPauseWindowDurationTooLarge();
        }
        if (bufferPeriodDuration > _MAX_BUFFER_PERIOD_DURATION) {
            revert PauseBufferPeriodDurationTooLarge();
        }

        // solhint-disable-next-line not-rely-on-time
        uint32 pauseWindowEndTime = uint32(block.timestamp) + pauseWindowDuration;

        _vaultPauseWindowEndTime = pauseWindowEndTime;
        _vaultBufferPeriodDuration = bufferPeriodDuration;
        _vaultBufferPeriodEndTime = pauseWindowEndTime + bufferPeriodDuration;

        _vault = mainVault;
    }

    /*******************************************************************************
                               Constants and immutables
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function vault() external view returns (IVault) {
        return _vault;
    }

    /// @inheritdoc IVaultAdmin
    function getPauseWindowEndTime() external view returns (uint32) {
        return _vaultPauseWindowEndTime;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodDuration() external view returns (uint32) {
        return _vaultBufferPeriodDuration;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodEndTime() external view returns (uint32) {
        return _vaultBufferPeriodEndTime;
    }

    /// @inheritdoc IVaultAdmin
    function getMinimumPoolTokens() external pure returns (uint256) {
        return _MIN_TOKENS;
    }

    /// @inheritdoc IVaultAdmin
    function getMaximumPoolTokens() external pure returns (uint256) {
        return _MAX_TOKENS;
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function isVaultPaused() external view onlyVaultDelegateCall returns (bool) {
        return _isVaultPaused();
    }

    /// @inheritdoc IVaultAdmin
    function getVaultPausedState() external view onlyVaultDelegateCall returns (bool, uint32, uint32) {
        return (_isVaultPaused(), _vaultPauseWindowEndTime, _vaultBufferPeriodEndTime);
    }

    /// @inheritdoc IVaultAdmin
    function pauseVault() external onlyVaultDelegateCall authenticate {
        _setVaultPaused(true);
    }

    /// @inheritdoc IVaultAdmin
    function unpauseVault() external onlyVaultDelegateCall authenticate {
        _setVaultPaused(false);
    }

    /**
     * @dev The contract can only be paused until the end of the Pause Window, and
     * unpaused until the end of the Buffer Period.
     */
    function _setVaultPaused(bool pausing) internal {
        if (_isVaultPaused()) {
            if (pausing) {
                // Already paused, and we're trying to pause it again.
                revert VaultPaused();
            }

            // The Vault can always be unpaused while it's paused.
            // When the buffer period expires, `_isVaultPaused` will return false, so we would be in the outside
            // else clause, where trying to unpause will revert unconditionally.
        } else {
            if (pausing) {
                // Not already paused; we can pause within the window.
                // solhint-disable-next-line not-rely-on-time
                if (block.timestamp >= _vaultPauseWindowEndTime) {
                    revert VaultPauseWindowExpired();
                }
            } else {
                // Not paused, and we're trying to unpause it.
                revert VaultNotPaused();
            }
        }

        VaultStateBits vaultState = _vaultStateBits;
        vaultState = vaultState.setVaultPaused(pausing);
        _vaultStateBits = vaultState;

        emit VaultPausedStateChanged(pausing);
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function pausePool(address pool) external onlyVaultDelegateCall withRegisteredPool(pool) authenticateByRole(pool) {
        _setPoolPaused(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function unpausePool(
        address pool
    ) external onlyVaultDelegateCall withRegisteredPool(pool) authenticateByRole(pool) {
        _setPoolPaused(pool, false);
    }

    function _setPoolPaused(address pool, bool pausing) internal {
        PoolConfigBits config = _poolConfigBits[pool];

        if (_isPoolPaused(pool)) {
            if (pausing) {
                // Already paused, and we're trying to pause it again.
                revert PoolPaused(pool);
            }

            // The pool can always be unpaused while it's paused.
            // When the buffer period expires, `_isPoolPaused` will return false, so we would be in the outside
            // else clause, where trying to unpause will revert unconditionally.
        } else {
            if (pausing) {
                // Not already paused; we can pause within the window.
                // solhint-disable-next-line not-rely-on-time
                if (block.timestamp >= config.getPauseWindowEndTime()) {
                    revert PoolPauseWindowExpired(pool);
                }
            } else {
                // Not paused, and we're trying to unpause it.
                revert PoolNotPaused(pool);
            }
        }

        // Update poolConfigBits.
        _poolConfigBits[pool] = config.setPoolPaused(pausing);

        emit PoolPausedStateChanged(pool, pausing);
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function setStaticSwapFeePercentage(
        address pool,
        uint256 swapFeePercentage
    ) external onlyVaultDelegateCall withRegisteredPool(pool) authenticateByRole(pool) {
        // Saving bits by not implementing a new modifier.
        _ensureUnpaused(pool);
        _setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function collectAggregateFees(address pool) public onlyVaultDelegateCall nonReentrant withRegisteredPool(pool) {
        IERC20[] memory poolTokens = _vault.getPoolTokens(pool);
        address feeController = address(_protocolFeeController);
        uint256 numTokens = poolTokens.length;

        uint256[] memory totalSwapFees = new uint256[](numTokens);
        uint256[] memory totalYieldFees = new uint256[](numTokens);

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            IERC20 token = poolTokens[i];

            (totalSwapFees[i], totalYieldFees[i]) = _aggregateFeeAmounts[pool][token].fromPackedBalance();

            if (totalSwapFees[i] > 0 || totalYieldFees[i] > 0) {
                // The ProtocolFeeController will pull tokens from the Vault.
                token.forceApprove(feeController, totalSwapFees[i] + totalYieldFees[i]);

                _aggregateFeeAmounts[pool][token] = 0;
            }
        }

        _protocolFeeController.receiveAggregateFees(pool, totalSwapFees, totalYieldFees);
    }

    /// @inheritdoc IVaultAdmin
    function updateAggregateSwapFeePercentage(
        address pool,
        uint256 newAggregateSwapFeePercentage
    )
        external
        onlyVaultDelegateCall
        withRegisteredPool(pool)
        withValidPercentage(newAggregateSwapFeePercentage)
        onlyProtocolFeeController
    {
        _poolConfigBits[pool] = _poolConfigBits[pool].setAggregateSwapFeePercentage(newAggregateSwapFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function updateAggregateYieldFeePercentage(
        address pool,
        uint256 newAggregateYieldFeePercentage
    )
        external
        onlyVaultDelegateCall
        withRegisteredPool(pool)
        withValidPercentage(newAggregateYieldFeePercentage)
        onlyProtocolFeeController
    {
        _poolConfigBits[pool] = _poolConfigBits[pool].setAggregateYieldFeePercentage(newAggregateYieldFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function setProtocolFeeController(
        IProtocolFeeController newProtocolFeeController
    ) external onlyVaultDelegateCall authenticate nonReentrant {
        _protocolFeeController = newProtocolFeeController;

        emit ProtocolFeeControllerChanged(newProtocolFeeController);
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function enableRecoveryMode(address pool) external onlyVaultDelegateCall withRegisteredPool(pool) {
        _ensurePoolNotInRecoveryMode(pool);

        // If the Vault or pool is pausable (and currently paused), this call is permissionless.
        if (_isPoolPaused(pool) == false && _isVaultPaused() == false) {
            // If not permissionless, authenticate with governance.
            _authenticateCaller();
        }

        _setPoolRecoveryMode(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function disableRecoveryMode(address pool) external onlyVaultDelegateCall withRegisteredPool(pool) authenticate {
        _ensurePoolInRecoveryMode(pool);
        _setPoolRecoveryMode(pool, false);
    }

    /**
     * @dev Reverts if the pool is in recovery mode.
     * @param pool The pool
     */
    function _ensurePoolNotInRecoveryMode(address pool) internal view {
        if (_isPoolInRecoveryMode(pool)) {
            revert PoolInRecoveryMode(pool);
        }
    }

    /**
     * @dev Change the recovery mode state of a pool, and emit an event. Assumes any validation (e.g., whether
     * the proposed state change is consistent) has already been done.
     *
     * @param pool The pool
     * @param recoveryMode The desired recovery mode state
     */
    function _setPoolRecoveryMode(address pool, bool recoveryMode) internal {
        // Update poolConfigBits
        _poolConfigBits[pool] = _poolConfigBits[pool].setPoolInRecoveryMode(recoveryMode);

        if (recoveryMode == false) {
            _writePoolBalancesToStorage(pool, _loadPoolData(pool, Rounding.ROUND_DOWN));
        }

        emit PoolRecoveryModeStateChanged(pool, recoveryMode);
    }

    /*******************************************************************************
                                        Queries
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function disableQuery() external onlyVaultDelegateCall authenticate {
        VaultStateBits vaultState = _vaultStateBits;
        vaultState = vaultState.setQueryDisabled(true);
        _vaultStateBits = vaultState;
    }

    /*******************************************************************************
                                Yield-bearing token buffers
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function pauseVaultBuffers() external onlyVaultDelegateCall authenticate {
        VaultStateBits vaultState = _vaultStateBits;
        vaultState = vaultState.setBuffersPaused(true);
        _vaultStateBits = vaultState;
    }

    /// @inheritdoc IVaultAdmin
    function unpauseVaultBuffers() external onlyVaultDelegateCall authenticate {
        VaultStateBits vaultState = _vaultStateBits;
        vaultState = vaultState.setBuffersPaused(false);
        _vaultStateBits = vaultState;
    }

    /// @inheritdoc IVaultAdmin
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
        address sharesOwner
    )
        public
        onlyVaultDelegateCall
        onlyWhenUnlocked
        whenVaultBuffersAreNotPaused
        nonReentrant
        returns (uint256 issuedShares)
    {
        address underlyingToken = wrappedToken.asset();

        // Amount of shares to issue is the total underlying token that the user is depositing.
        issuedShares = wrappedToken.convertToAssets(amountWrapped) + amountUnderlying;

        if (_bufferAssets[wrappedToken] == address(0)) {
            // Buffer is not initialized yet, so we initialize it.

            // Register asset of wrapper, so it cannot change.
            _bufferAssets[wrappedToken] = underlyingToken;

            // Burn MINIMUM_TOTAL_SUPPLY shares, so the buffer can never go back to zero liquidity
            // (avoids rounding issues with low liquidity).
            _bufferTotalShares[wrappedToken] = _MINIMUM_TOTAL_SUPPLY;
            issuedShares -= _MINIMUM_TOTAL_SUPPLY;
        } else if (_bufferAssets[wrappedToken] != underlyingToken) {
            // Asset was changed since the first bufferAddLiquidity call.
            revert WrongWrappedTokenAsset(address(wrappedToken));
        }

        bytes32 bufferBalances = _bufferTokenBalances[wrappedToken];

        // Adds the issued shares to the total shares of the liquidity pool.
        _bufferLpShares[wrappedToken][sharesOwner] += issuedShares;
        _bufferTotalShares[wrappedToken] += issuedShares;

        bufferBalances = PackedTokenBalance.toPackedBalance(
            bufferBalances.getBalanceRaw() + amountUnderlying,
            bufferBalances.getBalanceDerived() + amountWrapped
        );

        _bufferTokenBalances[wrappedToken] = bufferBalances;

        _takeDebt(IERC20(underlyingToken), amountUnderlying);
        _takeDebt(wrappedToken, amountWrapped);

        emit LiquidityAddedToBuffer(wrappedToken, sharesOwner, amountWrapped, amountUnderlying, issuedShares);
    }

    /// @inheritdoc IVaultAdmin
    function removeLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    )
        public
        onlyVaultDelegateCall
        onlyWhenUnlocked
        authenticate
        nonReentrant
        returns (uint256 removedUnderlyingBalance, uint256 removedWrappedBalance)
    {
        bytes32 bufferBalances = _bufferTokenBalances[wrappedToken];

        if (sharesToRemove > _bufferLpShares[wrappedToken][sharesOwner]) {
            revert NotEnoughBufferShares();
        }
        uint256 totalShares = _bufferTotalShares[wrappedToken];

        removedUnderlyingBalance = (bufferBalances.getBalanceRaw() * sharesToRemove) / totalShares;
        removedWrappedBalance = (bufferBalances.getBalanceDerived() * sharesToRemove) / totalShares;

        _bufferLpShares[wrappedToken][sharesOwner] -= sharesToRemove;
        _bufferTotalShares[wrappedToken] -= sharesToRemove;

        bufferBalances = PackedTokenBalance.toPackedBalance(
            bufferBalances.getBalanceRaw() - removedUnderlyingBalance,
            bufferBalances.getBalanceDerived() - removedWrappedBalance
        );

        _bufferTokenBalances[wrappedToken] = bufferBalances;

        _supplyCredit(IERC20(_bufferAssets[wrappedToken]), removedUnderlyingBalance);
        _supplyCredit(wrappedToken, removedWrappedBalance);

        emit LiquidityRemovedFromBuffer(
            wrappedToken,
            sharesOwner,
            removedWrappedBalance,
            removedUnderlyingBalance,
            sharesToRemove
        );
    }

    /// @inheritdoc IVaultAdmin
    function getBufferOwnerShares(
        IERC4626 token,
        address user
    ) external view onlyVaultDelegateCall returns (uint256 shares) {
        return _bufferLpShares[token][user];
    }

    /// @inheritdoc IVaultAdmin
    function getBufferTotalShares(IERC4626 token) external view onlyVaultDelegateCall returns (uint256 shares) {
        return _bufferTotalShares[token];
    }

    /// @inheritdoc IVaultAdmin
    function getBufferBalance(IERC4626 token) external view onlyVaultDelegateCall returns (uint256, uint256) {
        // The first balance is underlying, and the last is wrapped balance.
        return (_bufferTokenBalances[token].getBalanceRaw(), _bufferTokenBalances[token].getBalanceDerived());
    }

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function setAuthorizer(IAuthorizer newAuthorizer) external onlyVaultDelegateCall authenticate {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @dev Access control is delegated to the Authorizer.
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }

    /// @dev Access control is delegated to the Authorizer. `where` refers to the target contract.
    function _canPerform(bytes32 actionId, address user, address where) internal view returns (bool) {
        return _authorizer.canPerform(actionId, user, where);
    }
}
