// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/**
 * @notice Maintain a set of pools whose static swap fee percentages can be changed from here, vs. from the Vault.
 * @dev Governance can add a set of pools to this contract, then grant swap fee setting permission to accounts on this
 * contract, which allows greater granularity than setting the permission directly on the Vault.
 *
 * Note that governance must grant this contract permission to set swap fees from the Vault, and only pools that
 * allow governance to set fees can be added (i.e., they must not have swap managers).
 */
interface IPoolSwapFeeHelper {
    /**
     * @notice Cannot add a pool that has a swap manager.
     * @dev The swap manager is an exclusive role. If it is set to a non-zero value during pool registration,
     * only the swap manager can change the fee. This helper can only set fees on pools that allow governance
     * to grant this permission.
     *
     * @param pool Address of the pool being added
     */
    error PoolHasSwapManager(address pool);

    /***************************************************************************
                                    Manage Pools
    ***************************************************************************/

    /**
     * @notice Set the static swap fee percentage on a given pool.
     * @dev This is a permissioned function. Governance must grant this contract permission to call
     * `setStaticSwapFeePercentage` on the Vault. Note that since the swap manager is an exclusive role, the swap fee
     * cannot be changed by governance if it is set, and the pool cannot be added to the set.
     *
     * @param pool The address of the pool
     * @param swapFeePercentage The new swap fee percentage
     */
    function setStaticSwapFeePercentage(address pool, uint256 swapFeePercentage) external;
}
