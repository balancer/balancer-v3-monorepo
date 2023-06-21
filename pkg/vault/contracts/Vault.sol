// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./PoolRegistry.sol";

contract Vault is PoolRegistry {
    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        _weth = weth;
    }

    // solhint-disable-next-line func-name-mixedcase
    function WETH() public view override returns (IWETH) {
        return _weth;
    }
}
