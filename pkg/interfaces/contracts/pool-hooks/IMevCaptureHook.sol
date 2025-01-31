// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBalancerContractRegistry } from "../standalone-utils/IBalancerContractRegistry.sol";

interface IMevCaptureHook {
    /**
     * @notice The pool was not registered with the MEV Hook contract.
     * @param pool Address of the pool that should have been registered with MevCaptureHook
     */
    error MevCaptureHookNotRegisteredInPool(address pool);

    /**
     * @notice The new max MEV swap fee percentage is above the allowed absolute maximum.
     * @param feePercentage New fee percentage being set
     * @param maxFeePercentage Absolute maximum allowed
     */
    error MevSwapFeePercentageAboveMax(uint256 feePercentage, uint256 maxFeePercentage);

    /**
     * @notice The sender is already registered as MEV capture-exempt.
     * @param sender Sender that is already MEV capture-exempt
     */
    error MevCaptureExemptSenderAlreadyAdded(address sender);

    /**
     * @notice The sender is not registered as MEV capture-exempt.
     * @param sender Sender that is not MEV capture-exempt
     */
    error SenderNotRegisteredAsMevCaptureExempt(address sender);

    /**
     * @notice MEV capture was globally enabled or disabled in the hook.
     * @param enabled The new value for mevCaptureEnabled
     */
    event MevCaptureEnabledSet(bool enabled);

    /**
     * @notice The default MEV capture multiplier was set.
     * @dev Registered pools should set the multiplier using `setPoolMevCaptureMultiplier`.
     * @param newDefaultMevCaptureMultiplier The new value for defaultMevCaptureMultiplier
     */
    event DefaultMevCaptureMultiplierSet(uint256 newDefaultMevCaptureMultiplier);

    /**
     * @notice The default MEV capture threshold was set.
     * @dev Registered pools should set the threshold using `setPoolMevCaptureThreshold`.
     * @param newDefaultMevCaptureThreshold The new value for defaultMevCaptureThreshold
     */
    event DefaultMevCaptureThresholdSet(uint256 newDefaultMevCaptureThreshold);

    /**
     * @notice The maximum MEV swap fee percentage was set.
     * @param maxMevSwapFeePercentage The new value for maxMevSwapFeePercentage.
     */
    event MaxMevSwapFeePercentageSet(uint256 maxMevSwapFeePercentage);

    /**
     * @notice A pool's MEV capture multiplier was set.
     * @param pool The address of the pool where the multiplier has changed
     * @param newPoolMevCaptureMultiplier The new value for the pool multiplier
     */
    event PoolMevCaptureMultiplierSet(address pool, uint256 newPoolMevCaptureMultiplier);

    /**
     * @notice The default MEV capture threshold was set.
     * @param pool The address of the pool where the threshold has changed
     * @param newPoolMevCaptureThreshold The new value for the pool threshold
     */
    event PoolMevCaptureThresholdSet(address pool, uint256 newPoolMevCaptureThreshold);

    /**
     * @notice The sender was registered as MEV capture-exempt.
     * @param sender The address of the sender registered as MEV capture-exempt
     */
    event MevCaptureExemptSenderAdded(address sender);

    /**
     * @notice The sender was removed from the list of MEV capture-exempt senders.
     * @param sender The address of the sender removed from the MEV capture-exempt list
     */
    event MevCaptureExemptSenderRemoved(address sender);

    /// @notice Returns `BalancerContractRegistry`.
    function getBalancerContractRegistry() external view returns (IBalancerContractRegistry);

    /**
     * @notice Check whether MEV capture is enabled in the hook.
     * @dev If MEV capture is disabled, all swaps will pay the static swap fee amount.
     * @return mevCaptureEnabled True if MEV capture is enabled
     */
    function isMevCaptureEnabled() external view returns (bool mevCaptureEnabled);

    /// @notice Permissioned function to reversibly disable capturing MEV in registered pools.
    function disableMevCapture() external;

