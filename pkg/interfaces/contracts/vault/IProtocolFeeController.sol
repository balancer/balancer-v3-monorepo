// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";

/// @notice Contract that handles protocol and pool creator fees for the Vault.
interface IProtocolFeeController {
    /**
     * @notice Emitted when the protocol swap fee percentage is updated.
     * @param swapFeePercentage The updated protocol swap fee percentage
     */
    event GlobalProtocolSwapFeePercentageChanged(uint256 swapFeePercentage);

    /**
     * @notice Emitted when the protocol yield fee percentage is updated.
     * @param yieldFeePercentage The updated protocol yield fee percentage
     */
    event GlobalProtocolYieldFeePercentageChanged(uint256 yieldFeePercentage);

    /**
     * @notice Emitted when the protocol swap fee percentage is updated for a specific pool.
     * @param pool The pool whose protocol swap fee will be changed
     * @param swapFeePercentage The updated protocol swap fee percentage
     */
    event ProtocolSwapFeePercentageChanged(address indexed pool, uint256 swapFeePercentage);

    /**
     * @notice Emitted when the protocol yield fee percentage is updated for a specific pool.
     * @param pool The pool whose protocol yield fee will be changed
     * @param yieldFeePercentage The updated protocol yield fee percentage
     */
    event ProtocolYieldFeePercentageChanged(address indexed pool, uint256 yieldFeePercentage);

    /**
     * @notice Emitted when the pool creator swap fee percentage of a pool is updated.
     * @param pool The pool whose pool creator swap fee will be changed
     * @param poolCreatorSwapFeePercentage The new pool creator swap fee percentage for the pool
     */
    event PoolCreatorSwapFeePercentageChanged(address indexed pool, uint256 poolCreatorSwapFeePercentage);

    /**
     * @notice Emitted when the pool creator yield fee percentage of a pool is updated.
     * @param pool The pool whose pool creator yield fee will be changed
     * @param poolCreatorYieldFeePercentage The new pool creator yield fee percentage for the pool
     */
    event PoolCreatorYieldFeePercentageChanged(address indexed pool, uint256 poolCreatorYieldFeePercentage);

    /**
     * @notice Logs the collection of protocol swap fees in a specific token and amount.
     * @dev Note that since charging protocol fees (i.e., distributing tokens between pool and fee balances) occurs
     * in the Vault, but fee collection happens in the ProtocolFeeController, the swap fees reported here may encompass
     * multiple operations.
     *
     * @param pool The pool on which the swap fee was charged
     * @param token The token in which the swap fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolSwapFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @notice Logs the collection of protocol yield fees in a specific token and amount.
     * @dev Note that since charging protocol fees (i.e., distributing tokens between pool and fee balances) occurs
     * in the Vault, but fee collection happens in the ProtocolFeeController, the yield fees reported here may encompass
     * multiple operations.
     *
     * @param pool The pool on which the yield fee was charged
     * @param token The token in which the yield fee was charged
     * @param amount The amount of the token collected in fees
     */
    event ProtocolYieldFeeCollected(address indexed pool, IERC20 indexed token, uint256 amount);

    /**
     * @notice Logs the withdrawal of protocol fees in a specific token and amount.
     * @param pool The pool from which protocol fees are being withdrawn
     * @param token The token being withdrawn
     * @param recipient The recipient of the funds
     * @param amount The amount of the fee token that was withdrawn
     */
    event ProtocolFeesWithdrawn(address indexed pool, IERC20 indexed token, address indexed recipient, uint256 amount);

    /**
     * @notice Logs the withdrawal of pool creator fees in a specific token and amount.
     * @param pool The pool from which pool creator fees are being withdrawn
     * @param token The token being withdrawn
     * @param recipient The recipient of the funds (the pool creator if permissionless, or another account)
     * @param amount The amount of the fee token that was withdrawn
     */
    event PoolCreatorFeesWithdrawn(
        address indexed pool,
        IERC20 indexed token,
        address indexed recipient,
        uint256 amount
    );

