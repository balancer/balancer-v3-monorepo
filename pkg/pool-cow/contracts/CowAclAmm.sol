// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { console2 } from "forge-std/Test.sol";

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
    uint256 internal _lastInvariant;

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
        _c = increasePerDay / 110000; // A bit more than 86400 seconds (seconds/day)
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view override returns (uint256) {
        request.balancesScaled18 = _calculateNewBalances(request.balancesScaled18);

        return super.onSwap(request);
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallBeforeSwap = true;
        hookFlags.shouldCallAfterSwap = true;
        hookFlags.shouldCallAfterInitialize = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
    }

    /// @inheritdoc IHooks
    function onAfterInitialize(uint256[] memory exactAmountsIn, uint256, bytes memory) public override returns (bool) {
        (_virtualBalances, ) = _getVirtualBalances(exactAmountsIn, true);
        _lastTimestamp = block.timestamp;
        _lastInvariant = (exactAmountsIn[0] + _virtualBalances[0]).mulDown(exactAmountsIn[1] + _virtualBalances[1]);
        return true;
    }

    function onAfterSwap(PoolSwapParams memory request, address) public returns (bool) {
        (uint256[] memory virtualBalances, bool changed) = _getVirtualBalances(request.balancesScaled18, false);
        if (changed) {
            _virtualBalances = virtualBalances;
        }
        _lastTimestamp = block.timestamp;
        setLastInvariant(request.balancesScaled18);
        return true;
    }

    function _calculateNewBalances(
        uint256[] memory balancesScaled18
    ) internal view returns (uint256[] memory newBalances) {
        (uint256[] memory virtualBalances, ) = _getVirtualBalances(balancesScaled18, false);

        newBalances = new uint256[](balancesScaled18.length);

        for (uint256 i = 0; i < balancesScaled18.length; i++) {
            newBalances[i] = balancesScaled18[i] + virtualBalances[i];
        }
    }

    function updateVirtualBalances(uint256[] memory balancesScaled18) public {
        (uint256[] memory virtualBalances, bool changed) = _getVirtualBalances(balancesScaled18, false);
        if (changed) {
            _virtualBalances = virtualBalances;
        }
        _lastTimestamp = block.timestamp;
        setLastInvariant(balancesScaled18);
    }

    function getVirtualBalances(
        uint256[] memory balancesScaled18,
        bool isPoolInitializing
    ) public view returns (uint256[] memory virtualBalances, bool changed) {
        return _getVirtualBalances(balancesScaled18, isPoolInitializing);
    }

    function setVirtualBalances(uint256[] memory virtualBalances) public {
        _virtualBalances = virtualBalances;
    }

    function setLastTimestamp(uint256 lastTimestamp) public {
        _lastTimestamp = lastTimestamp;
    }

    function setLastInvariant(uint256[] memory balancesScaled18) public {
        _lastInvariant = (balancesScaled18[0] + _virtualBalances[0]).mulDown(balancesScaled18[1] + _virtualBalances[1]);
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
            // uint256 q0 = LogExpMath.pow(_sqrtQ0, 2e18);
            // virtualBalances[1] = (balancesScaled18[1].mulDown(virtualBalances[0] + balancesScaled18[0])).divDown(
            //     (q0 - FixedPoint.ONE).mulDown(virtualBalances[0]) - balancesScaled18[0]
            // );

            // // Vb = L / (Va + Ra) - Rb
            virtualBalances[1] = _lastInvariant.divDown(balancesScaled18[0] + virtualBalances[0]) - balancesScaled18[1];
            changed = true;
        } else {
            virtualBalances = _virtualBalances;
        }
    }

    function _isPoolInRange(uint256[] memory balancesScaled18) internal view returns (bool) {
        uint256 centerness = _calculateCenterness(balancesScaled18);
        console2.log("centerness", centerness);
        return centerness >= _centernessMargin;
    }

    function _calculateCenterness(uint256[] memory balancesScaled18) internal view returns (uint256) {
        if (_isAboveCenter(balancesScaled18)) {
            console2.log("above center");
            return
                balancesScaled18[1].mulDown(_virtualBalances[0]).divDown(
                    balancesScaled18[0].mulDown(_virtualBalances[1])
                );
        } else {
            console2.log("below center");
            return
                balancesScaled18[0].mulDown(_virtualBalances[1]).divDown(
                    balancesScaled18[1].mulDown(_virtualBalances[0])
                );
        }
    }

    function _isAboveCenter(uint256[] memory balancesScaled18) internal view returns (bool) {
        if (balancesScaled18[1] == 0) {
            return true;
        } else {
            return
                balancesScaled18[0].divDown(balancesScaled18[1]).divDown(_virtualBalances[0]).divDown(
                    _virtualBalances[1]
                ) >= FixedPoint.ONE;
        }
    }
}
