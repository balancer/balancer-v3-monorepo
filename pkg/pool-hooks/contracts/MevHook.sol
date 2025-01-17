// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
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

import { EnumerableSet } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableSet.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import { BalancerContractRegistry } from "@balancer-labs/v3-vault/contracts/BalancerContractRegistry.sol";

contract MevHook is BaseHooks, SingletonAuthentication, VaultGuard, IMevHook {
    using CastingHelpers for *;
    using FixedPoint for uint256;

    // Max Fee is 99.9999% (Max supported fee by the vault).
    uint256 private constant _MEV_MAX_FEE_PERCENTAGE = MAX_FEE_PERCENTAGE;

    BalancerContractRegistry internal immutable _registry;

    bool internal _mevTaxEnabled;

    // Global default parameter values.
    uint256 internal _defaultMevTaxThreshold;
    uint256 internal _defaultMevTaxMultiplier;

    // Global max dynamic swap fee percentage returned by this hook.
    uint256 internal _maxMevSwapFeePercentage;

    // Global list of senders that bypass MEV tax and pay static fees.
    EnumerableSet.AddressSet internal _mevTaxExemptSenders;

    // Pool-specific parameters.
    mapping(address => uint256) internal _poolMevTaxThresholds;
    mapping(address => uint256) internal _poolMevTaxMultipliers;

    modifier withMevTaxEnabledPool(address pool) {
        HooksConfig memory hooksConfig = _vault.getHooksConfig(pool);

        if (hooksConfig.hooksContract != address(this)) {
            revert MevHookNotRegisteredInPool(pool);
        }

        _;
    }

    constructor(IVault vault, BalancerContractRegistry registry) SingletonAuthentication(vault) VaultGuard(vault) {
        _setMevTaxEnabled(false);
        _registry = registry;

        _setDefaultMevTaxMultiplier(0);
        _setDefaultMevTaxThreshold(0);
        // Default to the maximum value allowed by the Vault.
        _setMaxMevSwapFeePercentage(_MEV_MAX_FEE_PERCENTAGE);
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

        // We can only check senders of trusted routers.
        if (_registry.isTrustedRouter(params.router)) {
            address sender = IRouterCommon(params.router).getSender();
            if (_isMevTaxExempt(sender)) {
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

    /// @inheritdoc IMevHook
    function isMevTaxEnabled() external view returns (bool) {
        return _mevTaxEnabled;
    }

    /// @inheritdoc IMevHook
    function disableMevTax() external authenticate {
        _setMevTaxEnabled(false);
    }

    /// @inheritdoc IMevHook
    function enableMevTax() external authenticate {
        _setMevTaxEnabled(true);
    }

    function _setMevTaxEnabled(bool value) private {
        _mevTaxEnabled = value;

        emit MevTaxEnabledSet(value);
    }

    /// @inheritdoc IMevHook
    function getMaxMevSwapFeePercentage() external view returns (uint256) {
        return _maxMevSwapFeePercentage;
    }

    /// @inheritdoc IMevHook
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

    /// @inheritdoc IMevHook
    function getDefaultMevTaxMultiplier() external view returns (uint256) {
        return _defaultMevTaxMultiplier;
    }

    /// @inheritdoc IMevHook
    function setDefaultMevTaxMultiplier(uint256 newDefaultMevTaxMultiplier) external authenticate {
        _setDefaultMevTaxMultiplier(newDefaultMevTaxMultiplier);
    }

    function _setDefaultMevTaxMultiplier(uint256 newDefaultMevTaxMultiplier) private {
        _defaultMevTaxMultiplier = newDefaultMevTaxMultiplier;

        emit DefaultMevTaxMultiplierSet(newDefaultMevTaxMultiplier);
    }

    /// @inheritdoc IMevHook
    function getPoolMevTaxMultiplier(address pool) external view withMevTaxEnabledPool(pool) returns (uint256) {
        return _poolMevTaxMultipliers[pool];
    }

    /// @inheritdoc IMevHook
    function setPoolMevTaxMultiplier(
        address pool,
        uint256 newPoolMevTaxMultiplier
    ) external withMevTaxEnabledPool(pool) authenticate {
        _setPoolMevTaxMultiplier(pool, newPoolMevTaxMultiplier);
    }

    function _setPoolMevTaxMultiplier(address pool, uint256 newPoolMevTaxMultiplier) private {
        _poolMevTaxMultipliers[pool] = newPoolMevTaxMultiplier;

        emit PoolMevTaxMultiplierSet(pool, newPoolMevTaxMultiplier);
    }

    /// @inheritdoc IMevHook
    function getDefaultMevTaxThreshold() external view returns (uint256) {
        return _defaultMevTaxThreshold;
    }

    /// @inheritdoc IMevHook
    function setDefaultMevTaxThreshold(uint256 newDefaultMevTaxThreshold) external authenticate {
        _setDefaultMevTaxThreshold(newDefaultMevTaxThreshold);
    }

    function _setDefaultMevTaxThreshold(uint256 newDefaultMevTaxThreshold) private {
        _defaultMevTaxThreshold = newDefaultMevTaxThreshold;

        emit DefaultMevTaxThresholdSet(newDefaultMevTaxThreshold);
    }

    /// @inheritdoc IMevHook
    function getPoolMevTaxThreshold(address pool) external view withMevTaxEnabledPool(pool) returns (uint256) {
        return _poolMevTaxThresholds[pool];
    }

    /// @inheritdoc IMevHook
    function setPoolMevTaxThreshold(
        address pool,
        uint256 newPoolMevTaxThreshold
    ) external withMevTaxEnabledPool(pool) authenticate {
        _setPoolMevTaxThreshold(pool, newPoolMevTaxThreshold);
    }

    /// @inheritdoc IMevHook
    function isMevTaxExempt(address sender) external view returns (bool) {
        return _isMevTaxExempt(sender);
    }

    /// @inheritdoc IMevHook
    function getMevTaxExemptSendersNumber() external view returns (uint256) {
        return _mevTaxExemptSenders.length();
    }

    /// @inheritdoc IMevHook
    function getMevTaxExemptSendersAt(uint256 index) external view returns (address) {
        return _mevTaxExemptSenders.at(index);
    }

    /// @inheritdoc IMevHook
    function addMevTaxExemptSenders(address[] memory mevTaxExemptSenders) external authenticate {
        uint256 numSenders = mevTaxExemptSenders.length;
        for (uint256 i = 0; i < numSenders; ++i) {
            _addMevTaxExemptSender(mevTaxExemptSenders[i]);
        }
    }

    /// @inheritdoc IMevHook
    function removeMevTaxExemptSenders(address[] memory mevTaxExemptSenders) external authenticate {
        uint256 numSenders = mevTaxExemptSenders.length;
        for (uint256 i = 0; i < numSenders; ++i) {
            _removeMevTaxExemptSender(mevTaxExemptSenders[i]);
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
        // impose the MEV tax. Also, if mev fee cap is lower than static fee percentage, returns the static.
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

    function _setPoolMevTaxThreshold(address pool, uint256 newPoolMevTaxThreshold) private {
        _poolMevTaxThresholds[pool] = newPoolMevTaxThreshold;

        emit PoolMevTaxThresholdSet(pool, newPoolMevTaxThreshold);
    }

    function _getPriorityGasPrice() internal view returns (uint256) {
        return tx.gasprice - block.basefee;
    }

    function _isMevTaxExempt(address sender) internal view returns (bool) {
        return _mevTaxExemptSenders.contains(sender);
    }

    function _addMevTaxExemptSender(address sender) internal {
        bool senderAdded = _mevTaxExemptSenders.add(sender);
        if (senderAdded == false) {
            revert MevTaxExemptSenderAlreadyAdded(sender);
        }

        emit MevTaxExemptSenderAdded(sender);
    }

    function _removeMevTaxExemptSender(address sender) internal {
        bool senderRemoved = _mevTaxExemptSenders.remove(sender);
        if (senderRemoved == false) {
            revert MevTaxExemptSenderNotAdded(sender);
        }

        emit MevTaxExemptSenderRemoved(sender);
    }
}
