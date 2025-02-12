// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICowPool {
    /**
     * @notice CoW Pool data that cannot change after deployment.
     * @param tokens Pool tokens, sorted in token registration order
     * @param decimalScalingFactors Conversion factor used to adjust for token decimals for uniform precision in
     * calculations. FP(1) for 18-decimal tokens
     * @param normalizedWeights The token weights, sorted in token registration order
     */
    struct CoWPoolImmutableData {
        IERC20[] tokens;
        uint256[] decimalScalingFactors;
        uint256[] normalizedWeights;
    }

    /**
     * @notice Snapshot of current CoW Pool data that can change.
     * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode. Withdrawals
     * in Recovery Mode do not make external calls (including those necessary for updating live balances), so if
     * there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
     *
     * @param balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
     * @param tokenRates 18-decimal FP values for rate tokens (e.g., yield-bearing), or FP(1) for standard tokens
     * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage
     * @param totalSupply The current total supply of the pool tokens (BPT)
     * @param trustedCowRouter The address of the trusted CoW Router
     * @param isPoolInitialized If false, the pool has not been seeded with initial liquidity, so operations will revert
     * @param isPoolPaused If true, the pool is paused, and all non-recovery-mode state-changing operations will revert
     * @param isPoolInRecoveryMode If true, Recovery Mode withdrawals are enabled, and live balances may be inaccurate
     */
    struct CoWPoolDynamicData {
        uint256[] balancesLiveScaled18;
        uint256[] tokenRates;
        uint256 staticSwapFeePercentage;
        uint256 totalSupply;
        address trustedCowRouter;
        bool isPoolInitialized;
        bool isPoolPaused;
        bool isPoolInRecoveryMode;
    }

    /**
     * @notice Trusted CoW Router has been refreshed from the pool factory.
     * @param newTrustedCowRouter The current trusted router address in the CoW pool factory
     */
    event CowTrustedRouterChanged(address newTrustedCowRouter);

    /**
     * @notice Get dynamic pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all dynamic CoW pool parameters
     */
    function getCowPoolDynamicData() external view returns (CoWPoolDynamicData memory data);

    /**
     * @notice Get immutable pool data relevant to swap/add/remove calculations.
     * @return data A struct containing all immutable CoW pool parameters
     */
    function getCowPoolImmutableData() external view returns (CoWPoolImmutableData memory data);

    /**
     * @notice Returns the trusted router address.
     * @dev The CoW Router address is registered in the factory. To minimize external calls from the pool to the
     * factory, the trusted router address is cached within the pool. This variable has no setter; therefore, updating
     * it requires calling `refreshTrustedCowRouter()`.
     * @return cowRouter The address of the trusted CoW Router
     */
    function getTrustedCowRouter() external view returns (address cowRouter);

    /// @notice Updates this pool's trusted router address to the current value in the CoW AMM Factory.
    function refreshTrustedCowRouter() external;
}
