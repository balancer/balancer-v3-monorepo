// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Maintain a set of pools that can be paused from this helper contract, vs. directly from the Vault.
 * @dev Governance can add a set of pools to this contract, then grant pause permission to accounts here, which
 * allows greater granularity than setting the permission directly on the Vault.
 *
 * Note that governance must grant this contract permission to pause pools from the Vault. Unpausing is not
 * addressed here, and must still be done through the Vault.
 */
interface IPoolPauseHelper {
    /**
     * @notice Pause a set of pools.
     * @dev This is a permissioned function. Governance must first grant this contract permission to call `pausePool`
     * on the Vault, then grant another account permission to call `pausePools` here. Note that this is not necessarily
     * the same account that can add or remove pools from the pausable list.
     *
     * Note that there is no `unpause`. This is a helper contract designed to react quickly to emergencies. Unpausing
     * is a more deliberate action that should be performed by accounts approved by governance for this purpose, or by
     * the individual pools' pause managers.
     *
     * @param pools List of pools to pause
     */
    function pausePools(address[] memory pools) external;
}
