// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IMevHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/IMevHook.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    HookFlags,
    LiquidityManagement,
    PoolSwapParams,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

contract MevHook is BaseHooks, SingletonAuthentication, VaultGuard, IMevHook {
    using FixedPoint for uint256;

    uint256 private constant _MEV_MAX_FEE_PERCENTAGE = FixedPoint.ONE;

    bool internal _mevTaxEnabled = false;
    // With a 0 multiplier, the mevSwapFeePercentage will always be smaller than staticSwapFeePercentage, so the static
    // fee will be used.
    uint256 internal _mevTaxMultiplier = 0;

    constructor(IVault vault) SingletonAuthentication(vault) VaultGuard(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        return true;
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
        address,
        uint256 staticSwapFeePercentage
    ) public view override returns (bool, uint256) {
        if (_mevTaxEnabled == false) {
            return (true, staticSwapFeePercentage);
        }

        // If gasprice is lower than basefee, the transaction is invalid and won't be processed. Gasprice is set
        // by the transaction sender, is always bigger than basefee and the difference between gasprice and basefee
        // defines the priority gas price (the part of the gas cost that will be paid to the validator).
        uint256 priorityGasPrice = tx.gasprice - block.basefee;
        uint256 mevSwapFeePercentage = priorityGasPrice.mulDown(_mevTaxMultiplier);

        // If the resulting fee percentage is greater than MAX_FEE_PERCENTAGE, returns the max fee percentage.
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
        _mevTaxEnabled = false;
    }

    /// @inheritdoc IMevHook
    function enableMevTax() external authenticate {
        _mevTaxEnabled = true;
    }

    /// @inheritdoc IMevHook
    function getMevTaxMultiplier() external view returns (uint256) {
        return _mevTaxMultiplier;
    }

    /// @inheritdoc IMevHook
    function setMevTaxMultiplier(uint256 newMevTaxMultiplier) external authenticate {
        _mevTaxMultiplier = newMevTaxMultiplier;
    }
}
