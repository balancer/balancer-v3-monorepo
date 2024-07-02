// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

struct StablePoolDynamicData {
    uint256[] liveBalances;
    uint256[] tokenRates;
    uint256 staticSwapFeePercentage;
    uint256 totalSupply;
    uint256 bptRate;
    uint256 amplificationParameter;
    bool isAmpUpdating;
}

struct StablePoolImmutableData {
    IERC20[] tokens;
    uint256[] decimalScalingFactors;
    uint256 amplificationParameterPrecision;
}

/// @notice Full Stable pool interface.
interface IStablePool is IBasePool {
    /**
     * @dev Begins changing the amplification parameter to `rawEndValue` over time. The value will change linearly until
     * `endTime` is reached, when it will be `rawEndValue`.
     *
     * NOTE: Internally, the amplification parameter is represented using higher precision. The values returned by
     * `getAmplificationParameter` have to be corrected to account for this when comparing to `rawEndValue`.
     */
    function startAmplificationParameterUpdate(uint256 rawEndValue, uint256 endTime) external;

    /// @dev Stops the amplification parameter change process, keeping the current value.
    function stopAmplificationParameterUpdate() external;

    /**
     * @notice Get all the amplifcation parameters.
     * @return value Current amplification parameter value (could be in the middle of an update)
     * @return isUpdating True if an amp update is in progress
     * @return precision The raw value is multiplied by this number for greater precision during updates
     */
    function getAmplificationParameter() external view returns (uint256 value, bool isUpdating, uint256 precision);

    /// @notice Get relevant dynamic pool data required for swap/add/remove calculations.
    function getStablePoolDynamicData() external view returns (StablePoolDynamicData memory data);

    /// @notice Get relevant immutable pool data required for swap / add / remove calculations.
    function getStablePoolImmutableData() external view returns (StablePoolImmutableData memory data);
}
