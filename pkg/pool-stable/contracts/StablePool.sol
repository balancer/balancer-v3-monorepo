// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { BasePoolAuthentication } from "@balancer-labs/v3-vault/contracts/BasePoolAuthentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

/// @notice Basic Stable Pool.
contract StablePool is IBasePool, BalancerPoolToken, BasePoolAuthentication, Version {
    using FixedPoint for uint256;
    using SafeCast for *;

    struct AmplificationState {
        uint64 startValue;
        uint64 endValue;
        uint32 startTime;
        uint32 endTime;
    }

    // This contract uses timestamps to slowly update its Amplification parameter over time. These changes must occur
    // over a minimum time period much larger than the blocktime, making timestamp manipulation a non-issue.
    // solhint-disable not-rely-on-time

    // Amplification factor changes must happen over a minimum period of one day, and can at most divide or multiple the
    // current value by 2 every day.
    // WARNING: this only limits *a single* amplification change to have a maximum rate of change of twice the original
    // value daily. It is possible to perform multiple amplification changes in sequence to increase this value more
    // rapidly: for example, by doubling the value every day it can increase by a factor of 8 over three days (2^3).
    uint256 private constant _MIN_UPDATE_TIME = 1 days;
    uint256 private constant _MAX_AMP_UPDATE_DAILY_RATE = 2;

    /// @dev Store amplification state.
    AmplificationState private _amplificationState;

    /// @dev An amplification update has started.
    event AmpUpdateStarted(uint256 startValue, uint256 endValue, uint256 startTime, uint256 endTime);

    /// @dev An amplification update has been stopped.
    event AmpUpdateStopped(uint256 currentValue);

    /// @dev The amplification factor is below the minimum of the range (1 - 5000).
    error AmplificationFactorTooLow();

    /// @dev The amplification factor is above the maximum of the range (1 - 5000).
    error AmplificationFactorTooHigh();

    /// @dev The amplification change duration is too short.
    error AmpUpdateDurationTooShort();

    /// @dev The amplification change rate is too fast.
    error AmpUpdateRateTooFast();

    /// @dev Amplification update operations must be done one at a time.
    error AmpUpdateAlreadyStarted();

    /// @dev Cannot stop an amplification update before it starts.
    error AmpUpdateNotStarted();

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
    function getPoolTokens() public view returns (IERC20[] memory tokens) {
        return getVault().getPoolTokens(address(this));
    }

    /// @inheritdoc IBasePool
    function computeInvariant(uint256[] memory balancesLiveScaled18) public view returns (uint256) {
        (uint256 currentAmp, ) = _getAmplificationParameter();

        return StableMath.computeInvariant(currentAmp, balancesLiveScaled18);
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
                computeInvariant(balancesLiveScaled18).mulDown(invariantRatio),
                tokenInIndex
            );
    }

    /// @inheritdoc IBasePool
    function onSwap(IBasePool.PoolSwapParams memory request) public view onlyVault returns (uint256) {
        uint256 invariant = computeInvariant(request.balancesScaled18);
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

    /**
     * @dev Begins changing the amplification parameter to `rawEndValue` over time. The value will change linearly until
     * `endTime` is reached, when it will be `rawEndValue`.
     *
     * NOTE: Internally, the amplification parameter is represented using higher precision. The values returned by
     * `getAmplificationParameter` have to be corrected to account for this when comparing to `rawEndValue`.
     */
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

        uint64 currentValueUint64 = currentValue.toUint64();
        uint64 endValueUint64 = endValue.toUint64();
        uint32 startTimeUint32 = block.timestamp.toUint32();
        uint32 endTimeUint32 = endTime.toUint32();

        _amplificationState.startValue = currentValueUint64;
        _amplificationState.endValue = endValueUint64;
        _amplificationState.startTime = startTimeUint32;
        _amplificationState.endTime = endTimeUint32;

        emit AmpUpdateStarted(currentValueUint64, endValueUint64, startTimeUint32, endTimeUint32);
    }

    /**
     * @dev Stops the amplification parameter change process, keeping the current value.
     */
    function stopAmplificationParameterUpdate() external authenticate {
        (uint256 currentValue, bool isUpdating) = _getAmplificationParameter();

        if (isUpdating == false) {
            revert AmpUpdateNotStarted();
        }

        _stopAmplification(currentValue);
    }

    /**
     * @notice Get all the amplifcation parameters.
     * @return value Current amplification parameter value (could be in the middle of an update)
     * @return isUpdating True if an amp update is in progress
     * @return precision The raw value is multiplied by this number for greater precision during updates
     */
    function getAmplificationParameter() external view returns (uint256 value, bool isUpdating, uint256 precision) {
        (value, isUpdating) = _getAmplificationParameter();
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
            //  - endTime is alawys larger than startTime
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
}
