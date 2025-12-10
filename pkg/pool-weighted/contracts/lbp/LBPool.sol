// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
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
import { LBPoolLib } from "../lib/LBPoolLib.sol";
import { LBPCommon } from "./LBPCommon.sol";

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

    // Offset applied to reserve token balance in seedless LBPs.
    uint256 private immutable _reserveTokenVirtualBalanceScaled18;
    uint256 private immutable _reserveTokenScalingFactor;

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
        LBPCommon(lbpCommonParams, migrationParams, factoryParams.trustedRouter, migrationParams.migrationRouter)
        WeightedPool(
            _buildWeightedPoolParams(lbpCommonParams, lbpParams, factoryParams.poolVersion),
            factoryParams.vault
        )
    {
        LBPoolLib.verifyWeightUpdateParameters(
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        _projectTokenStartWeight = lbpParams.projectTokenStartWeight;
        _reserveTokenStartWeight = lbpParams.reserveTokenStartWeight;

        _projectTokenEndWeight = lbpParams.projectTokenEndWeight;
        _reserveTokenEndWeight = lbpParams.reserveTokenEndWeight;

        _reserveTokenScalingFactor = _computeScalingFactor(lbpCommonParams.reserveToken);

        // The reserve virtual balance is given in native decimals; scale up to store as scaled18.
        _reserveTokenVirtualBalanceScaled18 = _toScaled18(
            lbpParams.reserveTokenVirtualBalance,
            _reserveTokenScalingFactor
        );

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

        if (_reserveTokenVirtualBalanceScaled18 > 0) {
            data.reserveTokenVirtualBalance = _toRaw(_reserveTokenVirtualBalanceScaled18, _reserveTokenScalingFactor);
        }

        // Migration-related params, non-zero if the pool supports migration.
        data.migrationRouter = _migrationRouter;
        data.lockDurationAfterMigration = _lockDurationAfterMigration;
        data.bptPercentageToMigrate = _bptPercentageToMigrate;
        data.migrationWeightProjectToken = _migrationWeightProjectToken;
        data.migrationWeightReserveToken = _migrationWeightReserveToken;
    }

    /// @inheritdoc ILBPool
    function getReserveTokenVirtualBalance() external view returns (uint256) {
        return _toRaw(_reserveTokenVirtualBalanceScaled18, _reserveTokenScalingFactor);
    }

    /*******************************************************************************
                                    Base Pool Hooks
    *******************************************************************************/

    /**
     * @inheritdoc WeightedPool
     * @notice Implementation of computeInvariant that adjusts for the virtual balance in seedless LBPs.
     * @dev The Vault calls this during liquidity operations.
     */
    function computeInvariant(
        uint256[] memory balancesLiveScaled18,
        Rounding rounding
    ) public view override(IBasePool, WeightedPool) returns (uint256 invariant) {
        // This is not a seedless LBP, fall back on standard Weighted Pool behavior.
        if (_reserveTokenVirtualBalanceScaled18 == 0) {
            return super.computeInvariant(balancesLiveScaled18, rounding);
        }

        return super.computeInvariant(_getEffectiveBalances(balancesLiveScaled18), rounding);
    }

    /// @inheritdoc WeightedPool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) public view override(IBasePool, WeightedPool) returns (uint256 newBalance) {
        if (_reserveTokenVirtualBalanceScaled18 == 0) {
            // This is not a seedless LBP, fall back on standard Weighted Pool behavior.
            newBalance = super.computeBalance(balancesLiveScaled18, tokenInIndex, invariantRatio);
        } else {
            // This is a seedless LBP - use virtual balances.
            newBalance = super.computeBalance(
                _getEffectiveBalances(balancesLiveScaled18),
                tokenInIndex,
                invariantRatio
            );

            // The Vault expects the real balance, so we need to adjust for the virtual balance if this is the reserve.
            // Will underflow if the operation would require a negative real balance.
            if (tokenInIndex == _reserveTokenIndex) {
                newBalance -= _reserveTokenVirtualBalanceScaled18;
            }
        }
    }

    function _getEffectiveBalances(
        uint256[] memory realBalances
    ) internal view returns (uint256[] memory effectiveBalances) {
        effectiveBalances = new uint256[](2);

        effectiveBalances[_projectTokenIndex] = realBalances[_projectTokenIndex];
        effectiveBalances[_reserveTokenIndex] = realBalances[_reserveTokenIndex] + _reserveTokenVirtualBalanceScaled18;
    }

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

        // This is not a seedless LBP, fall back on standard Weighted Pool behavior.
        if (_reserveTokenVirtualBalanceScaled18 == 0) {
            return super.onSwap(request);
        }

        // This is a seedless LBP, modify the request to use the virtual balance.
        PoolSwapParams memory seedlessRequest = PoolSwapParams({
            kind: request.kind,
            amountGivenScaled18: request.amountGivenScaled18,
            balancesScaled18: new uint256[](2), // LBPs are 2-token only
            indexIn: request.indexIn,
            indexOut: request.indexOut,
            router: request.router,
            userData: request.userData
        });
        seedlessRequest.balancesScaled18[_projectTokenIndex] = request.balancesScaled18[_projectTokenIndex];
        seedlessRequest.balancesScaled18[_reserveTokenIndex] =
            request.balancesScaled18[_reserveTokenIndex] +
            _reserveTokenVirtualBalanceScaled18;

        uint256 calculatedAmountScaled18 = super.onSwap(seedlessRequest);

        // If we are returning reserve tokens, ensure we have enough real balance to cover it.
        if (
            request.indexOut == _reserveTokenIndex &&
            calculatedAmountScaled18 > request.balancesScaled18[_reserveTokenIndex]
        ) {
            revert InsufficientRealReserveBalance(
                calculatedAmountScaled18,
                request.balancesScaled18[_reserveTokenIndex]
            );
        }

        return calculatedAmountScaled18;
    }

    /**
     * @inheritdoc LBPCommon
     * @dev Ensure the owner is initializing the pool, and ensure seedless LBPs do not accept reserve tokens.
     * @return success Allow the initialization to proceed if the conditions have been met
     */
    function onBeforeInitialize(
        uint256[] memory exactAmountsIn,
        bytes memory
    ) public view override onlyBeforeSale returns (bool) {
        if (_reserveTokenVirtualBalanceScaled18 > 0) {
            // This is a seedless LBP; ensure the caller is initializing with 0 reserve tokens.
            if (exactAmountsIn[_reserveTokenIndex] > 0) {
                revert SeedlessLBPInitializationWithNonZeroReserve();
            }
        }

        return ISenderGuard(_trustedRouter).getSender() == owner();
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
}
