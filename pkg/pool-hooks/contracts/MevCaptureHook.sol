// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import {
    IBalancerContractRegistry
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
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

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

contract MevCaptureHook is BaseHooks, SingletonAuthentication, VaultGuard, IMevCaptureHook {
    // Max Fee is 99.9999% (Max supported fee by the vault).
    uint256 private constant _MEV_MAX_FEE_PERCENTAGE = MAX_FEE_PERCENTAGE;

    IBalancerContractRegistry internal immutable _registry;

    bool internal _mevTaxEnabled;

    // Global default parameter values.
    uint256 internal _defaultMevTaxThreshold;
    uint256 internal _defaultMevTaxMultiplier;

    // Global max dynamic swap fee percentage returned by this hook.
    uint256 internal _maxMevSwapFeePercentage;

    // Global list of senders that bypass the MEV tax and always pay the static fee percentage.
    mapping(address => bool) internal _isMevTaxExemptSender;

    // Pool-specific parameters.
    mapping(address => uint256) internal _poolMevTaxThresholds;
    mapping(address => uint256) internal _poolMevTaxMultipliers;

    modifier withMevTaxEnabledPool(address pool) {
        HooksConfig memory hooksConfig = _vault.getHooksConfig(pool);

        if (hooksConfig.hooksContract != address(this)) {
            revert MevCaptureHookNotRegisteredInPool(pool);
        }

        _;
    }

    constructor(
        IVault vault,
        IBalancerContractRegistry registry,
        uint256 defaultMevTaxMultiplier,
        uint256 defaultMevTaxThreshold
    ) SingletonAuthentication(vault) VaultGuard(vault) {
        _registry = registry;

        // Smoke test to ensure the given registry is a contract and isn't hard-coded to trust everything.
        // For certainty, users can call `getBalancerContractRegistry` and compare the result to the published address.
        if (registry.isTrustedRouter(address(0))) {
            revert InvalidBalancerContractRegistry();
        }

        // Default to enabled and externally-provided default numerical values to reduce the need for further
        // governance actions.
        _setMevTaxEnabled(true);
        _setDefaultMevTaxMultiplier(defaultMevTaxMultiplier);
        _setDefaultMevTaxThreshold(defaultMevTaxThreshold);

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
        _poolMevTaxMultipliers[pool] = _defaultMevTaxMultiplier;
        _poolMevTaxThresholds[pool] = _defaultMevTaxThreshold;

        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // The MEV Tax is charged as a swap fee. Searcher transactions pay a higher swap fee percentage.
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
        if (_mevTaxEnabled == false) {
            return (true, staticSwapFeePercentage);
        }

        // We can only check senders if the router is trusted. Apply the exemption for MEV tax-exempt senders.
        if (_registry.isTrustedRouter(params.router)) {
            address sender = ISenderGuard(params.router).getSender();
            if (_isMevTaxExemptSender[sender]) {
                return (true, staticSwapFeePercentage);
            }
        }

        return (
            true,
            _calculateSwapFeePercentage(
                staticSwapFeePercentage,
                _poolMevTaxMultipliers[pool],
                _poolMevTaxThresholds[pool]
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
        if (_mevTaxEnabled == false) {
            return true;
        }

        uint256 priorityGasPrice = _getPriorityGasPrice();

        // Allow proportional operations, or unbalanced operations within the threshold.
        return kind == AddLiquidityKind.PROPORTIONAL || priorityGasPrice <= _poolMevTaxThresholds[pool];
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
        if (_mevTaxEnabled == false) {
            return true;
        }

        uint256 priorityGasPrice = _getPriorityGasPrice();

        // Allow proportional operations, or unbalanced operations within the threshold.
        return kind == RemoveLiquidityKind.PROPORTIONAL || priorityGasPrice <= _poolMevTaxThresholds[pool];
    }

    /// @inheritdoc IMevCaptureHook
    function isMevTaxEnabled() external view returns (bool) {
        return _mevTaxEnabled;
    }

    /// @inheritdoc IMevCaptureHook
    function disableMevTax() external authenticate {
        _setMevTaxEnabled(false);
    }

    /// @inheritdoc IMevCaptureHook
    function enableMevTax() external authenticate {
        _setMevTaxEnabled(true);
    }

    function _setMevTaxEnabled(bool value) private {
        _mevTaxEnabled = value;

        emit MevTaxEnabledSet(value);
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
    function getDefaultMevTaxMultiplier() external view returns (uint256) {
        return _defaultMevTaxMultiplier;
    }

    /// @inheritdoc IMevCaptureHook
    function setDefaultMevTaxMultiplier(uint256 newDefaultMevTaxMultiplier) external authenticate {
        _setDefaultMevTaxMultiplier(newDefaultMevTaxMultiplier);
    }

    function _setDefaultMevTaxMultiplier(uint256 newDefaultMevTaxMultiplier) private {
        _defaultMevTaxMultiplier = newDefaultMevTaxMultiplier;

        emit DefaultMevTaxMultiplierSet(newDefaultMevTaxMultiplier);
    }

    /// @inheritdoc IMevCaptureHook
    function getPoolMevTaxMultiplier(address pool) external view withMevTaxEnabledPool(pool) returns (uint256) {
        return _poolMevTaxMultipliers[pool];
    }

    /// @inheritdoc IMevCaptureHook
    function setPoolMevTaxMultiplier(
        address pool,
        uint256 newPoolMevTaxMultiplier
    ) external withMevTaxEnabledPool(pool) onlySwapFeeManagerOrGovernance(pool) {
        _setPoolMevTaxMultiplier(pool, newPoolMevTaxMultiplier);
    }

    function _setPoolMevTaxMultiplier(address pool, uint256 newPoolMevTaxMultiplier) private {
        _poolMevTaxMultipliers[pool] = newPoolMevTaxMultiplier;

        emit PoolMevTaxMultiplierSet(pool, newPoolMevTaxMultiplier);
    }

    /// @inheritdoc IMevCaptureHook
    function getDefaultMevTaxThreshold() external view returns (uint256) {
        return _defaultMevTaxThreshold;
    }

    /// @inheritdoc IMevCaptureHook
    function setDefaultMevTaxThreshold(uint256 newDefaultMevTaxThreshold) external authenticate {
        _setDefaultMevTaxThreshold(newDefaultMevTaxThreshold);
    }

    function _setDefaultMevTaxThreshold(uint256 newDefaultMevTaxThreshold) private {
        _defaultMevTaxThreshold = newDefaultMevTaxThreshold;

        emit DefaultMevTaxThresholdSet(newDefaultMevTaxThreshold);
    }

    /// @inheritdoc IMevCaptureHook
    function getPoolMevTaxThreshold(address pool) external view withMevTaxEnabledPool(pool) returns (uint256) {
        return _poolMevTaxThresholds[pool];
    }

    /// @inheritdoc IMevCaptureHook
    function setPoolMevTaxThreshold(
        address pool,
        uint256 newPoolMevTaxThreshold
    ) external withMevTaxEnabledPool(pool) onlySwapFeeManagerOrGovernance(pool) {
        _setPoolMevTaxThreshold(pool, newPoolMevTaxThreshold);
    }

    /// @inheritdoc IMevCaptureHook
    function isMevTaxExemptSender(address sender) external view returns (bool) {
        return _isMevTaxExemptSender[sender];
    }

    /// @inheritdoc IMevCaptureHook
    function addMevTaxExemptSenders(address[] memory senders) external authenticate {
        uint256 numSenders = senders.length;
        for (uint256 i = 0; i < numSenders; ++i) {
            _addMevTaxExemptSender(senders[i]);
        }
    }

    /// @inheritdoc IMevCaptureHook
    function removeMevTaxExemptSenders(address[] memory senders) external authenticate {
        uint256 numSenders = senders.length;
        for (uint256 i = 0; i < numSenders; ++i) {
            _removeMevTaxExemptSender(senders[i]);
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

        // If `priorityGasPrice` <= threshold, this indicates the transaction is from a retail user, so we should not
        // impose the MEV tax. Also, if mev fee cap is <= static fee percentage, returns the static fee percentage.
        if (priorityGasPrice <= threshold || maxMevSwapFeePercentage <= staticSwapFeePercentage) {
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

    function _setPoolMevTaxThreshold(address pool, uint256 newPoolMevTaxThreshold) private {
        _poolMevTaxThresholds[pool] = newPoolMevTaxThreshold;

        emit PoolMevTaxThresholdSet(pool, newPoolMevTaxThreshold);
    }

    function _getPriorityGasPrice() internal view returns (uint256) {
        return tx.gasprice - block.basefee;
    }

    function _addMevTaxExemptSender(address sender) internal {
        if (_isMevTaxExemptSender[sender]) {
            revert MevTaxExemptSenderAlreadyAdded(sender);
        }
        _isMevTaxExemptSender[sender] = true;

        emit MevTaxExemptSenderAdded(sender);
    }

    function _removeMevTaxExemptSender(address sender) internal {
        if (_isMevTaxExemptSender[sender] == false) {
            revert SenderNotRegisteredAsMevTaxExempt(sender);
        }
        _isMevTaxExemptSender[sender] = false;

        emit MevTaxExemptSenderRemoved(sender);
    }
}
