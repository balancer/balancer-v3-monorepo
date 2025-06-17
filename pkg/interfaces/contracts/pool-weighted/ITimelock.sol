// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts } from "../vault/VaultTypes.sol";
import { ILBPool } from "./ILBPool.sol";
import { IWeightedPool } from "./IWeightedPool.sol";

/// @notice Interface for locking tokens for a specific duration
interface ITimelock {
    struct TimeLockedAmount {
        IERC20 token;
        uint256 amount;
        uint256 unlockTimestamp;
    }

    /**
     * @notice A time-locked amount of tokens was locked for a specific owner.
     * @param owner The address of the owner of the locked tokens
     * @param token The address of the token that was locked
     * @param amount The amount of tokens that were locked
     * @param unlockTimestamp The timestamp when the locked tokens can be unlocked
     */
    event AmountLocked(address indexed owner, IERC20 token, uint256 amount, uint256 unlockTimestamp);

    /// @notice Locked amount not found for the given index.
    error TimeLockedAmountNotFound(uint256 index);

    /// @notice The locked amount is not yet unlocked.
    error TimeLockedAmountNotUnlockedYet(uint256 index, uint256 unlockTimestamp);

    /**
     * @notice Returns the time-locked amount of tokens for a specific owner and index.
     * @param owner The address of the owner of the time-locked amount
     * @param index The index of the time-locked amount
     * @return TimeLockedAmount The owner's time-locked amount
     */
    function getTimeLockedAmount(address owner, uint256 index) external view returns (TimeLockedAmount memory);

    /**
     * @notice Returns the count of time-locked amounts for a specific owner.
     * @param owner The address of the owner of the time-locked amounts
     * @return uint256 The count of time-locked amounts for the owner
     */
    function getTimeLockedAmountsCount(address owner) external view returns (uint256);

    /**
     * @notice Unlock the locked tokens for the caller.
     * @param timeLockedIndexes The indexes of the time-locked amounts to unlock
     */
    function unlockTokens(uint256[] memory timeLockedIndexes) external;
}
