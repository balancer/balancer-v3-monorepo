// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import {
    LiquidityManagement,
    TokenConfig,
    PoolSwapParams,
    HookFlags
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

import { StableSurgeMedianMath } from "./utils/StableSurgeMedianMath.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a "surge" fee on trades that unbalance the pool beyond the threshold.
 */
contract StableSurgeHook is BaseHooks, VaultGuard, SingletonAuthentication {
    using FixedPoint for uint256;
    using SafeCast for *;

    // Only pools from the allowed factory are able to register and use this hook.
    address private immutable _allowedPoolFactory;

    // Percentages are 18-decimal FP values, which fit in 64 bits (sized ensure a single slot).
    struct SurgeFeeData {
        uint64 thresholdPercentage;
        uint64 maxSurgeFeePercentage;
    }

    // The default threshold, above which surging will occur.
    uint256 private immutable _defaultMaxSurgeFeePercentage;

    // The default threshold, above which surging will occur.
    uint256 private immutable _defaultSurgeThresholdPercentage;

    // Store the current threshold and max fee for each pool.
    mapping(address pool => SurgeFeeData data) private _surgeFeePoolData;

    /**
     * @notice A new `StableSurgeHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event StableSurgeHookRegistered(address indexed pool, address indexed factory);

    /**
     * @notice The threshold percentage has been changed for a pool in a `StableSurgeHook` contract.
     * @dev Note, the initial threshold percentage is set on deployment, and an event is emitted.
     * @param pool The pool for which the threshold percentage has been changed
     * @param newSurgeThresholdPercentage The new threshold percentage
     */
    event ThresholdSurgePercentageChanged(address indexed pool, uint256 newSurgeThresholdPercentage);

    /**
     * @notice The maximum surge fee percentage has been changed for a pool in a `StableSurgeHook` contract.
     * @dev Note, the initial max surge fee percentage is set on deployment, and an event is emitted.
     * @param pool The pool for which the max surge fee percentage has been changed
     * @param newMaxSurgeFeePercentage The new max surge fee percentage
     */
    event MaxSurgeFeePercentageChanged(address indexed pool, uint256 newMaxSurgeFeePercentage);

    /// @notice The max surge fee and threshold values must be valid percentages.
    error InvalidPercentage();

    modifier withValidPercentage(uint256 percentageValue) {
        _ensureValidPercentage(percentageValue);
        _;
    }

    modifier withPermission(address pool) {
        _ensureValidSender(pool);
        _;
    }

    // Store the current threshold for each pool.
    mapping(address pool => uint256 threshold) private _surgeThresholdPercentage;

    constructor(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage
    ) SingletonAuthentication(vault) VaultGuard(vault) {
        _ensureValidPercentage(defaultSurgeThresholdPercentage);
        _ensureValidPercentage(defaultMaxSurgeFeePercentage);

        _defaultSurgeThresholdPercentage = defaultSurgeThresholdPercentage;
        _defaultMaxSurgeFeePercentage = defaultMaxSurgeFeePercentage;

        // Assumes the hook is deployed by a factory.
        _allowedPoolFactory = msg.sender;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        hookFlags.shouldCallComputeDynamicSwapFee = true;
    }

    /**
     * @notice Getter for the allowed pool factory.
     * @dev This will likely be a custom factory that deploys the standard Stable Pool with this hook contract.
     */
    function getAllowedPoolFactory() external view returns (address) {
        return _allowedPoolFactory;
    }

    /**
     * @notice Getter for the default maximum surge surge fee percentage.
     * @return maxSurgeFeePercentage The default max surge fee percentage for this hook contract
     */
    function getDefaultMaxSurgeFeePercentage() external view returns (uint256) {
        return _defaultMaxSurgeFeePercentage;
    }

    /**
     * @notice Getter for the default surge threshold percentage.
     * @return surgeThresholdPercentage The default surge threshold percentage for this hook contract
     */
    function getDefaultSurgeThresholdPercentage() external view returns (uint256) {
        return _defaultSurgeThresholdPercentage;
    }

    /**
     * @notice Getter for the maximum surge fee percentage for a pool.
     * @param pool The pool for which the max surge fee percentage is requested
     * @return maxSurgeFeePercentage The max surge fee percentage for the pool
     */
    function getMaxSurgeFeePercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].maxSurgeFeePercentage;
    }

    /**
     * @notice Getter for the surge threshold percentage for a pool.
     * @param pool The pool for which the surge threshold percentage is requested
     * @return surgeThresholdPercentage The surge threshold percentage for the pool
     */
    function getSurgeThresholdPercentage(address pool) external view returns (uint256) {
        return _surgeFeePoolData[pool].thresholdPercentage;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override onlyVault returns (bool) {
        bool isAllowedFactory = factory == _allowedPoolFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);

        if (isAllowedFactory == false) {
            return false;
        }

        // Initially set the max pool surge percentage to the default (can be changed by the pool swapFeeManager
        // in the future).
        _setMaxSurgeFeePercentage(pool, _defaultMaxSurgeFeePercentage);

        // Initially set the pool threshold to the default (can be changed by the pool swapFeeManager in the future).
        _setSurgeThresholdPercentage(pool, _defaultSurgeThresholdPercentage);

        emit StableSurgeHookRegistered(pool, factory);

        return true;
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) public view override onlyVault returns (bool, uint256) {
        return (true, getSurgeFeePercentage(params, pool, staticSwapFeePercentage));
    }

    /**
     * @notice Sets the max surge fee percentage.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the max surge
     * fee can only be changed by governance. It is initially set to the default max surge fee for this hook contract.
     */
    function setMaxSurgeFeePercentage(
        address pool,
        uint256 newMaxSurgeSurgeFeePercentage
    ) external withValidPercentage(newMaxSurgeSurgeFeePercentage) withPermission(pool) {
        _setMaxSurgeFeePercentage(pool, newMaxSurgeSurgeFeePercentage);
    }

    /**
     * @notice Sets the hook threshold percentage.
     * @dev This function must be permissioned. If the pool does not have a swap fee manager role set, the surge
     * threshold can only be changed by governance. It is initially set to the default threshold for this hook contract.
     */
    function setSurgeThresholdPercentage(
        address pool,
        uint256 newSurgeThresholdPercentage
    ) external withValidPercentage(newSurgeThresholdPercentage) withPermission(pool) {
        _setSurgeThresholdPercentage(pool, newSurgeThresholdPercentage);
    }

    /// @dev Ensure the sender is the swapFeeManager, or default to governance if there is no manager.
    function _ensureValidSender(address pool) private view {
        address swapFeeManager = _vault.getPoolRoleAccounts(pool).swapFeeManager;

        if (swapFeeManager == address(0)) {
            if (_canPerform(getActionId(msg.sig), msg.sender, pool) == false) {
                revert SenderNotAllowed();
            }
        } else if (swapFeeManager != msg.sender) {
            revert SenderNotAllowed();
        }
    }

    /**
     * @notice Calculate the surge fee percentage. If below threshold, return the standard static swap fee percentage.
     * @dev It is public to allow it to be called off-chain.
     * @param params Input parameters for the swap (balances needed)
     * @param pool The pool we are computing the fee for
     * @param staticFeePercentage The static fee percentage for the pool (default if there is no surge)
     */
    function getSurgeFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticFeePercentage
    ) public view returns (uint256) {
        uint256 numTokens = params.balancesScaled18.length;

        uint256[] memory newBalances = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            newBalances[i] = params.balancesScaled18[i];

            if (i == params.indexIn) {
                newBalances[i] += params.amountGivenScaled18;
            } else if (i == params.indexOut) {
                newBalances[i] -= params.amountGivenScaled18;
            }
        }

        uint256 newTotalImbalance = StableSurgeMedianMath.calculateImbalance(newBalances);

        // If we are balanced, or the balance has improved, do not surge: simply return the regular fee percentage.
        if (newTotalImbalance == 0) {
            return staticFeePercentage;
        }

        uint256 oldTotalImbalance = StableSurgeMedianMath.calculateImbalance(params.balancesScaled18);

        SurgeFeeData storage surgeFeeData = _surgeFeePoolData[pool];
        if (newTotalImbalance <= oldTotalImbalance || newTotalImbalance <= surgeFeeData.thresholdPercentage) {
            return staticFeePercentage;
        }

        // surgeFee = staticFee + (maxFee - staticFee) * (pctImbalance - pctThreshold) / (1 - pctThreshold).
        //
        // As you can see from the formula, if it’s unbalanced exactly at the threshold, the last term is 0,
        // and the fee is just: static + 0 = static fee.
        // As the unbalanced proportion term approaches 1, the fee surge approaches: static + max - static ~= max fee.
        // This formula linearly increases the fee from 0 at the threshold up to the maximum fee.
        // At 35%, the fee would be 1% + (0.95 - 0.01) * ((0.35 - 0.3)/(0.95-0.3)) = 1% + 0.94 * 0.0769 ~ 8.2%.
        // At 50% unbalanced, the fee would be 44%. At 99% unbalanced, the fee would be ~94%, very close to the maximum.
        return
            staticFeePercentage +
            (surgeFeeData.maxSurgeFeePercentage - staticFeePercentage).mulDown(
                (newTotalImbalance - surgeFeeData.thresholdPercentage).divDown(
                    uint256(surgeFeeData.thresholdPercentage).complement()
                )
            );
    }

    /// @dev Assumes the percentage value and sender have been externally validated.
    function _setMaxSurgeFeePercentage(address pool, uint256 newMaxSurgeFeePercentage) private {
        // Still use SafeCast out of an abundance of caution.
        _surgeFeePoolData[pool].maxSurgeFeePercentage = newMaxSurgeFeePercentage.toUint64();

        emit MaxSurgeFeePercentageChanged(pool, newMaxSurgeFeePercentage);
    }

    /// @dev Assumes the percentage value and sender have been externally validated.
    function _setSurgeThresholdPercentage(address pool, uint256 newSurgeThresholdPercentage) private {
        // Still use SafeCast out of an abundance of caution.
        _surgeFeePoolData[pool].thresholdPercentage = newSurgeThresholdPercentage.toUint64();

        emit ThresholdSurgePercentageChanged(pool, newSurgeThresholdPercentage);
    }

    function _ensureValidPercentage(uint256 percentage) private pure {
        if (percentage > FixedPoint.ONE) {
            revert InvalidPercentage();
        }
    }
}
