// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseHooks } from "../BaseHooks.sol";

error ZeroAddress();
error WrongBpt();
error LockFailed(address liquidityProvider, uint256 amount);

interface ILiquidityLocker {
    /// @notice sets bpt address for lock
    /// @dev can be set only once (for example in constructor)
    function setBpt() external;

    /// @notice returns immutable lock period in seconds
    function lockPeriod() external view returns (uint256);

    /// @notice returns immutable address of a BPT token
    function bptAddress() external view returns (address);

    /**
     * @notice Creates a lock for the liquidity provider.
     * @dev 1. If the liquidity provider already has a lock, adding new tokens
     *         will increase the lock size and update the lock expiration time.
     *      2. Requires existing allowance for transferFrom.
     * @param liquidityProvider The address of the liquidity provider.
     * @param amount The amount of tokens to lock.
     * @return A boolean indicating whether the locking operation was successful.
     */
    function lockFor(address liquidityProvider, uint256 amount) external returns (bool);

    /**
     * @notice Withdraws all BPT tokens that belong to liquidityProvider
     * @dev Can be executed when the lock is finished.
     * @param liquidityProvider The address of the liquidityProvider.
     */
    function unlockBpt(address liquidityProvider) external;

    /**
     * @notice Claims all available rewards.
     * @param liquidityProvider The address of the liquidityProvider.
     * @return A boolean indicating whether the rewards were successfully claimed.
     */
    function claimRewards(address liquidityProvider) external returns (bool);

    /**
     * @notice Returns the available rewards amount that can be claimed.
     * @param liquidityProvider The address of the liquidity provider.
     * @return The available rewards amount.
     */
    function pendingRewards(address liquidityProvider) external view returns (uint256);
}

/**
 * @title LiquidityLockForRewardsHooks
 * @notice The contract provides functionality for locking BPT tokens for
 *         a fixed period in exchange for additional rewards.
 *         This can be additional incentivization for providing liquidity into the pool.
 */
contract LiquidityLockForRewardsHooks is BaseHooks {
    ILiquidityLocker public immutable liquidityLocker;
    IERC20 public immutable bptToken;

    constructor(address _liquidityLocker, address _bptToken) {
        if (_liquidityLocker == address(0) || _bptToken == address(0)) revert ZeroAddress();
        if (_bptToken != ILiquidityLocker(_liquidityLocker).bptAddress()) revert WrongBpt();

        liquidityLocker = ILiquidityLocker(_liquidityLocker);
        bptToken = IERC20(_bptToken);
    }

    function availableHooks() external pure override returns (PoolHooks memory) {
        return
            PoolHooks({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: true,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false
            }); // Only after add liquidity hook enabled
    }

    /**
     * @notice Executes logic after adding liquidity to the pool.
     *      This function is called after a user adds liquidity to the pool.
     *      It locks the received BPT tokens for a fixed period
     *      in exchange for additional rewards, incentivizing liquidity provision to the pool.
     * @dev Approve for liquidityLocker must be done before providing liquidity.
     */
    function _onAfterAddLiquidity(
        address sender,
        uint256[] memory,
        uint256 bptAmountOut,
        uint256[] memory,
        bytes memory
    ) internal virtual override returns (bool) {
        if (!liquidityLocker.lockFor(sender, bptAmountOut)) revert LockFailed(sender, bptAmountOut);

        return true;
    }
}
