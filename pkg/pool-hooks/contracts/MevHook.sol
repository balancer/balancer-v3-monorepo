// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    HooksConfig,
    HookFlags,
    LiquidityManagement,
    PoolSwapParams,
    TokenConfig,
    MAX_FEE_PERCENTAGE
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

contract MevHook is BaseHooks, SingletonAuthentication, VaultGuard, IMevHook {
    using FixedPoint for uint256;

    // Max Fee is 99.9999% (Max supported fee by the vault).
    uint256 private constant _MEV_MAX_FEE_PERCENTAGE = MAX_FEE_PERCENTAGE;

    bool internal _mevTaxEnabled;

    // Global default parameter values.
    uint256 internal _defaultMevTaxThreshold;
    uint256 internal _defaultMevTaxMultiplier;

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

    constructor(IVault vault) SingletonAuthentication(vault) VaultGuard(vault) {
        _setMevTaxEnabled(false);
        _setDefaultMevTaxMultiplier(0);
        _setDefaultMevTaxThreshold(0);
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata liquidityManagement
    ) public override onlyVault returns (bool) {
        _poolMevTaxMultipliers[pool] = _defaultMevTaxMultiplier;
        _poolMevTaxThresholds[pool] = _defaultMevTaxThreshold;

        // Unbalanced liquidity must be disabled because the hook computes dynamic swap fees that unbalanced liquidity
        // operations could bypass.
        return liquidityManagement.disableUnbalancedLiquidity;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // The MEV Tax is charged as a swap fee. Searcher transactions pay a higher swap fee percentage.
        hookFlags.shouldCallComputeDynamicSwapFee = true;
        return hookFlags;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override returns (bool, uint256) {
        if (_mevTaxEnabled == false) {
            return (true, staticSwapFeePercentage);
        }

        // If gasprice is lower than basefee, the transaction is invalid and won't be processed. Gasprice is set
        // by the transaction sender, is always bigger than basefee, and the difference between gasprice and basefee
        // defines the priority gas price (the part of the gas cost that will be paid to the validator).
        uint256 priorityGasPrice = tx.gasprice - block.basefee;

        // If `priorityGasPrice` < threshold, this indicates the transaction is from a retail user, so we should not
        // impose the MEV tax.
        if (priorityGasPrice < _poolMevTaxThresholds[pool]) {
            return (true, staticSwapFeePercentage);
        }

        uint256 mevSwapFeePercentage = priorityGasPrice.mulDown(_poolMevTaxMultipliers[pool]);

        // Cap the maximum fee at `MAX_FEE_PERCENTAGE`.
        if (mevSwapFeePercentage > _MEV_MAX_FEE_PERCENTAGE) {
            return (true, _MEV_MAX_FEE_PERCENTAGE);
        }

        // Use the greater of the static and MEV fee percentages.
        return (true, staticSwapFeePercentage > mevSwapFeePercentage ? staticSwapFeePercentage : mevSwapFeePercentage);
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

    function _setPoolMevTaxThreshold(address pool, uint256 newPoolMevTaxThreshold) private {
        _poolMevTaxThresholds[pool] = newPoolMevTaxThreshold;

        emit PoolMevTaxThresholdSet(pool, newPoolMevTaxThreshold);
    }
}
