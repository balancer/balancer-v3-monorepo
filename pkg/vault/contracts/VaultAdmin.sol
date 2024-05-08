// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IProtocolFeeCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeCollector.sol";
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
import { ProtocolFeeCollector } from "./ProtocolFeeCollector.sol";

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

        _protocolFeeCollector = new ProtocolFeeCollector(mainVault);
    }

    /*******************************************************************************
                              Constants and immutables
    *******************************************************************************/

    function vault() external view returns (IVault) {
        return _vault;
    }

    function getProtocolFeeCollector() external view onlyVault returns (IProtocolFeeCollector) {
        return _protocolFeeCollector;
    }

    /// @inheritdoc IVaultAdmin
    function getPauseWindowEndTime() external view onlyVault returns (uint256) {
        return _vaultPauseWindowEndTime;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodDuration() external view onlyVault returns (uint256) {
        return _vaultBufferPeriodDuration;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodEndTime() external view onlyVault returns (uint256) {
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
    function pausePool(address pool) external withRegisteredPool(pool) authenticateByRole(pool) onlyVault {
        _setPoolPaused(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function unpausePool(address pool) external withRegisteredPool(pool) authenticateByRole(pool) onlyVault {
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
    ) external withRegisteredPool(pool) authenticateByRole(pool) onlyVault {
        // Saving bits by not implementing a new modifier
        _ensureUnpausedAndGetVaultState(pool);
        _setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    /**
     * @inheritdoc IVaultAdmin
     * @dev This can only be executed by the pool creator and is disabled if the pool is paused.
     * The creator fee must be <= 100%. It's the percentage of creatorAndLpFees that will be accrued by the creator
     * of the pool. For more details, check comment of vault's _computeAndChargeProtocolAndCreatorFees function
     * Emits the poolCreatorFeePercentageChanged event.
     */
    function setPoolCreatorFeePercentage(
        address pool,
        uint256 poolCreatorFeePercentage
    ) external withRegisteredPool(pool) authenticateByRole(pool) nonReentrant onlyVault {
        // Saving bits by not implementing a new modifier
        _ensureUnpausedAndGetVaultState(pool);
        _setPoolCreatorFeePercentage(pool, poolCreatorFeePercentage);
    }

    function _setPoolCreatorFeePercentage(address pool, uint256 poolCreatorFeePercentage) internal virtual {
        if (poolCreatorFeePercentage > FixedPoint.ONE) {
            revert PoolCreatorFeePercentageTooHigh();
        }

        // Force collection of any pool creator fees due, to ensure changes aren't retroactive.
        _collectProtocolFeesInternal(pool, ProtocolFeeType.SWAP);
        _collectProtocolFeesInternal(pool, ProtocolFeeType.YIELD);

        PoolConfig memory config = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        config.poolCreatorFeePercentage = poolCreatorFeePercentage;
        _poolConfig[pool] = config.fromPoolConfig();

        emit PoolCreatorFeePercentageChanged(pool, poolCreatorFeePercentage);
    }

    enum ProtocolFeeType {
        SWAP,
        YIELD
    }

    /// @inheritdoc IVaultAdmin
    function collectProtocolSwapFees(address pool) public nonReentrant onlyVault {
        _collectProtocolFeesInternal(pool, ProtocolFeeType.SWAP);
    }

    /// @inheritdoc IVaultAdmin
    function collectProtocolYieldFees(address pool) public nonReentrant onlyVault {
        _collectProtocolFeesInternal(pool, ProtocolFeeType.YIELD);
    }

    // Code is nearly identical, so factor out into this routine, parameterized by fee type.
    function _collectProtocolFeesInternal(address pool, ProtocolFeeType feeType) private {
        PoolConfig memory poolConfig = PoolConfigLib.toPoolConfig(_poolConfig[pool]);
        VaultState memory vaultState = _vaultState.toVaultState();
        IERC20[] memory poolTokens = _vault.getPoolTokens(pool);
        address poolCreator = _poolRoleAccounts[pool].poolCreator;

        bool isSwapFee = feeType == ProtocolFeeType.SWAP;
        uint256 protocolFeePercentage = isSwapFee
            ? vaultState.protocolSwapFeePercentage
            : vaultState.protocolYieldFeePercentage;
        bool needToSplitWithPoolCreator = poolCreator != address(0) && poolConfig.poolCreatorFeePercentage > 0;
        uint256 aggregateFeePercentage;

        if (needToSplitWithPoolCreator) {
            // Only need this if there is a pool creator and fees must be split
            aggregateFeePercentage = getAggregateFeePercentage(
                protocolFeePercentage,
                poolConfig.poolCreatorFeePercentage
            );
        }

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            IERC20 token = poolTokens[i];
            // Disaggregate the protocol and creator fees
            uint256 totalFees = isSwapFee ? _protocolSwapFees[pool][token] : _protocolYieldFees[pool][token];

            if (totalFees > 0) {
                uint256 protocolPortion;

                // Clear protocol fee balance.
                if (isSwapFee) {
                    _protocolSwapFees[pool][token] = 0;
                } else {
                    _protocolYieldFees[pool][token] = 0;
                }

                if (needToSplitWithPoolCreator) {
                    uint256 totalVolume = totalFees.divUp(aggregateFeePercentage);
                    protocolPortion = totalVolume.mulUp(protocolFeePercentage);
                    uint256 poolCreatorPortion = totalFees - protocolPortion;

                    token.safeTransfer(poolCreator, poolCreatorPortion);
                    if (isSwapFee) {
                        emit PoolCreatorSwapFeeCollected(pool, token, poolCreatorPortion);
                    } else {
                        emit PoolCreatorYieldFeeCollected(pool, token, poolCreatorPortion);
                    }
                } else {
                    protocolPortion = totalFees;
                }

                token.safeTransfer(address(_protocolFeeCollector), protocolPortion);
                if (isSwapFee) {
                    emit ProtocolSwapFeeCollected(pool, token, protocolPortion);
                } else {
                    emit ProtocolYieldFeeCollected(pool, token, protocolPortion);
                }
            }
        }
    }

    /// @inheritdoc IVaultAdmin
    function getAggregateFeePercentage(
        uint256 protocolPercentage,
        uint256 creatorPercentage
    ) public view onlyVault returns (uint256) {
        return protocolPercentage + protocolPercentage.complement().mulDown(creatorPercentage);
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

    function _canPerform(bytes32 actionId, address user, address where) internal view returns (bool) {
        return _authorizer.canPerform(actionId, user, where);
    }
}
