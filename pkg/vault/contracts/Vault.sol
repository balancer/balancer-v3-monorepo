// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./PoolTokens.sol";

contract Vault is PoolTokens {
    constructor(
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
