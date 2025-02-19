// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { Rounding, PoolSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";

import { AclAmmMath } from "./lib/AclAmmMath.sol";

contract AclAmmPool is BalancerPoolToken, PoolInfo, Version, IBasePool {
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // Invariant growth limit: non-proportional add cannot cause the invariant to increase by more than this ratio.
    uint256 internal constant _MAX_INVARIANT_RATIO = 300e16; // 300%
    // Invariant shrink limit: non-proportional remove cannot cause the invariant to decrease by less than this ratio.
    uint256 internal constant _MIN_INVARIANT_RATIO = 70e16; // 70%

    uint256 private _lastTimestamp;
    uint256[] private _virtualBalances;

    uint256 private _c;
    uint256 private _sqrtQ0;
    uint256 private _centernessMargin;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        string memory poolVersion,
        uint256 increaseDayRate,
        uint256 sqrtQ0,
        uint256 centernessMargin
    ) BalancerPoolToken(vault, name, symbol) PoolInfo(vault) Version(poolVersion) {
        _setIncreaseDayRate(increaseDayRate);
        _setSqrtQ0(sqrtQ0);
        _setCenternessMargin(centernessMargin);
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory, Rounding) public pure returns (uint256) {
        // The pool does not accept unbalanced adds and removes, so this function does not need to be implemented.
        revert("Not implemented");
    }

    /// @inheritdoc IBasePool
    function computeBalance(uint256[] memory, uint256, uint256) external pure returns (uint256) {
        // The pool does not accept unbalanced adds and removes, so this function does not need to be implemented.
        revert("Not implemented");
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public virtual returns (uint256) {
        // Calculate virtual balances
        (uint256[] memory virtualBalances, bool changed) = AclAmmMath.getVirtualBalances(
            request.balancesScaled18,
            _virtualBalances,
            _c,
            _sqrtQ0,
            _lastTimestamp,
            _centernessMargin,
            false
        );

        _lastTimestamp = block.timestamp;
        if (changed) {
            _virtualBalances = virtualBalances;
        }

        // Calculate swap result
        if (request.kind == SwapKind.EXACT_IN) {
            return
                AclAmmMath.calculateOutGivenIn(
                    request.balancesScaled18,
                    _virtualBalances,
                    request.indexIn,
                    request.indexOut,
                    request.amountGivenScaled18
                );
        } else {
            return
                AclAmmMath.calculateInGivenOut(
                    request.balancesScaled18,
                    _virtualBalances,
                    request.indexIn,
                    request.indexOut,
                    request.amountGivenScaled18
                );
        }
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMinimumInvariantRatio() external pure returns (uint256) {
        return _MIN_INVARIANT_RATIO;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMaximumInvariantRatio() external pure returns (uint256) {
        return _MAX_INVARIANT_RATIO;
    }

    function _setIncreaseDayRate(uint256 increaseDayRate) internal {
        _c = AclAmmMath.parseIncreaseDayRate(increaseDayRate);
    }

    function _setSqrtQ0(uint256 sqrtQ0) internal {
        _sqrtQ0 = sqrtQ0;
    }

    function _setCenternessMargin(uint256 centernessMargin) internal {
        _centernessMargin = centernessMargin;
    }
}
