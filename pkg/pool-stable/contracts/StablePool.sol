// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    IUnbalancedLiquidityInvariantRatioBounds
} from "@balancer-labs/v3-interfaces/contracts/vault/IUnbalancedLiquidityInvariantRatioBounds.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    IStablePool,
    StablePoolDynamicData,
    StablePoolImmutableData,
    AmplificationState
} from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolAuthentication } from "@balancer-labs/v3-pool-utils/contracts/BasePoolAuthentication.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { PoolInfo } from "@balancer-labs/v3-pool-utils/contracts/PoolInfo.sol";

/**
 * @notice Standard Balancer Stable Pool.
 * @dev Stable Pools are designed for assets that are either expected to consistently swap at near parity,
 * or at a known exchange rate. Stable Pools use `StableMath` (based on StableSwap, popularized by Curve),
 * which allows for swaps of significant size before encountering substantial price impact, vastly
 * increasing capital efficiency for like-kind and correlated-kind swaps.
 *
 * The `amplificationParameter` determines the "flatness" of the price curve. Higher values "flatten" the
 * curve, meaning there is a larger range of balances over which tokens will trade near parity, with very low
 * slippage. Generally, the `amplificationParameter` can be higher for tokens with lower volatility, and pools
 * with higher liquidity. Lower values more closely approximate the "weighted" math curve, handling greater
 * volatility at the cost of higher slippage. This parameter can be changed through permissioned calls
 * (see below for details).
 *
 * The swap fee percentage is bounded by minimum and maximum values (same as were used in v2).
 */
