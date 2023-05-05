// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.18;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/ITemporarilyPausable.sol";
import "../helpers/TemporarilyPausable.sol";

contract TemporarilyPausableMock is TemporarilyPausable {
    constructor(uint256 pauseWindowDuration, uint256 bufferPeriodDuration)
        TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration)
    {}
}