    /// @notice Permissioned function to enable capturing MEV in registered pools.
    function enableMevCapture() external;

    /**
     * @notice Returns the maximum MEV swap fee percentage returned by `onComputeDynamicSwapFeePercentage`.
     * @dev The absolute minimum is still the static swap fee percentage of the pool.
     * In other words:
     * - if `maxMevSwapFeePercentage > staticSwapFeePercentage`, then
     * `staticSwapFeePercentage <= computedFeePercentage <= maxMevSwapFeePercentage`
     * - if `maxMevSwapFeePercentage <= staticSwapFeePercentage, then `computedFeePercentage = maxMevSwapFeePercentage`
     */
    function getMaxMevSwapFeePercentage() external view returns (uint256);

    /**
     * @notice Permissioned function to set the maximum MEV swap fee percentage returned by
     * `onComputeDynamicSwapFeePercentage`.
     * @dev See `getMaxMevSwapFeePercentage` for reference; this maximum applies only when
     * `maxMevSwapFeePercentage > staticSwapFeePercentage`.
     * Capped by MAX_FEE_PERCENTAGE defined by the Vault.
     */
    function setMaxMevSwapFeePercentage(uint256 maxMevSwapFeePercentage) external;

    /**
     * @notice Fetch the default multiplier for the priority gas price.
     * @dev The MEV swap fee percentage is calculated as `mevCaptureMultiplier * priorityGasPrice`, where priorityGasPrice
     * is defined as `transactionGasPrice - baseFee`. This leads to a trade-off that requires careful calibration of
     * the mevCaptureMultiplier to incentivize both searchers and LPs.
     *
     * A higher mevCaptureMultiplier will raise the swap fee for searchers and accrue more priority fees for LPs. However,
     * raising the mevCaptureMultiplier too high may raise searchers' priority fees to levels more typical of retail users,
     * making it difficult for the contract to distinguish between them.
     *
     * @return defaultMevCaptureMultiplier The default MEV capture Multiplier
     */
    function getDefaultMevCaptureMultiplier() external view returns (uint256 defaultMevCaptureMultiplier);

    /**
     * @notice Permissioned function to set the default multiplier of the priority gas price.
     * @dev The multiplier is not validated or limited by any value and can assume any 18-decimal number. That's
     * because the multiplier value depends on the priority gas price used by searchers in a given moment for a
     * specific chain. However, the resulting swap fee percentage, given by `priorityGasPrice * multiplier`, is capped
     * at the lower end by the static swap fee, and at the upper end by the maximum swap fee percentage of the vault.
     * Therefore, a multiplier with value 0 will effectively disable MEV capture, since the static swap fee will be
     * charged. Also, a very high multiplier will make the trader pay the maximum configured swap fee which can be
     * close to 100%, effectively disabling swaps.
     *
     * @param newDefaultMevCaptureMultiplier 18-decimal used to calculate the MEV swap fee percentage
     */
    function setDefaultMevCaptureMultiplier(uint256 newDefaultMevCaptureMultiplier) external;

    /**
     * @notice Fetch the priority gas price multiplier of the given pool.
     * @dev When a pool is registered with the MEV Hook in the vault, the MEV Hook initializes the multiplier of the
     * pool to the defaultMevCaptureMultiplier value. If the pool is not registered with the MEV Hook, it reverts with
     * error MevCaptureHookNotRegisteredForPool(pool).
     *
     * @param pool Address of the pool with the multiplier
     * @return poolMevCaptureMultiplier The multiplier of the pool
     */
    function getPoolMevCaptureMultiplier(address pool) external view returns (uint256 poolMevCaptureMultiplier);