    /**
     * @notice Emitted on pool registration with the initial aggregate swap fee percentage, for off-chain processes.
     * @dev If the pool is registered as protocol fee exempt, this will be zero (until changed). Otherwise, it will
     * equal the current global swap fee percentage.
     *
     * @param pool The pool being registered
     * @param aggregateSwapFeePercentage The initial aggregate swap fee percentage
     */
    event InitialPoolAggregateSwapFeePercentage(address indexed pool, uint256 aggregateSwapFeePercentage);

    /**
     * @notice Emitted on pool registration with the initial aggregate yield fee percentage, for off-chain processes.
     * @dev If the pool is registered as protocol fee exempt, this will be zero (until changed). Otherwise, it will
     * equal the current global yield fee percentage.
     *
     * @param pool The pool being registered
     * @param aggregateYieldFeePercentage The initial aggregate yield fee percentage
     */
    event InitialPoolAggregateYieldFeePercentage(address indexed pool, uint256 aggregateYieldFeePercentage);

    /**
     * @notice Error raised when the protocol swap fee percentage exceeds the maximum allowed value.
     * @dev Note that this is checked for both the global and pool-specific protocol swap fee percentages.
     */
    error ProtocolSwapFeePercentageTooHigh();

    /**
     * @notice Error raised when the protocol yield fee percentage exceeds the maximum allowed value.
     * @dev Note that this is checked for both the global and pool-specific protocol yield fee percentages.
     */
    error ProtocolYieldFeePercentageTooHigh();

    /**
     * @notice Error raised if there is no pool creator on a withdrawal attempt from the given pool.
     * @param pool The pool with no creator
     */
    error PoolCreatorNotRegistered(address pool);

    /**
     * @notice Error raised if the wrong account attempts to withdraw pool creator fees.
     * @param caller The account attempting to withdraw pool creator fees
     * @param pool The pool the caller tried to withdraw from
     */
    error CallerIsNotPoolCreator(address caller, address pool);

    /// @notice Error raised when the pool creator swap or yield fee percentage exceeds the maximum allowed value.
    error PoolCreatorFeePercentageTooHigh();

    /**
     * @notice Get the address of the main Vault contract.
     * @return vault The Vault address
     */
    function vault() external view returns (IVault);

    /**
     * @notice Collects aggregate fees from the Vault for a given pool.
     * @param pool The pool with aggregate fees
     */
    function collectAggregateFees(address pool) external;

    /**
     * @notice Getter for the current global protocol swap fee.
     * @return protocolSwapFeePercentage The global protocol swap fee percentage
     */
    function getGlobalProtocolSwapFeePercentage() external view returns (uint256 protocolSwapFeePercentage);

    /**
     * @notice Getter for the current global protocol yield fee.
     * @return protocolYieldFeePercentage The global protocol yield fee percentage
     */
    function getGlobalProtocolYieldFeePercentage() external view returns (uint256 protocolYieldFeePercentage);

    /**
     * @notice Getter for the current protocol swap fee for a given pool.
     * @param pool The address of the pool
     * @return protocolSwapFeePercentage The global protocol swap fee percentage
     * @return isOverride True if the protocol fee has been overridden
     */
    function getPoolProtocolSwapFeeInfo(
        address pool
    ) external view returns (uint256 protocolSwapFeePercentage, bool isOverride);

    /**
     * @notice Getter for the current protocol yield fee for a given pool.
     * @param pool The address of the pool
     * @return protocolYieldFeePercentage The global protocol yield fee percentage
     * @return isOverride True if the protocol fee has been overridden
     */
    function getPoolProtocolYieldFeeInfo(
        address pool
    ) external view returns (uint256 protocolYieldFeePercentage, bool isOverride);

