// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { HookFlags, PoolSwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { LogExpMath } from "@balancer-labs/v3-solidity-utils/contracts/math/LogExpMath.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { CowPool } from "./CowPool.sol";

contract CowAclAmm is CowPool {
    using FixedPoint for uint256;

    uint256 internal _sqrtQ0;
    uint256 internal _centernessMargin;
    uint256[] internal _virtualBalances;
    uint256 immutable _c;

    uint256 internal _lastTimestamp;

    constructor(
        WeightedPool.NewPoolParams memory params,
        IVault vault,
        address trustedCowRouter,
        uint256 sqrtQ0,
        uint256 centernessMargin,
        uint256 increasePerDay
    ) CowPool(params, vault, trustedCowRouter) {
        // TODO Check num tokens is 2
        _sqrtQ0 = sqrtQ0;
        _centernessMargin = centernessMargin;
        _c = increasePerDay / 86400;
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public override returns (uint256) {
        request.balancesScaled18 = _calculateNewBalances(request.balancesScaled18);
        _lastTimestamp = block.timestamp;

        return super.onSwap(request);
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallBeforeSwap = true;
        hookFlags.shouldCallAfterInitialize = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
    }

    /// @inheritdoc IHooks
    function onAfterInitialize(uint256[] memory exactAmountsIn, uint256, bytes memory) public override returns (bool) {
        (_virtualBalances, ) = _getVirtualBalances(exactAmountsIn, true);
        _lastTimestamp = block.timestamp;
        return true;
    }

    function _calculateNewBalances(uint256[] memory balancesScaled18) internal returns (uint256[] memory newBalances) {
        (uint256[] memory virtualBalances, bool changed) = _getVirtualBalances(balancesScaled18, false);
        if (changed) {
            _virtualBalances = virtualBalances;
        }

        newBalances = new uint256[](balancesScaled18.length);

        for (uint256 i = 0; i < balancesScaled18.length; i++) {
            newBalances[i] = balancesScaled18[i] + virtualBalances[i];
        }
    }

    function getVirtualBalances(
        uint256[] memory balancesScaled18,
        bool isPoolInitializing
    ) public view returns (uint256[] memory virtualBalances, bool changed) {
        return _getVirtualBalances(balancesScaled18, isPoolInitializing);
    }

    function _getVirtualBalances(
        uint256[] memory balancesScaled18,
        bool isPoolInitializing
    ) internal view returns (uint256[] memory virtualBalances, bool changed) {
        virtualBalances = new uint256[](balancesScaled18.length);

        if (isPoolInitializing) {
            for (uint256 i = 0; i < balancesScaled18.length; i++) {
                virtualBalances[i] = balancesScaled18[i].divDown(_sqrtQ0 - FixedPoint.ONE);
            }
            changed = true;
        } else if (_isPoolInRange(balancesScaled18) == false) {
            if (_isAboveCenter(balancesScaled18)) {
                virtualBalances[0] = _virtualBalances[0].mulDown(
                    LogExpMath.pow(FixedPoint.ONE + _c, (block.timestamp - _lastTimestamp) * FixedPoint.ONE)
                );
            } else {
                virtualBalances[0] = _virtualBalances[0].mulDown(
                    LogExpMath.pow(FixedPoint.ONE - _c, (block.timestamp - _lastTimestamp) * FixedPoint.ONE)
                );
            }

            // (Rb * (Va + Ra)) / (((Q0 - 1) * Va) - Ra)
            uint256 q0 = LogExpMath.pow(_sqrtQ0, 2e18);
            virtualBalances[1] = (balancesScaled18[1].mulDown(virtualBalances[0] + balancesScaled18[0])).divDown(
                (q0 - FixedPoint.ONE).mulDown(virtualBalances[0]) - balancesScaled18[0]
            );
            changed = true;
        } else {
            virtualBalances = _virtualBalances;
        }
    }

    function _calculateCenterness(uint256[] memory balancesScaled18) internal view returns (uint256) {
        if (_isAboveCenter(balancesScaled18)) {
            return
                balancesScaled18[1].mulDown(_virtualBalances[0]).divDown(
                    balancesScaled18[0].mulDown(_virtualBalances[1])
                );
        } else {
            return
                balancesScaled18[0].mulDown(_virtualBalances[1]).divDown(
                    balancesScaled18[1].mulDown(_virtualBalances[0])
                );
        }
    }

    function _isPoolInRange(uint256[] memory balancesScaled18) internal view returns (bool) {
        uint256 centerness = _calculateCenterness(balancesScaled18);
        return centerness >= _centernessMargin;
    }

    function _isAboveCenter(uint256[] memory balancesScaled18) internal view returns (bool) {
        return
            balancesScaled18[0].divDown(balancesScaled18[1]).divDown(_virtualBalances[0]).divDown(
                _virtualBalances[1]
            ) >= FixedPoint.ONE;
    }
}
