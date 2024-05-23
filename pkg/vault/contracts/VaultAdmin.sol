// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import {
    IProtocolFeeCollector,
    ProtocolFeeType
} from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { VaultExtensionsLib } from "./lib/VaultExtensionsLib.sol";
import { PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultCommon } from "./VaultCommon.sol";
import { PackedTokenBalance } from "./lib/PackedTokenBalance.sol";

/**
 * @dev Bytecode extension for the Vault containing permissioned functions. Complementary to the `VaultExtension`.
 * Has access to the same storage layout as the main vault.
 *
 * The functions in this contract are not meant to be called directly ever. They should just be called by the Vault
 * via delegate calls instead, and any state modification produced by this contract's code will actually target
 * the main Vault's state.
 *
 * The storage of this contract is in practice unused.
 */
contract VaultAdmin is IVaultAdmin, VaultCommon, Authentication {
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfig;
    using VaultExtensionsLib for IVault;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;
    using VaultStateLib for VaultStateBits;

    IVault private immutable _vault;

    /// @dev Functions with this modifier can only be delegate-called by the vault.
    modifier onlyVault() {
        _vault.ensureVaultDelegateCall();
        _;
    }

    constructor(
        IVault mainVault,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Authentication(bytes32(uint256(uint160(address(mainVault))))) {
        if (pauseWindowDuration > _MAX_PAUSE_WINDOW_DURATION) {
            revert VaultPauseWindowDurationTooLarge();
        }
        if (bufferPeriodDuration > _MAX_BUFFER_PERIOD_DURATION) {
            revert PauseBufferPeriodDurationTooLarge();
        }

        // solhint-disable-next-line not-rely-on-time
        uint256 pauseWindowEndTime = block.timestamp + pauseWindowDuration;

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
    function getPauseWindowEndTime() external view returns (uint256) {
        return _vaultPauseWindowEndTime;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodDuration() external view returns (uint256) {
        return _vaultBufferPeriodDuration;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodEndTime() external view returns (uint256) {
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
                                    Pool Information
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function getPoolTokenRates(
        address pool
    ) external view withRegisteredPool(pool) onlyVault returns (uint256[] memory) {
        return _loadPoolData(pool, Rounding.ROUND_DOWN).tokenRates;
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function isVaultPaused() external view onlyVault returns (bool) {
        return _isVaultPaused();
    }

    /// @inheritdoc IVaultAdmin
    function getVaultPausedState() external view onlyVault returns (bool, uint256, uint256) {
        return (_isVaultPaused(), _vaultPauseWindowEndTime, _vaultBufferPeriodEndTime);
    }

    /// @inheritdoc IVaultAdmin
    function pauseVault() external onlyVault authenticate {
        _setVaultPaused(true);
    }

    /// @inheritdoc IVaultAdmin
    function unpauseVault() external onlyVault authenticate {
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

        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.isVaultPaused = pausing;
        _vaultState = VaultStateLib.fromVaultState(vaultState);

        emit VaultPausedStateChanged(pausing);
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    modifier authenticateByRole(address pool) {
        _ensureAuthenticatedByRole(pool);
        _;
    }

    function _ensureAuthenticatedByRole(address pool) private view {
        bytes32 actionId = getActionId(msg.sig);

        PoolFunctionPermission memory roleAssignment = _poolFunctionPermissions[pool][actionId];

        // If there is no role assigment, fall through and delegate to governance.
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

    /// @inheritdoc IVaultAdmin
    function pausePool(address pool) external onlyVault withRegisteredPool(pool) authenticateByRole(pool) {
        _setPoolPaused(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function unpausePool(address pool) external onlyVault withRegisteredPool(pool) authenticateByRole(pool) {
        _setPoolPaused(pool, false);
    }

    function _setPoolPaused(address pool, bool pausing) internal {
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);

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
                if (block.timestamp >= config.pauseWindowEndTime) {
                    revert PoolPauseWindowExpired(pool);
                }
            } else {
                // Not paused, and we're trying to unpause it.
                revert PoolNotPaused(pool);
            }
        }

        // Update poolConfig.
        config.isPoolPaused = pausing;
        _poolConfig[pool] = config.fromPoolConfig();

        emit PoolPausedStateChanged(pool, pausing);
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /**
     * @inheritdoc IVaultAdmin
     * @dev This is a permissioned function, disabled if the pool is paused. The swap fee must be <=
     * MAX_SWAP_FEE_PERCENTAGE. Emits the SwapFeePercentageChanged event.
     */
    function setStaticSwapFeePercentage(
        address pool,
        uint256 swapFeePercentage
    ) external onlyVault withRegisteredPool(pool) authenticateByRole(pool) {
        // Saving bits by not implementing a new modifier
        _ensureUnpausedAndGetVaultState(pool);
        _setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function collectProtocolFees(address pool) external onlyVault nonReentrant {
        _collectProtocolFeesInternal(pool, ProtocolFeeType.SWAP);
        _collectProtocolFeesInternal(pool, ProtocolFeeType.YIELD);
    }

    function _collectProtocolFeesInternal(address pool, ProtocolFeeType feeType) private {
        IERC20[] memory poolTokens = _vault.getPoolTokens(pool);
        bool isSwapFee = feeType == ProtocolFeeType.SWAP;

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            IERC20 token = poolTokens[i];

            uint256 totalFees = isSwapFee ? _protocolSwapFees[pool][token] : _protocolYieldFees[pool][token];
            if (totalFees > 0) {
                // The ProtocolFeeCollector will pull tokens from the Vault.
                token.approve(address(_protocolFeeCollector), totalFees);

                if (isSwapFee) {
                    _protocolSwapFees[pool][token] = 0;
                    _protocolFeeCollector.receiveProtocolSwapFees(pool, token, totalFees);
                } else {
                    _protocolYieldFees[pool][token] = 0;
                    _protocolFeeCollector.receiveProtocolYieldFees(pool, token, totalFees);
                }
            }
        }
    }

    /// @inheritdoc IVaultAdmin
    function updateAggregateFeePercentage(
        address pool,
        ProtocolFeeType feeType,
        uint256 newAggregateFeePercentage
    ) external {
        if (msg.sender != address(_protocolFeeCollector)) {
            revert SenderNotAllowed();
        }

        PoolConfig memory config = _poolConfig[pool].toPoolConfig();
        if (feeType == ProtocolFeeType.SWAP) {
            config.aggregateProtocolSwapFeePercentage = newAggregateFeePercentage;
        } else {
            config.aggregateProtocolYieldFeePercentage = newAggregateFeePercentage;
        }
        _poolConfig[pool] = config.fromPoolConfig();
    }

    /// @inheritdoc IVaultAdmin
    function setProtocolFeeCollector(
        IProtocolFeeCollector newProtocolFeeCollector
    ) external onlyVault nonReentrant authenticate {
        _protocolFeeCollector = newProtocolFeeCollector;

        emit ProtocolFeeCollectorChanged(newProtocolFeeCollector);
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function enableRecoveryMode(address pool) external onlyVault withRegisteredPool(pool) {
        _ensurePoolNotInRecoveryMode(pool);

        // If the Vault or pool is pausable (and currently paused), this call is permissionless.
        if (_isPoolPaused(pool) == false && _isVaultPaused() == false) {
            // If not permissionless, authenticate with governance.
            _authenticateCaller();
        }

        _setPoolRecoveryMode(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function disableRecoveryMode(address pool) external onlyVault withRegisteredPool(pool) authenticate {
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
        // Update poolConfig
        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        config.isPoolInRecoveryMode = recoveryMode;
        _poolConfig[pool] = config.fromPoolConfig();

        if (recoveryMode == false) {
            _writePoolBalancesToStorage(pool, _loadPoolData(pool, Rounding.ROUND_DOWN));
        }

        emit PoolRecoveryModeStateChanged(pool, recoveryMode);
    }

    /*******************************************************************************
                                        Queries
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function disableQuery() external onlyVault authenticate {
        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.isQueryDisabled = true;
        _vaultState = VaultStateLib.fromVaultState(vaultState);
    }

    /*******************************************************************************
                                Yield-bearing token buffers
    *******************************************************************************/
    /// @inheritdoc IVaultAdmin
    function unpauseVaultBuffers() external onlyVault authenticate {
        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.areBuffersPaused = false;
        _vaultState = VaultStateLib.fromVaultState(vaultState);
    }

    /// @inheritdoc IVaultAdmin
    function pauseVaultBuffers() external onlyVault authenticate {
        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.areBuffersPaused = true;
        _vaultState = VaultStateLib.fromVaultState(vaultState);
    }

    /// @inheritdoc IVaultAdmin
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
        address sharesOwner
    ) public onlyWhenUnlocked whenVaultBuffersAreNotPaused nonReentrant returns (uint256 issuedShares) {
        address underlyingToken = wrappedToken.asset();

        // amount of shares to issue is the total underlying token that the user is depositing
        issuedShares = wrappedToken.convertToAssets(amountWrapped) + amountUnderlying;

        if (_bufferAssets[IERC20(address(wrappedToken))] == address(0)) {
            // Buffer is not initialized yet, so we initialize it

            // Register asset of wrapper, so it cannot change
            _bufferAssets[IERC20(address(wrappedToken))] = underlyingToken;

            // Burn MINIMUM_TOTAL_SUPPLY shares, so the buffer can never go back to liquidity 0
            // (avoids rounding issues with low liquidity)
            _bufferTotalShares[IERC20(wrappedToken)] = _MINIMUM_TOTAL_SUPPLY;
            issuedShares -= _MINIMUM_TOTAL_SUPPLY;
        } else if (_bufferAssets[IERC20(address(wrappedToken))] != underlyingToken) {
            // Asset was changed since the first bufferAddLiquidity call
            revert WrongWrappedTokenAsset(address(wrappedToken));
        }

        bytes32 bufferBalances = _bufferTokenBalances[IERC20(wrappedToken)];

        // Adds the issued shares to the total shares of the liquidity pool
        _bufferLpShares[IERC20(wrappedToken)][sharesOwner] += issuedShares;
        _bufferTotalShares[IERC20(wrappedToken)] += issuedShares;

        bufferBalances = PackedTokenBalance.toPackedBalance(
            bufferBalances.getBalanceRaw() + amountUnderlying,
            bufferBalances.getBalanceDerived() + amountWrapped
        );

        _bufferTokenBalances[IERC20(wrappedToken)] = bufferBalances;

        _takeDebt(IERC20(underlyingToken), amountUnderlying);
        _takeDebt(wrappedToken, amountWrapped);
    }

    /// @inheritdoc IVaultAdmin
    function removeLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    )
        public
        onlyWhenUnlocked
        nonReentrant
        authenticate
        returns (uint256 removedUnderlyingBalance, uint256 removedWrappedBalance)
    {
        bytes32 bufferBalances = _bufferTokenBalances[IERC20(wrappedToken)];

        if (sharesToRemove > _bufferLpShares[IERC20(wrappedToken)][sharesOwner]) {
            revert NotEnoughBufferShares();
        }
        uint256 totalShares = _bufferTotalShares[IERC20(wrappedToken)];

        removedUnderlyingBalance = (bufferBalances.getBalanceRaw() * sharesToRemove) / totalShares;
        removedWrappedBalance = (bufferBalances.getBalanceDerived() * sharesToRemove) / totalShares;

        _bufferLpShares[IERC20(wrappedToken)][sharesOwner] -= sharesToRemove;
        _bufferTotalShares[IERC20(wrappedToken)] -= sharesToRemove;

        bufferBalances = PackedTokenBalance.toPackedBalance(
            bufferBalances.getBalanceRaw() - removedUnderlyingBalance,
            bufferBalances.getBalanceDerived() - removedWrappedBalance
        );

        _bufferTokenBalances[IERC20(wrappedToken)] = bufferBalances;

        _supplyCredit(IERC20(_bufferAssets[IERC20(address(wrappedToken))]), removedUnderlyingBalance);
        _supplyCredit(wrappedToken, removedWrappedBalance);
    }

    /// @inheritdoc IVaultAdmin
    function getBufferOwnerShares(IERC20 token, address user) external view returns (uint256 shares) {
        return _bufferLpShares[token][user];
    }

    /// @inheritdoc IVaultAdmin
    function getBufferTotalShares(IERC20 token) external view returns (uint256 shares) {
        return _bufferTotalShares[token];
    }

    /// @inheritdoc IVaultAdmin
    function getBufferBalance(IERC20 token) external view returns (uint256, uint256) {
        return (_bufferTokenBalances[token].getBalanceRaw(), _bufferTokenBalances[token].getBalanceDerived());
    }

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function setAuthorizer(IAuthorizer newAuthorizer) external onlyVault nonReentrant authenticate {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @dev Access control is delegated to the Authorizer
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }

    function _canPerform(bytes32 actionId, address user, address where) internal view returns (bool) {
        return _authorizer.canPerform(actionId, user, where);
    }
}