    /**
     * @notice Permissioned function to set the MEV capture multiplier of a pool, overriding the default value.
     * @dev The multiplier is not validated or limited by any value and can assume any 18-decimal number. That's
     * because the multiplier value depends on the priority gas price used by searchers in a given moment for a
     * specific chain. If the pool is not registered with the MEV Hook, it reverts with error
     * MevCaptureHookNotRegisteredForPool(pool). However, the resulting swap fee percentage, given by
     * `priorityGasPrice * multiplier`, is capped in the lower end by the static swap fee, and at the upper end by
     * the maximum swap fee percentage of the vault. Therefore, a multiplier with value 0 will effectively disable
     * MEV capture, since the static swap fee will be charged. Also, a very high multiplier will make the trader pay
     * the maximum configured swap fee which can be close to 100%, effectively disabling swaps.
     *
     * @param pool Address of the pool with the multiplier
     * @param newPoolMevCaptureMultiplier New multiplier to be set in a pool
     */
    function setPoolMevCaptureMultiplier(address pool, uint256 newPoolMevCaptureMultiplier) external;

    /**
     * @notice Fetch the default priority gas price threshold.
     * @dev The MEV swap fee percentage is only applied if the priority gas price, defined as
     * `transactionGasPrice - baseFee`, is greater than the threshold.
     *
     * @return defaultMevCaptureThreshold The default MEV capture Threshold
     */
    function getDefaultMevCaptureThreshold() external view returns (uint256 defaultMevCaptureThreshold);

    /**
     * @notice Permissioned function to set the default priority gas price threshold.
     * @dev The threshold can be any unsigned integer and represents the priority gas price, in wei. It's used to
     * check whether the priority gas price level corresponds to a retail or searcher swap. The threshold value is not
     * capped by any value, since it depends on the chain state. A very high threshold (above the priority gas price of
     * searchers in the chain) will disable MEV capture and charge the static swap fee.
     *
     * @param newDefaultMevCaptureThreshold The new default threshold
     */
    function setDefaultMevCaptureThreshold(uint256 newDefaultMevCaptureThreshold) external;

    /**
     * @notice Fetch the priority gas price threshold of the given pool.
     * @dev When a pool is registered with the MEV Hook in the vault, the MEV Hook initializes the multiplier of the
     * pool with the defaultMevCaptureMultiplier value. If the pool is not registered with the MEV Hook, it reverts with
     * error MevCaptureHookNotRegisteredForPool(pool).
     *
     * @param pool Address of the pool with the multiplier
     * @return poolMevCaptureThreshold The threshold of the pool
     */
    function getPoolMevCaptureThreshold(address pool) external view returns (uint256 poolMevCaptureThreshold);

    /**
     * @notice Permissioned function to set the threshold of a pool, overriding the current value.
     * @dev The threshold can be any unsigned integer and represents the priority gas price, in wei. It's used to
     * check whether the priority gas price level corresponds to a retail or searcher swap. The threshold value is not
     * capped by any value, since it depends on the chain state. If the pool is not registered with the MEV Hook, it
     * reverts with error MevCaptureHookNotRegisteredForPool(pool). A very high threshold (above the priority gas price of
     * searchers in the chain) will disable MEV capture and charge the static swap fee.
     *
     * @param pool Address of the pool with the threshold
     * @param newPoolMevCaptureThreshold The new threshold to be set in a pool
     */
    function setPoolMevCaptureThreshold(address pool, uint256 newPoolMevCaptureThreshold) external;

    /**
     * @notice Checks whether the sender is MEV capture-exempt.
     * @dev An MEV capture-exempt sender pays only the static swap fee percentage, regardless of the priority fee.
     * @param sender The sender being checked for MEV capture-exempt status
     * @return mevCaptureExempt True if the sender is MEV capture-exempt
     */
    function isMevCaptureExempt(address sender) external view returns (bool mevCaptureExempt);

    /**
     * @notice Registers a list of senders as MEV capture-exempt senders.
     * @param senders Addresses of senders to be registered as MEV capture-exempt
     */
    function addMevCaptureExemptSenders(address[] memory senders) external;

    /**
     * @notice Removes a list of senders from the list of MEV capture-exempt senders.
     * @param senders Addresses of senders to be removed from the MEV capture-exempt list
     */
    function removeMevCaptureExemptSenders(address[] memory senders) external;
}
