// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";

import { WordCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/WordCodec.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

// @notice Data type to store entire amplification state.
type AmplificationDataBits is bytes32;

using AmplificationDataLib for AmplificationDataBits global;

struct AmplificationData {
    uint256 startValue;
    uint256 endValue;
    uint256 startTime;
    uint256 endTime;
}

library AmplificationDataLib {
    using WordCodec for bytes32;

    // Bit offsets for amplification data
    uint8 public constant START_VALUE_OFFSET = 0;
    uint8 public constant END_VALUE_OFFSET = START_VALUE_OFFSET + _AMP_VALUE_BIT_LENGTH;
    uint8 public constant START_TIME_OFFSET = END_VALUE_OFFSET + _AMP_VALUE_BIT_LENGTH;
    uint8 public constant END_TIME_OFFSET = START_TIME_OFFSET + _TIMESTAMP_BIT_LENGTH;

    uint8 private constant _AMP_VALUE_BIT_LENGTH = 64;
    uint8 private constant _TIMESTAMP_BIT_LENGTH = 64;

    function getStartValue(AmplificationDataBits data) internal pure returns (uint256) {
        return AmplificationDataBits.unwrap(data).decodeUint(START_VALUE_OFFSET, _AMP_VALUE_BIT_LENGTH);
    }

    function getEndValue(AmplificationDataBits data) internal pure returns (uint256) {
        return AmplificationDataBits.unwrap(data).decodeUint(END_VALUE_OFFSET, _AMP_VALUE_BIT_LENGTH);
    }

    function getStartTime(AmplificationDataBits data) internal pure returns (uint256) {
        return AmplificationDataBits.unwrap(data).decodeUint(START_TIME_OFFSET, _TIMESTAMP_BIT_LENGTH);
    }

    function getEndTime(AmplificationDataBits data) internal pure returns (uint256) {
        return AmplificationDataBits.unwrap(data).decodeUint(END_TIME_OFFSET, _TIMESTAMP_BIT_LENGTH);
    }

    function fromAmpData(AmplificationData memory data) internal pure returns (AmplificationDataBits) {
        return
            AmplificationDataBits.wrap(
                bytes32(0)
                    .insertUint(data.startValue, START_VALUE_OFFSET, _AMP_VALUE_BIT_LENGTH)
                    .insertUint(data.endValue, END_VALUE_OFFSET, _AMP_VALUE_BIT_LENGTH)
                    .insertUint(data.startTime, START_TIME_OFFSET, _TIMESTAMP_BIT_LENGTH)
                    .insertUint(data.endTime, END_TIME_OFFSET, _TIMESTAMP_BIT_LENGTH)
            );
    }

    function toAmpData(AmplificationDataBits data) internal pure returns (AmplificationData memory) {
        return
            AmplificationData({
                startValue: data.getStartValue(),
                endValue: data.getEndValue(),
                startTime: data.getStartTime(),
                endTime: data.getEndTime()
            });
    }
}
