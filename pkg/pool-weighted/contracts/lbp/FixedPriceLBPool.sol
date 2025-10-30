// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";

import { GradualValueChange } from "../lib/GradualValueChange.sol";
import { LBPCommon } from "./LBPCommon.sol";

/**
 * @notice Fixed-price Liquidity Bootstrapping Pool for token sales at a constant rate.
 * @dev Unlike traditional LBPs with changing weights, this pool maintains a constant exchange rate throughout the sale
 * period. The pool uses a simple x + y invariant corresponding to the total value in terms of the reserve token (i.e,
 * token balance * rate + reserve). This avoids the complexity and gas cost of weight adjustments, while still
 * benefiting from Balancer's vault infrastructure.
 *
 * If created as "buy only" - with `blockProjectTokenSwapsIn` set to true - it is "seedless," and must be initialized
 * with only project tokens.
 *
 * Key features:
 * - Constant price throughout the sale period
 * - Simple swap math: multiply or divide by the fixed rate
 * - Simple constant sum invariant: inv = projectBalance * projectTokenRate + reserveBalance
 * - No reserve tokens required on initialization for "buy only" sales
 */
contract FixedPriceLBPool is IFixedPriceLBPool, LBPCommon, BalancerPoolToken, PoolInfo, Version {
    using FixedPoint for uint256;

    // Fees are 18-decimal, floating point values, which will be stored in the Vault using 24 bits.
    // This means they have 0.00001% resolution (i.e., any non-zero bits < 1e11 will cause precision loss).
    // Since this doesn't use WeightedMath, we don't need a minimum swap fee to keep the math well-behaved.
    // Maximum values protect users by preventing permissioned actors from setting excessively high swap fees.
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 0;
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    /**
     * @notice Rate bounds derived from historical LBP data (50+ completed token sales from Fjord).
     * @dev Observed range: $0.032 to $5.37 per token (rates: 3.2e16 to 5.37e18).
     * MIN allows tokens as cheap as $0.0001 (0.01 cent) - 100x below observed minimum.
     * MAX allows tokens as expensive as $10,000 - ~2000x above observed maximum.
     * These bounds prevent configuration errors while remaining flexible for legitimate use cases.
     */
    uint256 private constant _MIN_RATE = FixedPoint.ONE / 10_000;
    uint256 private constant _MAX_RATE = FixedPoint.ONE * 10_000;

    // Tolerance for initialization balance validation in the buy/sell case.
    uint256 private constant _INITIALIZATION_TOLERANCE = 10e16; // 10%

    /**
     * @notice The fixed exchange rate between project and reserve tokens (18 decimals).
     * @dev This represents how many reserve tokens equal one project token.
     * For example, if 1 PROJECT = 4 USDC, then _projectTokenRate = 4e18.
     */
    uint256 private immutable _projectTokenRate;

    /**
     * @notice Event emitted when a fixed price LBP is deployed.
     * @dev The common factory emits LBPoolCreated (with the pool address and project/reserve tokens). This event gives
     * more detail on this specific LBP configuration.
     *
     * @param owner Address of the pool's owner
     * @param projectTokenRate The project token price in terms of the reserve token
     * @param blockProjectTokenSwapsIn If true, this is a "buy-only" sale
     * @param hasMigration True if the pool will be migrated after the sale
     */
    event FixedPriceLBPoolCreated(
        address indexed owner,
        uint256 projectTokenRate,
        bool blockProjectTokenSwapsIn,
        bool hasMigration
    );

    /// @notice The initialization amounts do not match the expected ratio based on the fixed rate.
    error UnbalancedInitialization();

    /// @notice An initialization amount is invalid (e.g., zero token balance, or non-zero reserve in buy-only mode).
    error InvalidInitializationAmount();

    /// @notice The provided rate is below the minimum allowed rate.
    /// @param actualRate The rate provided on creation
    /// @param minimumRate The minimum allowed rate
    error ProjectTokenRateTooLow(uint256 actualRate, uint256 minimumRate);

    /// @notice The provided rate is above the maximum allowed rate.
    /// @param actualRate The rate provided on creation
    /// @param maximumRate The maximum allowed rate
    error ProjectTokenRateTooHigh(uint256 actualRate, uint256 maximumRate);

    constructor(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        FixedPriceLBPParams memory lbpParams,
        FactoryParams memory factoryParams
    )
        // `buildLBPCommonParams` may adjust startTime as a side effect.
        LBPCommon(
            _buildLBPCommonParams(lbpCommonParams),
            migrationParams,
            factoryParams.trustedRouter,
            factoryParams.migrationRouter
        )
        BalancerPoolToken(factoryParams.vault, lbpCommonParams.name, lbpCommonParams.symbol)
        PoolInfo(factoryParams.vault)
        Version(factoryParams.poolVersion)
    {
        // Validate the rate is within acceptable bounds based on historical LBP data.
        if (lbpParams.projectTokenRate < _MIN_RATE) {
            revert ProjectTokenRateTooLow(lbpParams.projectTokenRate, _MIN_RATE);
        }
        if (lbpParams.projectTokenRate > _MAX_RATE) {
            revert ProjectTokenRateTooHigh(lbpParams.projectTokenRate, _MAX_RATE);
        }

        bool hasMigration = migrationParams.bptPercentageToMigrate != 0;

        emit FixedPriceLBPoolCreated(
            lbpCommonParams.owner,
            lbpParams.projectTokenRate,
            lbpCommonParams.blockProjectTokenSwapsIn,
            hasMigration
        );
    }

    /// @inheritdoc IFixedPriceLBPool
    function getProjectTokenRate() external view returns (uint256) {
        return _projectTokenRate;
    }

    /// @inheritdoc IFixedPriceLBPool
    function getFixedPriceLBPoolDynamicData() external view returns (FixedPriceLBPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
        data.isSwapEnabled = _isSwapEnabled();
    }

    /// @inheritdoc IFixedPriceLBPool
    function getFixedPriceLBPoolImmutableData() external view returns (FixedPriceLBPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        data.projectTokenIndex = _projectTokenIndex;
        data.reserveTokenIndex = _reserveTokenIndex;

        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.isProjectTokenSwapInBlocked = _blockProjectTokenSwapsIn;
        data.startTime = _startTime;
        data.endTime = _endTime;

        data.projectTokenRate = _projectTokenRate;

        // Migration-related params, non-zero if the pool supports migration.
        data.migrationRouter = _migrationRouter;
        data.lockDurationAfterMigration = _lockDurationAfterMigration;
        data.bptPercentageToMigrate = _bptPercentageToMigrate;
        data.migrationWeightProjectToken = _migrationWeightProjectToken;
        data.migrationWeightReserveToken = _migrationWeightReserveToken;
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view override returns (uint256 amountCalculatedScaled18) {
        // Block if the sale has not started or has ended.
        if (_isSwapEnabled() == false) {
            revert SwapsDisabled();
        }

        // If project token swaps are blocked, project token must be the token out.
        if (_blockProjectTokenSwapsIn && request.indexOut != _projectTokenIndex) {
            revert SwapOfProjectTokenIn();
        }

        // Determine whether we're buying or selling project tokens
        bool buyingProjectToken = request.indexIn == _reserveTokenIndex;

        if (request.kind == SwapKind.EXACT_IN) {
            // Calculated amount is amount out; round down to favor the Vault.
            // When buying project (reserve in): amountOut = amountIn / rate
            // When selling project (project in): amountOut = amountIn * rate
            amountCalculatedScaled18 = buyingProjectToken
                ? request.amountGivenScaled18.divDown(_projectTokenRate)
                : request.amountGivenScaled18.mulDown(_projectTokenRate);
        } else {
            // Calculated amount is amount in; round up to favor the Vault.
            // When buying project (reserve in): amountIn = amountOut * rate
            // When selling project (project in): amountIn = amountOut / rate
            amountCalculatedScaled18 = buyingProjectToken
                ? request.amountGivenScaled18.mulUp(_projectTokenRate)
                : request.amountGivenScaled18.divUp(_projectTokenRate);
        }
    }

    /**
     * @notice Compute the pool invariant.
     * @dev The invariant is: inv = projectBalance * projectTokenRate + reserveBalance.
     * This represents the total value in the pool, in terms of reserve tokens.
     *
     * @param balances The current pool balances (in 18-decimal scaling)
     * @param rounding The rounding direction (up or down)
     * @return invariant The calculated invariant value
     */
    function computeInvariant(uint256[] memory balances, Rounding rounding) public view returns (uint256 invariant) {
        // inv = projectBalance * rate + reserveBalance
        uint256 projectTokenValue = rounding == Rounding.ROUND_UP
            ? balances[_projectTokenIndex].mulUp(_projectTokenRate)
            : balances[_projectTokenIndex].mulDown(_projectTokenRate);

        invariant = projectTokenValue + balances[_reserveTokenIndex];
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balances,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance) {
        // Calculate the current invariant, rounding up to favor the Vault.
        uint256 invariant = computeInvariant(balances, Rounding.ROUND_UP);

        if (tokenInIndex == _projectTokenIndex) {
            // Solve for project token: projectBalance = (inv - reserveBalance) / rate.
            // Round up to favor the pool (require more tokens in).AddLiquidityParams
            newBalance = (invariant - balances[_reserveTokenIndex]).divUp(_projectTokenRate);
        } else {
            // Solve for reserve token: reserveBalance = inv - (projectBalance * rate).
            // Round up to favor the pool (require more tokens in).
            uint256 projectTokenValue = balances[_projectTokenIndex].mulDown(_projectTokenRate);
            newBalance = invariant - projectTokenValue;
        }

        // Apply invariant ratio for proportional operations.
        // When adding liquidity proportionally, invariantRatio > FixedPoint.ONE.
        // When removing liquidity proportionally, invariantRatio < FixedPoint.ONE.
        newBalance = newBalance.mulUp(invariantRatio);
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    /**
     * @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
     * @dev Since this pool only allows balanced liquidity operations (owner adds before sale, anyone removes after),
     * unbalanced operations should never occur. We return extreme bounds to indicate this.
     */
    function getMinimumInvariantRatio() external pure returns (uint256) {
        // No minimum - unbalanced adds are blocked by hooks anyway
        return 0;
    }

    /**
     * @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
     * @dev Since this pool only allows balanced liquidity operations (owner adds before sale, anyone removes after),
     * unbalanced operations should never occur. We return extreme bounds to indicate this.
     */
    function getMaximumInvariantRatio() external pure returns (uint256) {
        // No maximum - unbalanced adds are blocked by hooks anyway
        return type(uint256).max;
    }

    /*******************************************************************************
                                      Pool Hooks
    *******************************************************************************/

    /**
     * @notice Block initialization if the sale has already started, verify sender, and validate amounts.
     * @dev Take care to set the start time far enough in advance to allow for funding; otherwise the pool will remain
     * unfunded and need to be redeployed. Note that initialization does not pass the router address, so we cannot
     * directly check that here, though there has to be a call on the trusted router for its `getSender` to be
     * non-zero.
     *
     * @param exactAmountsInScaled18 The amounts being used to initialize the pool (18-decimal scaled)
     * @return success Always true: allow the initialization to proceed if all conditions have been met
     */
    function onBeforeInitialize(
        uint256[] memory exactAmountsInScaled18,
        bytes memory
    ) public view override onlyBeforeSale returns (bool) {
        // Verify the sender is the owner through the trusted router
        if (ISenderGuard(_trustedRouter).getSender() != owner()) {
            return false;
        }

        // Validate the initialization amounts are reasonable given the rate
        _validateInitializationAmounts(exactAmountsInScaled18);

        return true;
    }

    /**
     * @notice Validate that initialization amounts are appropriate for the pool configuration.
     * @dev For one-way pools (blockProjectTokenSwapsIn=true), only project tokens are required since
     * reserve tokens only flow IN through swaps. For two-way pools, both tokens are required and must
     * match the expected ratio within tolerance.
     *
     * @param amountsScaled18 The scaled initialization amounts
     */
    function _validateInitializationAmounts(uint256[] memory amountsScaled18) private view {
        uint256 projectAmount = amountsScaled18[_projectTokenIndex];
        uint256 reserveAmount = amountsScaled18[_reserveTokenIndex];

        if (_blockProjectTokenSwapsIn) {
            // One-way pool: only buying project tokens with reserve.
            // Therefore, there is no point adding reserve tokens, as they will never be tokenOut in a swap.
            // This is a form of "seedless" LBP; easy because the math is very simple.
            if (projectAmount == 0 || reserveAmount != 0) {
                revert InvalidInitializationAmount();
            }
        } else {
            // Two-way pool: both directions allowed.
            // Both tokens required and must approximately match the expected ratio.
            if (projectAmount == 0 || reserveAmount == 0) {
                revert InvalidInitializationAmount();
            }

            // Calculate the expected reserve amount based on the project amount and rate.
            // expectedReserve = projectAmount * rate.
            uint256 expectedReserve = projectAmount.mulDown(_projectTokenRate);

            // This accounts for decimal precision and gives the owner some flexibility
            uint256 minReserve = expectedReserve.mulDown(FixedPoint.ONE - _INITIALIZATION_TOLERANCE);
            uint256 maxReserve = expectedReserve.mulUp(FixedPoint.ONE + _INITIALIZATION_TOLERANCE);

            // Verify the actual reserve amount is within tolerance
            if (reserveAmount < minReserve || reserveAmount > maxReserve) {
                revert UnbalancedInitialization();
            }
        }
    }

    // Build and validate LBPCommonParams for initializing LBPCommon. Called on construction.
    function _buildLBPCommonParams(
        LBPCommonParams memory lbpCommonParams
    ) private view returns (LBPCommonParams memory finalCommonParams) {
        finalCommonParams = lbpCommonParams;

        // Checks that `endTime` is after `startTime`. If `startTime` is in the past, override it with the current
        // block time for consistency.
        finalCommonParams.startTime = GradualValueChange.resolveStartTime(
            lbpCommonParams.startTime,
            lbpCommonParams.endTime
        );
    }
}
