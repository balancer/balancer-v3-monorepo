// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";

import "./AssetHelpers.sol";

interface IVault {
    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view returns (IWETH);
}

contract Vault is IVault, AssetHelpers, TemporarilyPausable {
    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) AssetHelpers(weth) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view override returns (IWETH) {
        return _WETH();
    }
}