contract StablePool is IStablePool, BalancerPoolToken, BasePoolAuthentication, PoolInfo, Version {
    using FixedPoint for uint256;
    using SafeCast for *;

    // This contract uses timestamps to slowly update its Amplification parameter over time. These changes must occur
    // over a minimum time period much larger than the block time, making timestamp manipulation a non-issue.
    // solhint-disable not-rely-on-time

    // Amplification factor changes must happen over a minimum period of one day, and can at most divide or multiple the
    // current value by 2 every day.
    // WARNING: this only limits *a single* amplification change to have a maximum rate of change of twice the original
    // value daily. It is possible to perform multiple amplification changes in sequence to increase this value more
    // rapidly: for example, by doubling the value every day it can increase by a factor of 8 over three days (2^3).
    uint256 private constant _MIN_UPDATE_TIME = 1 days;
    uint256 private constant _MAX_AMP_UPDATE_DAILY_RATE = 2;

    // Fees are 18-decimal, floating point values, which will be stored in the Vault using 24 bits.
    // This means they have 0.00001% resolution (i.e., any non-zero bits < 1e11 will cause precision loss).
    // Minimum values help make the math well-behaved (i.e., the swap fee should overwhelm any rounding error).
    // Maximum values protect users by preventing permissioned actors from setting excessively high swap fees.
    uint256 private constant _MIN_SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%
    uint256 private constant _MAX_SWAP_FEE_PERCENTAGE = 10e16; // 10%

    /// @notice Store amplification state.
    AmplificationState private _amplificationState;

    /**
     * @notice An amplification update has started.
     * @param startValue Starting value of the amplification parameter
     * @param endValue Ending value of the amplification parameter
     * @param startTime Timestamp when the update starts
     * @param endTime Timestamp when the update is complete
     */
    event AmpUpdateStarted(uint256 startValue, uint256 endValue, uint256 startTime, uint256 endTime);

    /**
     * @notice An amplification update has been stopped.
     * @param currentValue The value at which it stopped
     */
    event AmpUpdateStopped(uint256 currentValue);

    /// @notice The amplification factor is below the minimum of the range (1 - 5000).
    error AmplificationFactorTooLow();

    /// @notice The amplification factor is above the maximum of the range (1 - 5000).
    error AmplificationFactorTooHigh();

    /// @notice The amplification change duration is too short.
    error AmpUpdateDurationTooShort();

    /// @notice The amplification change rate is too fast.
    error AmpUpdateRateTooFast();

    /// @notice Amplification update operations must be done one at a time.
    error AmpUpdateAlreadyStarted();

    /// @notice Cannot stop an amplification update before it starts.
    error AmpUpdateNotStarted();

    /**
     * @notice Parameters used to deploy a new Stable Pool.
     * @param name ERC20 token name
     * @param symbol ERC20 token symbol
     * @param amplificationParameter Controls the "flatness" of the invariant curve. higher values = lower slippage,
     * and assumes prices are near parity. lower values = closer to the constant product curve (e.g., more like a
     * weighted pool). This has higher slippage, and accommodates greater price volatility
     * @param version The stable pool version
     */
    struct NewPoolParams {
        string name;
        string symbol;
        uint256 amplificationParameter;
        string version;
    }

    constructor(
        NewPoolParams memory params,
        IVault vault
    )
        BalancerPoolToken(vault, params.name, params.symbol)
        BasePoolAuthentication(vault, msg.sender)
        PoolInfo(vault)
        Version(params.version)
    {
        if (params.amplificationParameter < StableMath.MIN_AMP) {
            revert AmplificationFactorTooLow();
        }
        if (params.amplificationParameter > StableMath.MAX_AMP) {
            revert AmplificationFactorTooHigh();
        }

        uint256 initialAmp = params.amplificationParameter * StableMath.AMP_PRECISION;
        _stopAmplification(initialAmp);
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18, Rounding rounding) public view returns (uint256) {
        (uint256 currentAmp, ) = _getAmplificationParameter();

        uint256 invariant = StableMath.computeInvariant(currentAmp, balancesLiveScaled18);
        if (invariant > 0) {
            invariant = rounding == Rounding.ROUND_DOWN ? invariant : invariant + 1;
        }

        return invariant;
    }

    /// @inheritdoc IBasePool
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance) {
        (uint256 currentAmp, ) = _getAmplificationParameter();

        return
            StableMath.computeBalance(
                currentAmp,
                balancesLiveScaled18,
                computeInvariant(balancesLiveScaled18, Rounding.ROUND_UP).mulUp(invariantRatio),
                tokenInIndex
            );
    }

    /// @inheritdoc IBasePool
    function onSwap(PoolSwapParams memory request) public view virtual returns (uint256) {
        uint256 invariant = computeInvariant(request.balancesScaled18, Rounding.ROUND_DOWN);
        (uint256 currentAmp, ) = _getAmplificationParameter();

        if (request.kind == SwapKind.EXACT_IN) {
            uint256 amountOutScaled18 = StableMath.computeOutGivenExactIn(
                currentAmp,
                request.balancesScaled18,
                request.indexIn,
                request.indexOut,
                request.amountGivenScaled18,
                invariant
            );

            return amountOutScaled18;
        } else {
            uint256 amountInScaled18 = StableMath.computeInGivenExactOut(
                currentAmp,
                request.balancesScaled18,
                request.indexIn,
                request.indexOut,
                request.amountGivenScaled18,
                invariant
            );

            return amountInScaled18;
        }
    }

    /// @inheritdoc IStablePool
    function startAmplificationParameterUpdate(uint256 rawEndValue, uint256 endTime) external authenticate {
        if (rawEndValue < StableMath.MIN_AMP) {
            revert AmplificationFactorTooLow();
        }
        if (rawEndValue > StableMath.MAX_AMP) {
            revert AmplificationFactorTooHigh();
        }

        uint256 duration = endTime - block.timestamp;
        if (duration < _MIN_UPDATE_TIME) {
            revert AmpUpdateDurationTooShort();
        }

        (uint256 currentValue, bool isUpdating) = _getAmplificationParameter();
        if (isUpdating) {
            revert AmpUpdateAlreadyStarted();
        }

        uint256 endValue = rawEndValue * StableMath.AMP_PRECISION;

        // daily rate = (endValue / currentValue) / duration * 1 day
        // We perform all multiplications first to not reduce precision, and round the division up as we want to avoid
        // large rates. Note that these are regular integer multiplications and divisions, not fixed point.
        uint256 dailyRate = endValue > currentValue
            ? (endValue * 1 days).divUpRaw(currentValue * duration)
            : (currentValue * 1 days).divUpRaw(endValue * duration);

        if (dailyRate > _MAX_AMP_UPDATE_DAILY_RATE) {
            revert AmpUpdateRateTooFast();
        }

        // Values are 18 decimal floating point, which fits in 64 bits. Timestamps are 32 bits.
        uint64 currentValueUint64 = currentValue.toUint64();
        uint64 endValueUint64 = endValue.toUint64();
        uint32 startTimeUint32 = block.timestamp.toUint32();
        uint32 endTimeUint32 = endTime.toUint32();

        _amplificationState.startValue = currentValueUint64;
        _amplificationState.endValue = endValueUint64;
        _amplificationState.startTime = startTimeUint32;
        _amplificationState.endTime = endTimeUint32;

        emit AmpUpdateStarted(currentValueUint64, endValueUint64, startTimeUint32, endTimeUint32);
        _vault.emitAuxiliaryEvent(
            "AmpUpdateStarted",
            abi.encode(currentValueUint64, endValueUint64, startTimeUint32, endTimeUint32)
        );
    }

    /// @inheritdoc IStablePool
    function stopAmplificationParameterUpdate() external authenticate {
        (uint256 currentValue, bool isUpdating) = _getAmplificationParameter();

        if (isUpdating == false) {
            revert AmpUpdateNotStarted();
        }

        _stopAmplification(currentValue);
        _vault.emitAuxiliaryEvent("AmpUpdateStopped", abi.encode(currentValue));
    }

    /// @inheritdoc IStablePool
    function getAmplificationParameter() external view returns (uint256 value, bool isUpdating, uint256 precision) {
        (value, isUpdating) = _getAmplificationParameter();
        precision = StableMath.AMP_PRECISION;
    }

    /// @inheritdoc IStablePool
    function getAmplificationState()
        external
        view
        returns (AmplificationState memory amplificationState, uint256 precision)
    {
        amplificationState = _amplificationState;
        precision = StableMath.AMP_PRECISION;
    }

    function _getAmplificationParameter() internal view returns (uint256 value, bool isUpdating) {
        AmplificationState memory state = _amplificationState;

        (uint256 startValue, uint256 endValue, uint256 startTime, uint256 endTime) = (
            state.startValue,
            state.endValue,
            state.startTime,
            state.endTime
        );

        // Note that block.timestamp >= startTime, since startTime is set to the current time when an update starts

        if (block.timestamp < endTime) {
            isUpdating = true;

            // We can skip checked arithmetic as:
            //  - block.timestamp is always larger or equal to startTime
            //  - endTime is always larger than startTime
            //  - the value delta is bounded by the largest amplification parameter, which never causes the
            //    multiplication to overflow.
            // This also means that the following computation will never revert nor yield invalid results.
            unchecked {
                if (endValue > startValue) {
                    value =
                        startValue +
                        ((endValue - startValue) * (block.timestamp - startTime)) /
                        (endTime - startTime);
                } else {
                    value =
                        startValue -
                        ((startValue - endValue) * (block.timestamp - startTime)) /
                        (endTime - startTime);
                }
            }
        } else {
            isUpdating = false;
            value = endValue;
        }
    }

    function _stopAmplification(uint256 value) internal {
        uint64 currentValueUint64 = value.toUint64();
        _amplificationState.startValue = currentValueUint64;
        _amplificationState.endValue = currentValueUint64;

        uint32 currentTime = block.timestamp.toUint32();
        _amplificationState.startTime = currentTime;
        _amplificationState.endTime = currentTime;

        emit AmpUpdateStopped(currentValueUint64);
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return _MIN_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc ISwapFeePercentageBounds
    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return _MAX_SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMinimumInvariantRatio() external pure returns (uint256) {
        return StableMath.MIN_INVARIANT_RATIO;
    }

    /// @inheritdoc IUnbalancedLiquidityInvariantRatioBounds
    function getMaximumInvariantRatio() external pure returns (uint256) {
        return StableMath.MAX_INVARIANT_RATIO;
    }

    /// @inheritdoc IStablePool
    function getStablePoolDynamicData() external view returns (StablePoolDynamicData memory data) {
        data.balancesLiveScaled18 = _vault.getCurrentLiveBalances(address(this));
        (, data.tokenRates) = _vault.getPoolTokenRates(address(this));
        data.staticSwapFeePercentage = _vault.getStaticSwapFeePercentage((address(this)));
        data.totalSupply = totalSupply();
        data.bptRate = getRate();
        (data.amplificationParameter, data.isAmpUpdating) = _getAmplificationParameter();

        AmplificationState memory state = _amplificationState;
        data.startValue = state.startValue;
        data.endValue = state.endValue;
        data.startTime = state.startTime;
        data.endTime = state.endTime;

        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));
        data.isPoolInitialized = poolConfig.isPoolInitialized;
        data.isPoolPaused = poolConfig.isPoolPaused;
        data.isPoolInRecoveryMode = poolConfig.isPoolInRecoveryMode;
    }

    /// @inheritdoc IStablePool
    function getStablePoolImmutableData() external view returns (StablePoolImmutableData memory data) {
        data.tokens = _vault.getPoolTokens(address(this));
        (data.decimalScalingFactors, ) = _vault.getPoolTokenRates(address(this));
        data.amplificationParameterPrecision = StableMath.AMP_PRECISION;
    }
}
