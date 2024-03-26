// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { VaultExtensionsLib } from "./lib/VaultExtensionsLib.sol";
import { PoolConfigLib } from "./lib/PoolConfigLib.sol";
import { VaultCommon } from "./VaultCommon.sol";

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
    using PoolConfigLib for PoolConfig;
    using VaultExtensionsLib for IVault;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
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
        if (pauseWindowDuration > MAX_PAUSE_WINDOW_DURATION) {
            revert VaultPauseWindowDurationTooLarge();
        }
        if (bufferPeriodDuration > MAX_BUFFER_PERIOD_DURATION) {
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
        return _getPoolData(pool).tokenRates;
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
    function pauseVault() external authenticate onlyVault {
        _setVaultPaused(true);
    }

    /// @inheritdoc IVaultAdmin
    function unpauseVault() external authenticate onlyVault {
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

    modifier onlyAuthenticatedPauser(address pool) {
        _ensureAuthenticatedPauser(pool);
        _;
    }

    function _ensureAuthenticatedPauser(address pool) private view {
        address pauseManager = _poolPauseManagers[pool];

        if (pauseManager == address(0)) {
            // If there is no pause manager, default to the authorizer.
            _authenticateCaller();
        } else {
            // Sender must be the pause manager.
            if (msg.sender != pauseManager) {
                revert SenderIsNotPauseManager(pool);
            }
        }
    }

    /// @inheritdoc IVaultAdmin
    function pausePool(address pool) external withRegisteredPool(pool) onlyAuthenticatedPauser(pool) onlyVault {
        _setPoolPaused(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function unpausePool(address pool) external withRegisteredPool(pool) onlyAuthenticatedPauser(pool) onlyVault {
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

    /// @inheritdoc IVaultAdmin
    function setProtocolSwapFeePercentage(uint256 newProtocolSwapFeePercentage) external authenticate onlyVault {
        if (newProtocolSwapFeePercentage > _MAX_PROTOCOL_SWAP_FEE_PERCENTAGE) {
            revert ProtocolSwapFeePercentageTooHigh();
        }
        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.protocolSwapFeePercentage = newProtocolSwapFeePercentage;
        _vaultState = VaultStateLib.fromVaultState(vaultState);
        emit ProtocolSwapFeePercentageChanged(newProtocolSwapFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function setProtocolYieldFeePercentage(uint256 newProtocolYieldFeePercentage) external authenticate onlyVault {
        if (newProtocolYieldFeePercentage > _MAX_PROTOCOL_YIELD_FEE_PERCENTAGE) {
            revert ProtocolYieldFeePercentageTooHigh();
        }
        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.protocolYieldFeePercentage = newProtocolYieldFeePercentage;
        _vaultState = VaultStateLib.fromVaultState(vaultState);
        emit ProtocolYieldFeePercentageChanged(newProtocolYieldFeePercentage);
    }

    /**
     * @inheritdoc IVaultAdmin
     * @dev This is a permissioned function, disabled if the pool is paused. The swap fee must be <=
     * MAX_SWAP_FEE_PERCENTAGE. Emits the SwapFeePercentageChanged event.
     */
    function setStaticSwapFeePercentage(
        address pool,
        uint256 swapFeePercentage
    ) external authenticate withRegisteredPool(pool) onlyVault {
        // Saving bits by not implementing a new modifier
        _ensureUnpausedAndGetVaultState(pool);
        _setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    function _setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) internal virtual {
        if (swapFeePercentage > _MAX_SWAP_FEE_PERCENTAGE) {
            revert SwapFeePercentageTooHigh();
        }

        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        config.staticSwapFeePercentage = swapFeePercentage;
        _poolConfig[pool] = config.fromPoolConfig();

        emit SwapFeePercentageChanged(pool, swapFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function collectProtocolFees(IERC20[] calldata tokens) external authenticate nonReentrant onlyVault {
        for (uint256 index = 0; index < tokens.length; index++) {
            IERC20 token = tokens[index];
            uint256 amount = _protocolFees[token];

            if (amount > 0) {
                // set fees to zero for the token
                _protocolFees[token] = 0;

                token.safeTransfer(msg.sender, amount);
                emit ProtocolFeeCollected(token, amount);
            }
        }
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function enableRecoveryMode(address pool) external withRegisteredPool(pool) onlyVault {
        _ensurePoolNotInRecoveryMode(pool);

        // If the Vault or pool is pausable (and currently paused), this call is permissionless.
        if (_isPoolPaused(pool) == false && _isVaultPaused() == false) {
            // If not permissionless, authenticate with governance.
            _authenticateCaller();
        }

        _setPoolRecoveryMode(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function disableRecoveryMode(address pool) external withRegisteredPool(pool) authenticate onlyVault {
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
            _setPoolBalances(pool, _getPoolData(pool));
        }

        emit PoolRecoveryModeStateChanged(pool, recoveryMode);
    }

    /// @dev Factored out as it is reused.
    function _getPoolData(address pool) internal view returns (PoolData memory poolData) {
        (
            poolData.tokenConfig,
            poolData.balancesRaw,
            poolData.decimalScalingFactors,
            poolData.poolConfig
        ) = _getPoolTokenInfo(pool);

        _updateTokenRatesInPoolData(poolData);
    }

    /*******************************************************************************
                                        Queries
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function disableQuery() external authenticate onlyVault {
        VaultState memory vaultState = _vaultState.toVaultState();
        vaultState.isQueryDisabled = true;
        _vaultState = VaultStateLib.fromVaultState(vaultState);
    }

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function setAuthorizer(IAuthorizer newAuthorizer) external nonReentrant authenticate onlyVault {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @dev Access control is delegated to the Authorizer
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }
}
