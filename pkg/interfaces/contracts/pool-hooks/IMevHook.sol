// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

interface IMevHook {
    /**
     * @notice Check if the Mev Tax is enabled in the hook.
     * @dev If Mev Tax is disabled, all swaps will pay the static swap fee amount.
     * @return mevTaxEnabled true if the MEV Tax is enabled to be charged by the hook, false otherwise
     */
    function isMevTaxEnabled() external view returns (bool mevTaxEnabled);

    /// @notice Permissioned function to disable Mev Tax to be charged in the hook.
    function disableMevTax() external;

    /// @notice Permissioned function to enable Mev Tax to be charged in the hook.
    function enableMevTax() external;

    /**
     * @notice Fetch the current multiplier of the priority gas price.
     * @dev The MEV swap fee percentage is calculated as `mevTaxMultiplier * priorityGasPrice`, where priorityGasPrice
     * is defined as `transactionGasPrice - baseFee`. A higher mevTaxMultiplier will charge a bigger swap fee from
     * searchers, absorb more priority fee to LPs, but a too high mevTaxMultiplier may charge big swap fees from retail
     * users, which is not desired.
     *
     * @return mevTaxMultiplier The current MEV Tax Multiplier
     */
    function getMevTaxMultiplier() external view returns (uint256 mevTaxMultiplier);

    /**
     * @notice Permissioned function to set the multiplier of the priority gas price.
     * @param newMevTaxMultiplier Integer that will be used to multiply by the priority gas price and get the MEV swap
     * fee percentage
     */
    function setMevTaxMultiplier(uint256 newMevTaxMultiplier) external;
}
