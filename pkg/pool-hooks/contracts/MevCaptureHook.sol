// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    IBalancerContractRegistry
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IMevCaptureHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevCaptureHook.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    HooksConfig,
    HookFlags,
    LiquidityManagement,
    PoolSwapParams,
    RemoveLiquidityKind,
    TokenConfig,
    MAX_FEE_PERCENTAGE
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

contract MevCaptureHook is BaseHooks, SingletonAuthentication, VaultGuard, IMevCaptureHook {
    using FixedPoint for uint256;

    // Max Fee is 99.9999% (Max supported fee by the vault).
    uint256 private constant _MEV_MAX_FEE_PERCENTAGE = MAX_FEE_PERCENTAGE;

    IBalancerContractRegistry internal immutable _registry;

    bool internal _mevCaptureEnabled;

    // Global default parameter values.
    uint256 internal _defaultMevCaptureThreshold;
    uint256 internal _defaultMevCaptureMultiplier;

    // Global max dynamic swap fee percentage returned by this hook.
    uint256 internal _maxMevSwapFeePercentage;

    // Global list of senders that bypass MEV capture, and always pay the static fee percentage.
    mapping(address => bool) internal _isMevCaptureExemptSender;

    // Pool-specific parameters.
    mapping(address => uint256) internal _poolMevCaptureThresholds;
    mapping(address => uint256) internal _poolMevCaptureMultipliers;

    modifier withMevCaptureEnabledPool(address pool) {
        HooksConfig memory hooksConfig = _vault.getHooksConfig(pool);

        if (hooksConfig.hooksContract != address(this)) {
            revert MevCaptureHookNotRegisteredInPool(pool);
        }

        _;
    }

    constructor(IVault vault, IBalancerContractRegistry registry) SingletonAuthentication(vault) VaultGuard(vault) {
        _registry = registry;

        _setMevCaptureEnabled(false);
        _setDefaultMevCaptureMultiplier(0);
        _setDefaultMevCaptureThreshold(0);
        // Default to the maximum value allowed by the Vault.
        _setMaxMevSwapFeePercentage(_MEV_MAX_FEE_PERCENTAGE);
    }

    function getBalancerContractRegistry() external view returns (IBalancerContractRegistry) {
        return _registry;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        _poolMevCaptureMultipliers[pool] = _defaultMevCaptureMultiplier;
        _poolMevCaptureThresholds[pool] = _defaultMevCaptureThreshold;

        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // MEV capture uses the dynamic swap fee. Searcher transactions pay a higher swap fee percentage.
        hookFlags.shouldCallComputeDynamicSwapFee = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
        hookFlags.shouldCallBeforeRemoveLiquidity = true;

        return hookFlags;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override returns (bool, uint256) {
        if (_mevCaptureEnabled == false) {
            return (true, staticSwapFeePercentage);
        }

        // We can only check senders if the router is trusted. Apply the exemption for MEV capture-exempt senders.
        if (_registry.isTrustedRouter(params.router)) {
            address sender = IRouterCommon(params.router).getSender();
            if (_isMevCaptureExempt(sender)) {
                return (true, staticSwapFeePercentage);
            }
        }

        return (
            true,
            _calculateSwapFeePercentage(
                staticSwapFeePercentage,
                _poolMevCaptureMultipliers[pool],
                _poolMevCaptureThresholds[pool]
            )
        );
    }

    /// @inheritdoc IHooks
    function onBeforeAddLiquidity(
        address,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override returns (bool success) {
        if (_mevCaptureEnabled == false) {
            return true;
        }

        uint256 priorityGasPrice = _getPriorityGasPrice();

        // Allow proportional operations, or unbalanced operations within the threshold.
        return kind == AddLiquidityKind.PROPORTIONAL || priorityGasPrice <= _poolMevCaptureThresholds[pool];
    }

    /// @inheritdoc IHooks
    function onBeforeRemoveLiquidity(
        address,
        address pool,
        RemoveLiquidityKind kind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public view override returns (bool success) {
        if (_mevCaptureEnabled == false) {
            return true;
        }

        uint256 priorityGasPrice = _getPriorityGasPrice();

        // Allow proportional operations, or unbalanced operations within the threshold.
        return kind == RemoveLiquidityKind.PROPORTIONAL || priorityGasPrice <= _poolMevCaptureThresholds[pool];
    }

    /// @inheritdoc IMevCaptureHook
    function isMevCaptureEnabled() external view returns (bool) {
        return _mevCaptureEnabled;
    }

    /// @inheritdoc IMevCaptureHook
    function disableMevCapture() external authenticate {
        _setMevCaptureEnabled(false);
    }

    /// @inheritdoc IMevCaptureHook
    function enableMevCapture() external authenticate {
        _setMevCaptureEnabled(true);
    }

    function _setMevCaptureEnabled(bool value) private {
        _mevCaptureEnabled = value;

        emit MevCaptureEnabledSet(value);
    }

    /// @inheritdoc IMevCaptureHook
    function getMaxMevSwapFeePercentage() external view returns (uint256) {
        return _maxMevSwapFeePercentage;
    }

    /// @inheritdoc IMevCaptureHook
    function setMaxMevSwapFeePercentage(uint256 maxMevSwapFeePercentage) external authenticate {
        _setMaxMevSwapFeePercentage(maxMevSwapFeePercentage);
    }

    function _setMaxMevSwapFeePercentage(uint256 maxMevSwapFeePercentage) internal {
        if (maxMevSwapFeePercentage > _MEV_MAX_FEE_PERCENTAGE) {
            revert MevSwapFeePercentageAboveMax(maxMevSwapFeePercentage, _MEV_MAX_FEE_PERCENTAGE);
        }

        _maxMevSwapFeePercentage = maxMevSwapFeePercentage;

        emit MaxMevSwapFeePercentageSet(maxMevSwapFeePercentage);
    }

    /// @inheritdoc IMevCaptureHook
    function getDefaultMevCaptureMultiplier() external view returns (uint256) {
        return _defaultMevCaptureMultiplier;
    }

    /// @inheritdoc IMevCaptureHook
    function setDefaultMevCaptureMultiplier(uint256 newDefaultMevCaptureMultiplier) external authenticate {
        _setDefaultMevCaptureMultiplier(newDefaultMevCaptureMultiplier);
    }

    function _setDefaultMevCaptureMultiplier(uint256 newDefaultMevCaptureMultiplier) private {
        _defaultMevCaptureMultiplier = newDefaultMevCaptureMultiplier;

        emit DefaultMevCaptureMultiplierSet(newDefaultMevCaptureMultiplier);
    }

    /// @inheritdoc IMevCaptureHook
    function getPoolMevCaptureMultiplier(address pool) external view withMevCaptureEnabledPool(pool) returns (uint256) {
        return _poolMevCaptureMultipliers[pool];
    }

    /// @inheritdoc IMevCaptureHook
    function setPoolMevCaptureMultiplier(
        address pool,
        uint256 newPoolMevCaptureMultiplier
    ) external withMevCaptureEnabledPool(pool) authenticate {
        _setPoolMevCaptureMultiplier(pool, newPoolMevCaptureMultiplier);
    }

    function _setPoolMevCaptureMultiplier(address pool, uint256 newPoolMevCaptureMultiplier) private {
        _poolMevCaptureMultipliers[pool] = newPoolMevCaptureMultiplier;

        emit PoolMevCaptureMultiplierSet(pool, newPoolMevCaptureMultiplier);
    }

    /// @inheritdoc IMevCaptureHook
    function getDefaultMevCaptureThreshold() external view returns (uint256) {
        return _defaultMevCaptureThreshold;
    }

    /// @inheritdoc IMevCaptureHook
    function setDefaultMevCaptureThreshold(uint256 newDefaultMevCaptureThreshold) external authenticate {
        _setDefaultMevCaptureThreshold(newDefaultMevCaptureThreshold);
    }

    function _setDefaultMevCaptureThreshold(uint256 newDefaultMevCaptureThreshold) private {
        _defaultMevCaptureThreshold = newDefaultMevCaptureThreshold;

        emit DefaultMevCaptureThresholdSet(newDefaultMevCaptureThreshold);
    }

    /// @inheritdoc IMevCaptureHook
    function getPoolMevCaptureThreshold(address pool) external view withMevCaptureEnabledPool(pool) returns (uint256) {
        return _poolMevCaptureThresholds[pool];
    }

    /// @inheritdoc IMevCaptureHook
    function setPoolMevCaptureThreshold(
        address pool,
        uint256 newPoolMevCaptureThreshold
    ) external withMevCaptureEnabledPool(pool) authenticate {
        _setPoolMevCaptureThreshold(pool, newPoolMevCaptureThreshold);
    }

    /// @inheritdoc IMevCaptureHook
    function isMevCaptureExempt(address sender) external view returns (bool) {
        return _isMevCaptureExempt(sender);
    }

    /// @inheritdoc IMevCaptureHook
    function addMevCaptureExemptSenders(address[] memory senders) external authenticate {
        uint256 numSenders = senders.length;
        for (uint256 i = 0; i < numSenders; ++i) {
            _addMevCaptureExemptSender(senders[i]);
        }
    }

    /// @inheritdoc IMevCaptureHook
    function removeMevCaptureExemptSenders(address[] memory senders) external authenticate {
        uint256 numSenders = senders.length;
        for (uint256 i = 0; i < numSenders; ++i) {
            _removeMevCaptureExemptSender(senders[i]);
        }
    }

    /*******************************************************
                        Helper functions
    *******************************************************/

    function _calculateSwapFeePercentage(
        uint256 staticSwapFeePercentage,
        uint256 multiplier,
        uint256 threshold
    ) internal view returns (uint256) {
        // If gasprice is lower than basefee, the transaction is invalid and won't be processed. Gasprice is set
        // by the transaction sender, is always bigger than basefee, and the difference between gasprice and basefee
        // defines the priority gas price (the part of the gas cost that will be paid to the validator).
        uint256 priorityGasPrice = _getPriorityGasPrice();
        uint256 maxMevSwapFeePercentage = _maxMevSwapFeePercentage;

        // If `priorityGasPrice` < threshold, this indicates the transaction is from a retail user, so we should not
        // try to capture MEV. Also, if mev fee cap is lower than static fee percentage, returns the static.
        if (priorityGasPrice < threshold || maxMevSwapFeePercentage < staticSwapFeePercentage) {
            return staticSwapFeePercentage;
        }

        (bool success, uint256 feeIncrement) = Math.tryMul(priorityGasPrice - threshold, multiplier);

        // If success == false, an overflow occurred, so we should return the max fee.
        if (success == false) {
            return maxMevSwapFeePercentage;
        }

        // Math.tryMul is not an operation with 18-decimals number, so we need to fix the result dividing by 1e18.
        feeIncrement = feeIncrement / 1e18;

        // At this point, `priorityGasPrice >= threshold` and `maxMevSwapFeePercentage >= staticSwapFeePercentage`.
        // `staticSwapFeePercentage` cannot be greater than 1e18, so there is no need to check if
        // `staticSwapFeePercentage + feeIncrement` overflows.
        uint256 mevSwapFeePercentage = staticSwapFeePercentage + feeIncrement;

        // Cap the maximum fee at `maxMevSwapFeePercentage`.
        return Math.min(mevSwapFeePercentage, maxMevSwapFeePercentage);
    }

    function _setPoolMevCaptureThreshold(address pool, uint256 newPoolMevCaptureThreshold) private {
        _poolMevCaptureThresholds[pool] = newPoolMevCaptureThreshold;

        emit PoolMevCaptureThresholdSet(pool, newPoolMevCaptureThreshold);
    }

    function _getPriorityGasPrice() internal view returns (uint256) {
        return tx.gasprice - block.basefee;
    }

    function _isMevCaptureExempt(address sender) internal view returns (bool) {
        return _isMevCaptureExemptSender[sender];
    }

    function _addMevCaptureExemptSender(address sender) internal {
        if (_isMevCaptureExemptSender[sender]) {
            revert MevCaptureExemptSenderAlreadyAdded(sender);
        }
        _isMevCaptureExemptSender[sender] = true;

        emit MevCaptureExemptSenderAdded(sender);
    }

    function _removeMevCaptureExemptSender(address sender) internal {
        if (_isMevCaptureExemptSender[sender] == false) {
            revert SenderNotRegisteredAsMevCaptureExempt(sender);
        }
        _isMevCaptureExemptSender[sender] = false;

        emit MevCaptureExemptSenderRemoved(sender);
    }
}
