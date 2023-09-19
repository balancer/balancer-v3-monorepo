// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Vault } from "../Vault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";

contract VaultMock is Vault {
    constructor(
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Vault(pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function burnERC20(address poolToken, address from, uint256 amount) external {
        _burnERC20(poolToken, from, amount);
    }

    function mintERC20(address poolToken, address to, uint256 amount) external {
        _mintERC20(poolToken, to, amount);
    }

    function pause() external {
        _pause();
    }

    // Used for testing the ReentrancyGuard
    function reentrantRegisterPool(address factory, IERC20[] memory tokens) external nonReentrant {
        this.registerPool(factory, tokens);
    }

    // Used for testing pool registration, which is ordinarily done in the constructor of the pool.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address factory, IERC20[] memory tokens) external whenNotPaused {
        _registerPool(factory, tokens);
    }
}
