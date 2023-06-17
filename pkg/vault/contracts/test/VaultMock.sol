// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../Vault.sol";

contract VaultMock is Vault {
    constructor(
      uint256 pauseWindowDuration,
      uint256 bufferPeriodDuration
    ) Vault(pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks      
    }

    function mint(address poolToken, address to, uint256 amount) external {
        _mint(poolToken, to, amount);
    }

    function burn(address poolToken, address from, uint256 amount) external {
        _burn(poolToken, from, amount);
    }
}
