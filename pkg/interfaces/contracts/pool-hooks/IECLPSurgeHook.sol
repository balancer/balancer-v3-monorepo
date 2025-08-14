// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolSwapParams } from "../vault/VaultTypes.sol";

interface IECLPSurgeHook {
    /**
     * @notice A new `ECLPSurgeHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event ECLPSurgeHookRegistered(address indexed pool, address indexed factory);

    /**
     * @notice Compute whether a swap will surge.
     * @dev If max surge fee is less than static fee, return false.
     * @param params Input parameters for the swap (balances needed)
     * @param pool The pool we are computing the surge flag for
     * @param staticSwapFeePercentage The static fee percentage for the pool (default if there is no surge)
     * @return isSurging True if the swap will surge, false otherwise
     */
    function isSurgingSwap(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) external view returns (bool isSurging);
}
