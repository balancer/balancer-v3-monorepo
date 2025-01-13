// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
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
    uint256 internal _defaultMevTaxMultiplier;
    uint256 internal _defaultMevTaxThreshold;
    mapping(address => uint256) internal _poolMevTaxMultipliers;
    mapping(address => uint256) internal _poolMevTaxThresholds;

    modifier withMevEnabledPool(address pool) {
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

        // disable unbalanced liquidity must be true, because the hook computes dynamic swap fees and it may be
        // bypassed by unbalanced liquidity operations.
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
        if (mevSwapFeePercentage >= _MEV_MAX_FEE_PERCENTAGE) {
            return (true, _MEV_MAX_FEE_PERCENTAGE);
        }

        // If static fee percentage is higher than mev fee percentage, uses the static one.
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
    }

    /// @inheritdoc IMevHook
    function getPoolMevTaxMultiplier(address pool) external view withMevEnabledPool(pool) returns (uint256) {
        return _poolMevTaxMultipliers[pool];
    }

    /// @inheritdoc IMevHook
    function setPoolMevTaxMultiplier(
        address pool,
        uint256 newPoolMevTaxMultiplier
    ) external withMevEnabledPool(pool) authenticate {
        _poolMevTaxMultipliers[pool] = newPoolMevTaxMultiplier;
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
    }

    /// @inheritdoc IMevHook
    function getPoolMevTaxThreshold(address pool) external view withMevEnabledPool(pool) returns (uint256) {
        return _poolMevTaxThresholds[pool];
    }

    /// @inheritdoc IMevHook
    function setPoolMevTaxThreshold(
        address pool,
        uint256 newPoolMevTaxThreshold
    ) external withMevEnabledPool(pool) authenticate {
        _poolMevTaxThresholds[pool] = newPoolMevTaxThreshold;
    }
}
