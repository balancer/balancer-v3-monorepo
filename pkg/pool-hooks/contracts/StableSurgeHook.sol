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
import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";

import { StableSurgeMedianMath } from "./utils/StableSurgeMedianMath.sol";

//import { console } from "forge-std/console.sol";

/**
 * @notice Hook that charges a fee on trades that push a pool into an imbalanced state beyond a given threshold.
 * @dev Uses the dynamic fee mechanism to apply a "surge" fee on trades that unbalance the pool beyond the threshold.
 */
contract StableSurgeHook is BaseHooks, VaultGuard, Authentication {
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
     * @notice A new `StableSurgeHookExample` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     */
    event StableSurgeHookExampleRegistered(address indexed pool);

    /**
     * @notice The threshold percentage has been changed for a pool in a `StableSurgeHookExample` contract.
     * @dev Note, the initial threshold percentage is set on deployment, and an event is emitted.
     * @param pool The pool for which the threshold percentage has been changed
     * @param newSurgeThresholdPercentage The new threshold percentage
     */
    event ThresholdSurgePercentageChanged(address indexed pool, uint256 newSurgeThresholdPercentage);

    /**
     * @notice The maximum surge fee percentage has been changed for a pool in a `StableSurgeHookExample` contract.
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

    constructor(
        IVault vault,
        uint256 defaultMaxSurgeFeePercentage,
        uint256 defaultSurgeThresholdPercentage
    ) Authentication(bytes32(uint256(uint160(address(vault))))) VaultGuard(vault) {
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
        emit StableSurgeHookExampleRegistered(pool);

        // Initially set the max pool surge percentage to the default (can be changed by the pool swapFeeManager
        // in the future).
        _setMaxSurgeFeePercentage(pool, _defaultMaxSurgeFeePercentage);

        // Initially set the pool threshold to the default (can be changed by the pool swapFeeManager in the future).
        _setSurgeThresholdPercentage(pool, _defaultSurgeThresholdPercentage);

        // This hook only allows pools deployed by `_allowedStablePoolFactory` to register it.
        return factory == _allowedPoolFactory && IBasePoolFactory(factory).isPoolFromFactory(pool);
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
        //console.log("surgeFeeData.maxSurgeFeePercentage: %s", surgeFeeData.maxSurgeFeePercentage);
        //console.log("surgeFeeData.thresholdPercentage: %s", surgeFeeData.thresholdPercentage);

        if (newTotalImbalance <= oldTotalImbalance || newTotalImbalance <= surgeFeeData.thresholdPercentage) {
            return staticFeePercentage;
        }

        // surgeFee = staticFee + (maxFee - staticFee) * (pctImbalance - pctThreshold) / (1 - pctThreshold).
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

    /// @dev Access control is delegated to the Authorizer.
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, user, address(this));
    }

    /// @dev Access control is delegated to the Authorizer. `where` refers to the target contract.
    function _canPerform(bytes32 actionId, address user, address where) internal view returns (bool) {
        return _vault.getAuthorizer().canPerform(actionId, user, where);
    }
}