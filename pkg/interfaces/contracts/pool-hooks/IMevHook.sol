// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IMevHook {
    /**
     * @notice Pool was registered in the vault with a hook that is different from Mev Hook.
     * @param pool Address of the pool that should have been initialized with MevHook
     */
    error MevHookNotRegisteredInPool(address pool);

    /**
     * @notice Check if the Mev Tax is enabled in the hook.
     * @dev If Mev Tax is disabled, all swaps will pay the static swap fee amount.
     * @return mevTaxEnabled true if the MEV Tax is enabled to be charged by the hook, false otherwise
     */
    function isMevTaxEnabled() external view returns (bool mevTaxEnabled);

    /// @notice Permissioned function to disable Mev Tax to be charged in the hook.
    function disableMevTax() external;

    /// @notice Permissioned function to enable charging the Mev Tax in registered pools.
    function enableMevTax() external;

    /**
     * @notice Fetch the default multiplier for the priority gas price.
     * @dev The MEV swap fee percentage is calculated as `mevTaxMultiplier * priorityGasPrice`, where priorityGasPrice
     * is defined as `transactionGasPrice - baseFee`. A higher mevTaxMultiplier will charge a bigger swap fee from
     * searchers, absorb more priority fee to LPs, but a too high mevTaxMultiplier may put the searcher swaps in the
     * same level of priority fees as a retail user, making it harder to differentiate retail and searcher. That's
     * undesirable.
     *
     * @return defaultMevTaxMultiplier The default MEV Tax Multiplier
     */
    function getDefaultMevTaxMultiplier() external view returns (uint256 defaultMevTaxMultiplier);

    /**
     * @notice Permissioned function to set the default multiplier of the priority gas price.
     * @param newDefaultMevTaxMultiplier Integer that will be used to multiply by the priority gas price and get the
     * MEV swap fee percentage
     */
    function setDefaultMevTaxMultiplier(uint256 newDefaultMevTaxMultiplier) external;

    /**
     * @notice Fetch the pool multiplier of the priority gas price.
     * @dev When a pool is registered with the MEV Hook in the vault, the MEV Hook initializes the multiplier of the
     * pool with the defaultMevTaxMultiplier value. If the pool is not registered with the MEV Hook, it reverts with
     * error MevHookNotRegisteredForPool(pool).
     *
     * @param pool Address of the pool with the multiplier
     * @return poolMevTaxMultiplier The multiplier of the pool
     */
    function getPoolMevTaxMultiplier(address pool) external view returns (uint256 poolMevTaxMultiplier);

    /**
     * @notice Permissioned function to set the multiplier of a pool, overriding the default value.
     * @dev The multiplier can be any unsigned integer, and will be treated as an 18 decimals number. If the pool is
     * not registered with the MEV Hook, it reverts with error MevHookNotRegisteredForPool(pool).
     * @param pool Address of the pool with the multiplier
     * @param newPoolMevTaxMultiplier New multiplier to be set in a pool
     */
    function setPoolMevTaxMultiplier(address pool, uint256 newPoolMevTaxMultiplier) external;

    /**
     * @notice Fetch the default threshold of the priority gas price.
     * @dev The MEV swap fee percentage is only applied if the priority gas price, defined as
     * `transactionGasPrice - baseFee`, is bigger than the threshold.
     *
     * @return defaultMevTaxThreshold The default MEV Tax Threshold
     */
    function getDefaultMevTaxThreshold() external view returns (uint256 defaultMevTaxThreshold);

    /**
     * @notice Permissioned function to set the default threshold of the priority gas price.
     * @dev The threshold can be any unsigned integer and represents the priority gas price, in gwei. It's used to
     * check if the priority gas price is in the level of a retail swap or a searcher swap.
     *
     * @param newDefaultMevTaxThreshold The new default threshold
     */
    function setDefaultMevTaxThreshold(uint256 newDefaultMevTaxThreshold) external;

    /**
     * @notice Fetch the pool threshold of the priority gas price.
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
     * @dev The threshold can be any unsigned integer and represents the priority gas price, in gwei. It's used to
     * check if the priority gas price is in the level of a retail swap or a searcher swap. If the pool is not
     * registered with the MEV Hook, it reverts with error MevHookNotRegisteredForPool(pool).
     *
     * @param pool Address of the pool with the threshold
     * @param newPoolMevTaxThreshold The new threshold to be set in a pool
     */
    function setPoolMevTaxThreshold(address pool, uint256 newPoolMevTaxThreshold) external;
}
