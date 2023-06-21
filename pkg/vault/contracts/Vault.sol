// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";
import "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

interface IVault {
    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view returns (IWETH);
}

contract Vault is IVault, TemporarilyPausable {
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
