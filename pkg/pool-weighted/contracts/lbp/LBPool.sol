// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { GradualValueChange } from "../lib/GradualValueChange.sol";
import { WeightedPool } from "../WeightedPool.sol";
import { LBPCommon } from "./LBPCommon.sol";
import { LBPoolLib } from "../lib/LBPoolLib.sol";

/**
 * @notice Weighted Pool with mutable weights, designed to support v3 Liquidity Bootstrapping.
 * @dev Inheriting from WeightedPool is only slightly wasteful (setting 2 immutable weights and `_totalTokens`,
 * which will not be used later), and it is tremendously helpful for pool validation and any potential future
 * base contract changes.
 */
contract LBPool is ILBPool, LBPCommon, WeightedPool {
    // The sale parameters are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    uint256 private immutable _projectTokenStartWeight;
    uint256 private immutable _reserveTokenStartWeight;
    uint256 private immutable _projectTokenEndWeight;
    uint256 private immutable _reserveTokenEndWeight;

    /**
     * @notice Event emitted when a standard weighted LBPool is deployed.
     * @dev The common factory emits LBPoolCreated (with the pool address and project/reserve tokens). This event gives
     * more detail on this specific LBP configuration. The pool also emits a `GradualWeightUpdateScheduled` event with
     * the starting and ending times and weights.
     *
     * @param owner Address of the pool's owner
     * @param blockProjectTokenSwapsIn If true, this is a "buy-only" sale
     * @param hasMigration True if the pool will be migrated after the sale
     */
    event WeightedLBPoolCreated(address indexed owner, bool blockProjectTokenSwapsIn, bool hasMigration);

    /**
     * @notice Emitted on deployment to record the sale parameters.
     * @param startTime The starting timestamp of the update
     * @param endTime  The ending timestamp of the update
     * @param startWeights The weights at the start of the update
     * @param endWeights The final weights after the update is completed
     */
    event GradualWeightUpdateScheduled(
        uint256 startTime,
        uint256 endTime,
        uint256[] startWeights,
        uint256[] endWeights
    );

    /// @notice LBPs are WeightedPools by inheritance, but WeightedPool immutable/dynamic getters are wrong for LBPs.
    error NotImplemented();

    constructor(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        LBPParams memory lbpParams,
        FactoryParams memory factoryParams
    )
        LBPCommon(
            _buildLBPCommonParams(lbpCommonParams, lbpParams), // May adjust startTime as a side effect
            migrationParams,
            factoryParams.trustedRouter,
            factoryParams.migrationRouter
        )
        WeightedPool(
            _buildWeightedPoolParams(lbpCommonParams, lbpParams, factoryParams.poolVersion),
            factoryParams.vault
        )
    {
        _projectTokenStartWeight = lbpParams.projectTokenStartWeight;
        _reserveTokenStartWeight = lbpParams.reserveTokenStartWeight;

        _projectTokenEndWeight = lbpParams.projectTokenEndWeight;
        _reserveTokenEndWeight = lbpParams.reserveTokenEndWeight;

        // Preserve event compatibility with previous LBP versions.
        uint256[] memory startWeights = new uint256[](_TWO_TOKENS);
        uint256[] memory endWeights = new uint256[](_TWO_TOKENS);
        (startWeights[_projectTokenIndex], startWeights[_reserveTokenIndex]) = (
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight
        );
        (endWeights[_projectTokenIndex], endWeights[_reserveTokenIndex]) = (
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        bool hasMigration = factoryParams.migrationRouter != address(0);

        emit WeightedLBPoolCreated(lbpCommonParams.owner, lbpCommonParams.blockProjectTokenSwapsIn, hasMigration);

        emit GradualWeightUpdateScheduled(_startTime, _endTime, startWeights, endWeights);
    }

    /// @inheritdoc ILBPool
    function getGradualWeightUpdateParams()
        public
        view
        returns (uint256 startTime, uint256 endTime, uint256[] memory startWeights, uint256[] memory endWeights)
    {
        startTime = _startTime;
        endTime = _endTime;

        startWeights = new uint256[](_TWO_TOKENS);
        (startWeights[_projectTokenIndex], startWeights[_reserveTokenIndex]) = (
            _projectTokenStartWeight,
            _reserveTokenStartWeight
        );

        endWeights = new uint256[](_TWO_TOKENS);
        (endWeights[_projectTokenIndex], endWeights[_reserveTokenIndex]) = (
            _projectTokenEndWeight,
            _reserveTokenEndWeight
        );
    }

    /**
     * @notice Not implemented; reverts unconditionally.
     * @dev This is because the LBP dynamic data also includes the weights, so overriding this would be incomplete
     * and potentially misleading.
     */
    function getWeightedPoolDynamicData() external pure override returns (WeightedPoolDynamicData memory) {
        revert NotImplemented();
    }

    /**
     * @notice Not implemented; reverts unconditionally.
     * @dev This is because in the standard Weighted Pool, weights are included in the immutable data. In the LBP,
     * weights can change, so they are instead part of the dynamic data.
     */
    function getWeightedPoolImmutableData() external pure override returns (WeightedPoolImmutableData memory) {
        revert NotImplemented();
    }

    /// @inheritdoc ILBPool
    function getLBPoolDynamicData() external view override returns (LBPoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        data.normalizedWeights = _getNormalizedWeights();
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
        data.isSwapEnabled = _isSwapEnabled();
    }

    /// @inheritdoc ILBPool
    function getLBPoolImmutableData() external view override returns (LBPoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        data.projectTokenIndex = _projectTokenIndex;
        data.reserveTokenIndex = _reserveTokenIndex;

        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.isProjectTokenSwapInBlocked = _blockProjectTokenSwapsIn;
        data.startTime = _startTime;
        data.endTime = _endTime;

        data.startWeights = new uint256[](_TWO_TOKENS);
        data.startWeights[_projectTokenIndex] = _projectTokenStartWeight;
        data.startWeights[_reserveTokenIndex] = _reserveTokenStartWeight;

        data.endWeights = new uint256[](_TWO_TOKENS);
        data.endWeights[_projectTokenIndex] = _projectTokenEndWeight;
        data.endWeights[_reserveTokenIndex] = _reserveTokenEndWeight;

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

    /// @inheritdoc WeightedPool
    function onSwap(PoolSwapParams memory request) public view override(IBasePool, WeightedPool) returns (uint256) {
        // Block if the sale has not started or has ended.
        if (_isSwapEnabled() == false) {
            revert SwapsDisabled();
        }

        // If project token swaps are blocked, project token must be the token out.
        if (_blockProjectTokenSwapsIn && request.indexOut != _projectTokenIndex) {
            revert SwapOfProjectTokenIn();
        }

        return super.onSwap(request);
    }

    /*******************************************************************************
                                  Internal Functions
    *******************************************************************************/

    function _getNormalizedWeight(uint256 tokenIndex) internal view override returns (uint256) {
        if (tokenIndex < _TWO_TOKENS) {
            return _getNormalizedWeights()[tokenIndex];
        }

        revert IVaultErrors.InvalidToken();
    }

    function _getNormalizedWeights() internal view override returns (uint256[] memory) {
        uint256[] memory normalizedWeights = new uint256[](_TWO_TOKENS);
        normalizedWeights[_projectTokenIndex] = _getProjectTokenNormalizedWeight();
        normalizedWeights[_reserveTokenIndex] = FixedPoint.ONE - normalizedWeights[_projectTokenIndex];

        return normalizedWeights;
    }

    function _getProjectTokenNormalizedWeight() internal view returns (uint256) {
        uint256 pctProgress = GradualValueChange.calculateValueChangeProgress(_startTime, _endTime);

        return GradualValueChange.interpolateValue(_projectTokenStartWeight, _projectTokenEndWeight, pctProgress);
    }

    // Build the required struct for initializing the underlying WeightedPool. Called on construction.
    function _buildWeightedPoolParams(
        LBPCommonParams memory lbpCommonParams,
        LBPParams memory lbpParams,
        string memory poolVersion
    ) private pure returns (NewPoolParams memory) {
        (uint256 projectTokenIndex, uint256 reserveTokenIndex) = lbpCommonParams.projectToken <
            lbpCommonParams.reserveToken
            ? (0, 1)
            : (1, 0);

        uint256[] memory normalizedWeights = new uint256[](_TWO_TOKENS);
        normalizedWeights[projectTokenIndex] = lbpParams.projectTokenStartWeight;
        normalizedWeights[reserveTokenIndex] = lbpParams.reserveTokenStartWeight;

        // The WeightedPool will validate the starting weights (i.e., ensure they respect the minimum and sum to ONE).
        return
            NewPoolParams({
                name: lbpCommonParams.name,
                symbol: lbpCommonParams.symbol,
                numTokens: _TWO_TOKENS,
                normalizedWeights: normalizedWeights,
                version: poolVersion
            });
    }

    // Build and validate LBPCommonParams for initializing LBPCommon. Called on construction.
    // Validates weights and adjusts startTime if needed.
    function _buildLBPCommonParams(
        LBPCommonParams memory lbpCommonParams,
        LBPParams memory lbpParams
    ) private view returns (LBPCommonParams memory finalCommonParams) {
        finalCommonParams = lbpCommonParams;

        // Checks that the weights are valid and `endTime` is after `startTime`. If `startTime` is in the past,
        // avoid abrupt weight changes by overriding it with the current block time.
        finalCommonParams.startTime = LBPoolLib.verifyWeightUpdateParameters(
            lbpCommonParams.startTime,
            lbpCommonParams.endTime,
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );
    }
}
