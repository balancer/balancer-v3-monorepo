// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable not-rely-on-time

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { AclAmmPoolParams, IAclAmmPool } from "@balancer-labs/v3-interfaces/contracts/pool-aclamm/IAclAmmPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import {
    Rounding,
    PoolSwapParams,
    SwapKind,
    HookFlags,
    TokenConfig,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { BasePoolAuthentication } from "@balancer-labs/v3-pool-utils/contracts/BasePoolAuthentication.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { SqrtQ0State, AclAmmMath } from "./lib/AclAmmMath.sol";

contract AclAmmPool is
    IUnbalancedLiquidityInvariantRatioBounds,
    IAclAmmPool,
    BalancerPoolToken,
    PoolInfo,
    BasePoolAuthentication,
    Version,
    BaseHooks
{
    // uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0.001e16; // 0.001%
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0;
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    // Invariant growth limit: non-proportional add cannot cause the invariant to increase by more than this ratio.
    uint256 internal constant _MAX_INVARIANT_RATIO = 300e16; // 300%
    // Invariant shrink limit: non-proportional remove cannot cause the invariant to decrease by less than this ratio.
    uint256 internal constant _MIN_INVARIANT_RATIO = 70e16; // 70%

    SqrtQ0State private _sqrtQ0State;
    uint256 private _lastTimestamp;
    uint256 private _c;
    uint256 private _centerednessMargin;
    uint256[] private _virtualBalances;

    constructor(
        AclAmmPoolParams memory params,
        IVault vault
    )
        BalancerPoolToken(vault, params.name, params.symbol)
        PoolInfo(vault)
        BasePoolAuthentication(vault, msg.sender)
        Version(params.version)
    {
        _setIncreaseDayRate(params.increaseDayRate);

        _sqrtQ0State.endSqrtQ0 = params.sqrtQ0;
        _setCenterednessMargin(params.centerednessMargin);

        emit AclAmmPoolInitialized(params.increaseDayRate, params.sqrtQ0, params.centerednessMargin);
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesScaled18, Rounding rounding) public view returns (uint256) {
        return
            AclAmmMath.computeInvariant(
                balancesScaled18,
                _virtualBalances,
                _c,
                _calculateCurrentSqrtQ0(),
                _lastTimestamp,
                _centerednessMargin,
                _sqrtQ0State,
                rounding
            );
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
            _calculateCurrentSqrtQ0(),
            _lastTimestamp,
            _centerednessMargin,
            block.timestamp,
            _sqrtQ0State
        );
        _lastTimestamp = block.timestamp;
        if (changed) {
            _virtualBalances = virtualBalances;

            if (_sqrtQ0State.startTime != 0) {
                _sqrtQ0State.startTime = 0;
            }
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

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallBeforeInitialize = true;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata
    ) public view override onlyVault returns (bool) {
        return tokenConfig.length == 2;
    }

    /// @inheritdoc IHooks
    function onBeforeInitialize(
        uint256[] memory balancesScaled18,
        bytes memory
    ) public override onlyVault returns (bool) {
        _lastTimestamp = block.timestamp;
        _virtualBalances = AclAmmMath.initializeVirtualBalances(balancesScaled18, _calculateCurrentSqrtQ0());
        return true;
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

    /// @inheritdoc IAclAmmPool
    function getLastVirtualBalances() external view returns (uint256[] memory virtualBalances) {
        (, , uint256[] memory balancesScaled18, ) = _vault.getPoolTokenInfo(address(this));

        // Calculate virtual balances
        (virtualBalances, ) = AclAmmMath.getVirtualBalances(
            balancesScaled18,
            _virtualBalances,
            _c,
            _calculateCurrentSqrtQ0(),
            _lastTimestamp,
            _centerednessMargin,
            block.timestamp,
            _sqrtQ0State
        );
    }

    /// @inheritdoc IAclAmmPool
    function getLastTimestamp() external view returns (uint256) {
        return _lastTimestamp;
    }

    /// @inheritdoc IAclAmmPool
    function getCurrentSqrtQ0() external view override returns (uint256) {
        return _calculateCurrentSqrtQ0();
    }

    /// @inheritdoc IAclAmmPool
    function setSqrtQ0(
        uint256 newSqrtQ0,
        uint256 startTime,
        uint256 endTime
    ) external onlySwapFeeManagerOrGovernance(address(this)) {
        _setSqrtQ0(newSqrtQ0, startTime, endTime);
    }

    function _setSqrtQ0(uint256 endSqrtQ0, uint256 startTime, uint256 endTime) internal {
        if (startTime > endTime) {
            revert InvalidTimeRange(startTime, endTime);
        }

        uint256 startSqrtQ0 = _calculateCurrentSqrtQ0();
        _sqrtQ0State.startSqrtQ0 = startSqrtQ0;
        _sqrtQ0State.endSqrtQ0 = endSqrtQ0;
        _sqrtQ0State.startTime = startTime;
        _sqrtQ0State.endTime = endTime;

        emit SqrtQ0Updated(startSqrtQ0, endSqrtQ0, startTime, endTime);
    }

    function _calculateCurrentSqrtQ0() internal view returns (uint256) {
        SqrtQ0State memory sqrtQ0State = _sqrtQ0State;

        return
            AclAmmMath.calculateSqrtQ0(
                block.timestamp,
                sqrtQ0State.startSqrtQ0,
                sqrtQ0State.endSqrtQ0,
                sqrtQ0State.startTime,
                sqrtQ0State.endTime
            );
    }

    function _setIncreaseDayRate(uint256 increaseDayRate) internal {
        _c = AclAmmMath.parseIncreaseDayRate(increaseDayRate);
    }

    function _setCenterednessMargin(uint256 centerednessMargin) internal {
        _centerednessMargin = centerednessMargin;
    }
}
