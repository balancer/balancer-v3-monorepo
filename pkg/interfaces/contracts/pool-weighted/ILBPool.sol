// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILBPCommon } from "./ILBPCommon.sol";
import { IVault } from "../vault/IVault.sol";

/**
 * @notice Structure containing LBP-specific parameters.
 * @dev See `LBPCommonParams` in ILBPCommon.sol for general parameters.
 * @param projectTokenStartWeight The project token weight at the start of the sale (normally higher than the reserve)
 * @param reserveTokenStartWeight The reserve token weight at the start of the sale (normally lower than the project)
 * @param projectTokenEndWeight The project token weight at the end of the sale (should go down over time)
 * @param reserveTokenEndWeight The reserve token weight at the end of the sale (should go up over time)
 */
struct LBPParams {
    uint256 projectTokenStartWeight;
    uint256 reserveTokenStartWeight;
    uint256 projectTokenEndWeight;
    uint256 reserveTokenEndWeight;
}

/**
 * @notice Parameters passed down from the factory and passed to the pool on deployment.
 * @param vault The address of the Balancer Vault
 * @param trustedRouter The address of the trusted router (i.e., one that reliably stores the real sender)
 * @param migrationRouter The address of the router used for migration to a Weighted Pool after the sale
 * @param poolVersion The pool version deployed by the factory
 */
struct FactoryParams {
    IVault vault;
    address trustedRouter;
    address migrationRouter;
    string poolVersion;
}

/**
 * @notice Liquidity Bootstrapping Pool data that cannot change after deployment.
 * @param tokens Pool tokens, sorted in token registration order
 * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
 * calculations. FP(1) for 18-decimal tokens
 * @param startTime Timestamp of the start of the sale, when all liquidity is present and swaps are enabled
 * @param endTime Timestamp of the end of the sale, when swaps are disabled, and liquidity can be removed
 * @param projectTokenIndex The index of token (in `tokens`) being distributed through the sale
 * @param reserveTokenIndex The index of the token (in `tokens`) used to purchase project tokens
 * @param isProjectTokenSwapInBlocked If true, it is impossible to sell the project token back into the pool
 * @param startWeights Starting weights for the LBP, sorted in token registration order
 * @param endWeights Ending weights for the LBP, sorted in token registration order
 * @param migrationRouter The address of the router used for migration to a Weighted Pool after the sale
 * @param lockDurationAfterMigration The duration for which the BPT will be locked after migration
 * @param bptPercentageToMigrate The percentage of the BPT to migrate from the LBP to the new weighted pool
 * @param migrationWeightProjectToken The weight of the project token
 * @param migrationWeightReserveToken The weight of the reserve token
 */
struct LBPoolImmutableData {
    // Common LBPool immutable parameters
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256 startTime;
    uint256 endTime;
    uint256 projectTokenIndex;
    uint256 reserveTokenIndex;
    bool isProjectTokenSwapInBlocked;
    // Weighted LBPool specific parameters
    uint256[] startWeights;
    uint256[] endWeights;
    // Migration parameters (if migrationRouter == address(0), the pool does not support migration).
    address migrationRouter;
    uint256 lockDurationAfterMigration;
    uint256 bptPercentageToMigrate;
    uint256 migrationWeightProjectToken;
    uint256 migrationWeightReserveToken;
}

/**
 * @notice Snapshot of current Weighted Pool data that can change.
 * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode. Withdrawals
 * in Recovery Mode do not make external calls (including those necessary for updating live balances), so if
 * there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
 *
 * @param balancesLiveScaled18 18-decimal FP token balances, sorted in token registration order
 * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
 * @param totalSupply The current total supply of the pool tokens (BPT)
 * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
 * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
 * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
 * @param isSwapEnabled If true, the sale is ongoing, and swaps are enabled (unless the pool is paused)
 * @param normalizedWeights Current token weights, sorted in token registration order
 */
struct LBPoolDynamicData {
    // Common LBPool Dynamic Data parameters
    uint256[] balancesLiveScaled18;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool isSwapEnabled;
    // Weighted LBPool specific parameters
    uint256[] normalizedWeights;
}

/// @notice Interface for standard LBPools - base LBP functions, plus immutable/dynamic field getters.
interface ILBPool is ILBPCommon {
    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic LBP parameters
     */
    function getLBPoolDynamicData() external view returns (LBPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable LBP parameters
     */
    function getLBPoolImmutableData() external view returns (LBPoolImmutableData memory data);
}
