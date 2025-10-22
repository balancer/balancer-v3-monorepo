// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

/**
 * @notice Structure containing Fixed-Price LBP-specific parameters.
 * @dev These parameters are immutable, representing the configuration of a single token sale, running from `startTime`
 * to `endTime`. Swaps may only occur while the sale is active. If `blockProjectTokenSwapsIn` is true, users may only
 * purchase project tokens with the reserve currency.
 *
 * @param owner The account with permission to change the static swap fee percentage
 * @param projectToken The token being sold
 * @param reserveToken The token used to buy the project token (e.g., USDC or WETH)
 * @param startTime The timestamp at the beginning of the sale - initialization/funding must occur before this time
 * @param endTime the timestamp at the end of the sale - withdrawal of proceeds becomes possible after this time
 * @param blockProjectTokenSwapsIn If set, the pool only supports one-way "token distribution"
 */
struct FixedPriceLBPParams {
    address owner;
    IERC20 projectToken;
    IERC20 reserveToken;
    uint256 startTime;
    uint256 endTime;
    bool blockProjectTokenSwapsIn;
    uint256 projectTokenRate;
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
 */
struct FixedPriceLBPoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256 startTime;
    uint256 endTime;
    uint256 projectTokenIndex;
    uint256 reserveTokenIndex;
    bool isProjectTokenSwapInBlocked;
    // Migration parameters (if migrationRouter == address(0), the pool does not support migration).
    address migrationRouter;
    uint256 bptLockDuration;
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
 * @param normalizedWeights Current token weights, sorted in token registration order
 * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
 * @param totalSupply The current total supply of the pool tokens (BPT)
 * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
 * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
 * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
 * @param isSwapEnabled If true, the sale is ongoing, and swaps are enabled (unless the pool is paused)
 */
struct FixedPriceLBPoolDynamicData {
    uint256[] balancesLiveScaled18;
    uint256[] normalizedWeights;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    bool isPoolInitialized;
    bool isPoolPaused;
    bool isPoolInRecoveryMode;
    bool isSwapEnabled;
}

/**
 * @notice Full Fixed-Price LBP interface - base pool plus immutable/dynamic field getters.
 * @dev There is some redundancy here to cover all use cases. Project and reserve tokens can be read directly, if that
 * is all that's needed. Those who already need the more complete data in `FixedPriceLBPoolImmutableData` can recover
 * these values without further calls by indexing into the `tokens` array with `projectTokenIndex` and
 * `reserveTokenIndex`.
 */
interface IFixedPriceLBPool is IBasePool {
    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic LBP parameters
     */
    function getFixedPriceLBPoolDynamicData() external view returns (FixedPriceLBPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable LBP parameters
     */
    function getFixedPriceLBPoolImmutableData() external view returns (FixedPriceLBPoolImmutableData memory data);

    /**
     * @notice Get the project token for this LBP.
     * @dev This is the token being distributed through the sale. It is also available in the immutable data, but this
     * getter is provided as a convenience for those who only need the project token address.
     *
     * @return projectToken The address of the project token
     */
    function getProjectToken() external view returns (IERC20);

    /**
     * @notice Get the reserve token for this LBP.
     * @dev This is the token exchanged for the project token (usually a stablecoin or WETH). It is also available in
     * the immutable data, but this getter is provided as a convenience for those who only need the reserve token
     * address.
     *
     * @return reserveToken The address of the reserve token
     */
    function getReserveToken() external view returns (IERC20);

    /// @notice Get the project token rate (price) in terms of reserve tokens.
    function getProjectTokenRate() external view returns (uint256);
}
