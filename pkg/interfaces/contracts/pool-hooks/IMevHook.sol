// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IMevHook {
    /**
     * @notice The pool was not registered with the MEV Hook contract.
     * @param pool Address of the pool that should have been registered with MevHook
     */
    error MevHookNotRegisteredInPool(address pool);

    /**
     * @notice The MEV tax was globally enabled or disabled in the hook.
     * @param enabled The new value for mevTaxEnabled. If true, MEV tax will be charged
     */
    event MevTaxEnabledSet(bool enabled);

    /**
     * @notice Default MEV tax multiplier was set.
     * @dev Registered pools should set the multiplier using `setPoolMevTaxMultiplier`.
     * @param newDefaultMevTaxMultiplier The new value for defaultMevTaxMultiplier
     */
    event DefaultMevTaxMultiplierSet(uint256 newDefaultMevTaxMultiplier);

    /**
     * @notice The default MEV tax threshold was set.
     * @dev Registered pools should set the threshold using `setPoolMevTaxThreshold`.
     * @param newDefaultMevTaxThreshold The new value for defaultMevTaxThreshold
     */
    event DefaultMevTaxThresholdSet(uint256 newDefaultMevTaxThreshold);

    /**
     * @notice A pool's MEV tax multiplier was set.
     * @param pool The address of the pool where the multiplier has changed
     * @param newPoolMevTaxMultiplier The new value for the pool multiplier
     */
    event PoolMevTaxMultiplierSet(address pool, uint256 newPoolMevTaxMultiplier);

    /**
     * @notice The default MEV tax threshold was set.
     * @param pool The address of the pool where the threshold has changed
     * @param newPoolMevTaxThreshold The new value for the pool threshold
     */
    event PoolMevTaxThresholdSet(address pool, uint256 newPoolMevTaxThreshold);

    /**
     * @notice Check whether the MEV Tax is enabled in the hook.
     * @dev If MEV Tax is disabled, all swaps will pay the static swap fee amount.
     * @return mevTaxEnabled True if the MEV Tax is enabled
     */
    function isMevTaxEnabled() external view returns (bool mevTaxEnabled);

    /// @notice Permissioned function to reversibly disable charging the MEV Tax in registered pools.
    function disableMevTax() external;

    /// @notice Permissioned function to enable charging the MEV Tax in registered pools.
    function enableMevTax() external;

    /**
     * @notice Fetch the default multiplier for the priority gas price.
     * @dev The MEV swap fee percentage is calculated as `mevTaxMultiplier * priorityGasPrice`, where priorityGasPrice
     * is defined as `transactionGasPrice - baseFee`. This leads to a trade-off that requires careful calibration of
     * the mevTaxMultiplier to incentivize both searchers and LPs.
     *
     * A higher mevTaxMultiplier will raise the swap fee for searchers and accrue more priority fees for LPs. However,
     * raising the mevTaxMultiplier too high may raise searchers' priority fees to levels more typical of retail users,
     * making it difficult for the contract to distinguish between them.
     *
     * @return defaultMevTaxMultiplier The default MEV Tax Multiplier
     */
    function getDefaultMevTaxMultiplier() external view returns (uint256 defaultMevTaxMultiplier);

    /**
     * @notice Permissioned function to set the default multiplier of the priority gas price.
     * @dev The multiplier is not validated or limited by any value and can assume any 18-decimal number. That's
     * because the multiplier value depends on the priority gas price used by searchers in a given moment for a
     * specific chain. However, the resulting swap fee percentage, given by `priorityGasPrice * multiplier`, is capped
     * in the lower end by the static swap fee, and in the upper end by the maximum swap fee percentage of the vault.
     * Therefore, a multiplier with value 0 will effectively disable the MEV tax, since the static swap fee will be
     * charged. Also, a very high multiplier may disable pool swaps, since the MEV tax will be 99.9999%.
     *
     * @param newDefaultMevTaxMultiplier 18-decimal used to calculate the MEV swap fee percentage
     */
    function setDefaultMevTaxMultiplier(uint256 newDefaultMevTaxMultiplier) external;

    /**
     * @notice Fetch the priority gas price multiplier of the given pool.
     * @dev When a pool is registered with the MEV Hook in the vault, the MEV Hook initializes the multiplier of the
     * pool to the defaultMevTaxMultiplier value. If the pool is not registered with the MEV Hook, it reverts with
     * error MevHookNotRegisteredForPool(pool).
     *
     * @param pool Address of the pool with the multiplier
     * @return poolMevTaxMultiplier The multiplier of the pool
     */
    function getPoolMevTaxMultiplier(address pool) external view returns (uint256 poolMevTaxMultiplier);

    /**
     * @notice Permissioned function to set the MEV tax multiplier of a pool, overriding the default value.
     * @dev The multiplier is not validated or limited by any value and can assume any 18-decimal number. That's
     * because the multiplier value depends on the priority gas price used by searchers in a given moment for a
     * specific chain. If the pool is not registered with the MEV Hook, it reverts with error
     * MevHookNotRegisteredForPool(pool). However, the resulting swap fee percentage, given by
     * `priorityGasPrice * multiplier`, is capped in the lower end by the static swap fee, and in the upper end by
     * the maximum swap fee percentage of the vault. Therefore, a multiplier with value 0 will effectively disable the
     * MEV tax, since the static swap fee will be charged. Also, a very high multiplier may disable pool swaps, since
     * the MEV tax will be 99.9999%.
     *
     * @param pool Address of the pool with the multiplier
     * @param newPoolMevTaxMultiplier New multiplier to be set in a pool
     */
    function setPoolMevTaxMultiplier(address pool, uint256 newPoolMevTaxMultiplier) external;

    /**
     * @notice Fetch the default priority gas price threshold.
     * @dev The MEV swap fee percentage is only applied if the priority gas price, defined as
     * `transactionGasPrice - baseFee`, is greater than the threshold.
     *
     * @return defaultMevTaxThreshold The default MEV Tax Threshold
     */
    function getDefaultMevTaxThreshold() external view returns (uint256 defaultMevTaxThreshold);

    /**
     * @notice Permissioned function to set the default priority gas price threshold.
     * @dev The threshold can be any unsigned integer and represents the priority gas price, in wei. It's used to
     * check whether the priority gas price level corresponds to a retail or searcher swap. The threshold value is not
     * capped by any value, since it depends on the chain state. A very high threshold (above the priority gas price of
     * searchers in the chain) will disable the MEV tax and charge the static swap fee.
     *
     * @param newDefaultMevTaxThreshold The new default threshold
     */
    function setDefaultMevTaxThreshold(uint256 newDefaultMevTaxThreshold) external;

    /**
     * @notice Fetch the priority gas price threshold of the given pool.
     * @dev When a pool is registered with the MEV Hook in the vault, the MEV Hook initializes the multiplier of the
     * pool with the defaultMevTaxMultiplier value. If the pool is not registered with the MEV Hook, it reverts with
     * error MevHookNotRegisteredForPool(pool).
     *
     * @param pool Address of the pool with the multiplier
     * @return poolMevTaxThreshold The threshold of the pool
     */
    function getPoolMevTaxThreshold(address pool) external view returns (uint256 poolMevTaxThreshold);

    /**
     * @notice Permissioned function to set the threshold of a pool, overriding the current value.
     * @dev The threshold can be any unsigned integer and represents the priority gas price, in wei. It's used to
     * check whether the priority gas price level corresponds to a retail or searcher swap. The threshold value is not
     * capped by any value, since it depends on the chain state. If the pool is not registered with the MEV Hook, it
     * reverts with error MevHookNotRegisteredForPool(pool). A very high threshold (above the priority gas price of
     * searchers in the chain) will disable the MEV tax and charge the static swap fee.
     *
     * @param pool Address of the pool with the threshold
     * @param newPoolMevTaxThreshold The new threshold to be set in a pool
     */
    function setPoolMevTaxThreshold(address pool, uint256 newPoolMevTaxThreshold) external;
}