    /**
     * @notice Returns the amount of each pool token allocated to the protocol for withdrawal.
     * @dev Includes both swap and yield fees.
     * @param pool The address of the pool on which fees were collected
     * @return feeAmounts The total amounts of each token available for withdrawal, sorted in token registration order
     */
    function getProtocolFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts);

    /**
     * @notice Returns the amount of each pool token allocated to the pool creator for withdrawal.
     * @dev Includes both swap and yield fees.
     * @param pool The address of the pool on which fees were collected
     * @return feeAmounts The total amounts of each token available for withdrawal, sorted in token registration order
     */
    function getPoolCreatorFeeAmounts(address pool) external view returns (uint256[] memory feeAmounts);

    /**
     * @notice Returns a calculated aggregate percentage from protocol and pool creator fee percentages.
     * @dev Not tied to any particular pool; this just performs the low-level "additive fee" calculation. Note that
     * pool creator fees are calculated based on creatorAndLpFees, and not in totalFees. Since aggregate fees are
     * stored in the Vault with 24-bit precision, this will truncate any values that require greater precision.
     * It is expected that pool creators will negotiate with the DAO and agree on reasonable values for these fee
     * components, but the truncation ensures it will not revert for any valid set of fee percentages.
     *
     * See example below:
     *
     * tokenOutAmount = 10000; poolSwapFeePct = 10%; protocolFeePct = 40%; creatorFeePct = 60%
     * totalFees = tokenOutAmount * poolSwapFeePct = 10000 * 10% = 1000
     * protocolFees = totalFees * protocolFeePct = 1000 * 40% = 400
     * creatorAndLpFees = totalFees - protocolFees = 1000 - 400 = 600
     * creatorFees = creatorAndLpFees * creatorFeePct = 600 * 60% = 360
     * lpFees (will stay in the pool) = creatorAndLpFees - creatorFees = 600 - 360 = 240
     *
     * @param protocolFeePercentage The protocol portion of the aggregate fee percentage
     * @param poolCreatorFeePercentage The pool creator portion of the aggregate fee percentage
     * @return aggregateFeePercentage The computed aggregate percentage
     */
    function computeAggregateFeePercentage(
        uint256 protocolFeePercentage,
        uint256 poolCreatorFeePercentage
    ) external pure returns (uint256 aggregateFeePercentage);

    /**
     * @notice Override the protocol swap fee percentage for a specific pool.
     * @dev This is a permissionless call, and will set the pool's fee to the current global fee, if it is different
     * from the current value, and the fee is not controlled by governance (i.e., has never been overridden).
     *
     * @param pool The pool for which we are setting the protocol swap fee
     */
    function updateProtocolSwapFeePercentage(address pool) external;

    /**
     * @notice Override the protocol yield fee percentage for a specific pool.
     * @dev This is a permissionless call, and will set the pool's fee to the current global fee, if it is different
     * from the current value, and the fee is not controlled by governance (i.e., has never been overridden).
     *
     * @param pool The pool for which we are setting the protocol yield fee
     */
    function updateProtocolYieldFeePercentage(address pool) external;

    /***************************************************************************
                                Permissioned Functions
    ***************************************************************************/

    /**
     * @notice Add pool-specific entries to the protocol swap and yield percentages.
     * @dev This must be called from the Vault during pool registration. It will initialize the pool to the global
     * protocol fee percentage values (or 0, if the `protocolFeeExempt` flags is set), and return the initial aggregate
     * fee percentages, based on an initial pool creator fee of 0.
     *
     * @param pool The address of the pool being registered
     * @param poolCreator The address of the pool creator (or 0 if there won't be a pool creator fee)
     * @param protocolFeeExempt If true, the pool is initially exempt from protocol fees
     * @return aggregateSwapFeePercentage The initial aggregate swap fee percentage
     * @return aggregateYieldFeePercentage The initial aggregate yield fee percentage
     */
    function registerPool(
        address pool,
        address poolCreator,
        bool protocolFeeExempt
    ) external returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage);

    /**
     * @notice Set the global protocol swap fee percentage, used by standard pools.
     * @param newProtocolSwapFeePercentage The new protocol swap fee percentage
     */
    function setGlobalProtocolSwapFeePercentage(uint256 newProtocolSwapFeePercentage) external;

    /**
     * @notice Set the global protocol yield fee percentage, used by standard pools.
     * @param newProtocolYieldFeePercentage The new protocol yield fee percentage
     */
    function setGlobalProtocolYieldFeePercentage(uint256 newProtocolYieldFeePercentage) external;

    /**
     * @notice Override the protocol swap fee percentage for a specific pool.
     * @param pool The address of the pool for which we are setting the protocol swap fee
     * @param newProtocolSwapFeePercentage The new protocol swap fee percentage for the pool
     */
    function setProtocolSwapFeePercentage(address pool, uint256 newProtocolSwapFeePercentage) external;

    /**
     * @notice Override the protocol yield fee percentage for a specific pool.
     * @param pool The address of the pool for which we are setting the protocol yield fee
     * @param newProtocolYieldFeePercentage The new protocol yield fee percentage for the pool
     */
    function setProtocolYieldFeePercentage(address pool, uint256 newProtocolYieldFeePercentage) external;

    /**
     * @notice Assigns a new pool creator swap fee percentage to the specified pool.
     * @dev Fees are divided between the protocol, pool creator, and LPs. The pool creator percentage is applied to
     * the "net" amount after protocol fees, and divides the remainder between the pool creator and LPs. If the
     * pool creator fee is near 100%, almost none of the fee amount remains in the pool for LPs.
     *
     * @param pool The address of the pool for which the pool creator fee will be changed
     * @param poolCreatorSwapFeePercentage The new pool creator swap fee percentage to apply to the pool
     */
    function setPoolCreatorSwapFeePercentage(address pool, uint256 poolCreatorSwapFeePercentage) external;

    /**
     * @notice Assigns a new pool creator yield fee percentage to the specified pool.
     * @dev Fees are divided between the protocol, pool creator, and LPs. The pool creator percentage is applied to
     * the "net" amount after protocol fees, and divides the remainder between the pool creator and LPs. If the
     * pool creator fee is near 100%, almost none of the fee amount remains in the pool for LPs.
     *
     * @param pool The address of the pool for which the pool creator fee will be changed
     * @param poolCreatorYieldFeePercentage The new pool creator yield fee percentage to apply to the pool
     */
    function setPoolCreatorYieldFeePercentage(address pool, uint256 poolCreatorYieldFeePercentage) external;

    /**
     * @notice Withdraw collected protocol fees for a given pool (all tokens). This is a permissioned function.
     * @dev Sends swap and yield protocol fees to the recipient.
     * @param pool The pool on which fees were collected
     * @param recipient Address to send the tokens
     */
    function withdrawProtocolFees(address pool, address recipient) external;

    /**
     * @notice Withdraw collected protocol fees for a given pool and a given token. This is a permissioned function.
     * @dev Sends swap and yield protocol fees to the recipient.
     * @param pool The pool on which fees were collected
     * @param recipient Address to send the tokens
     * @param token Token to withdraw
     */
    function withdrawProtocolFeesForToken(address pool, address recipient, IERC20 token) external;

    /**
     * @notice Withdraw collected pool creator fees for a given pool. This is a permissioned function.
     * @dev Sends swap and yield pool creator fees to the recipient.
     * @param pool The pool on which fees were collected
     * @param recipient Address to send the tokens
     */
    function withdrawPoolCreatorFees(address pool, address recipient) external;

    /**
     * @notice Withdraw collected pool creator fees for a given pool.
     * @dev Sends swap and yield pool creator fees to the registered poolCreator. Since this is a known and immutable
     * value, this function is permissionless.
     *
     * @param pool The pool on which fees were collected
     */
    function withdrawPoolCreatorFees(address pool) external;
}
