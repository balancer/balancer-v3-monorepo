// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FactoryWidePauseWindow } from "../factories/FactoryWidePauseWindow.sol";

contract PoolFactoryMock is FactoryWidePauseWindow {
    // Since there is a minimum static swap fee, sending zero will actually set the pool to have dynamic fees.
    // As dynamic fees are not currently implemented, this is a way to bypass the minimum for testing purposes.
    // The current implementation ignores the dynamic fee flag and always returns the static swap fee, which
    // initializes to zero. That way, it will return 0 in this case, yet can be overridden for tests that require
    // non-zero swap fees.
    uint256 private constant DEFAULT_SWAP_FEE = 0;

    IVault private immutable _vault;

    constructor(IVault vault, uint256 pauseWindowDuration) FactoryWidePauseWindow(pauseWindowDuration) {
        _vault = vault;
    }

    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        address pauseManager,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            getNewPoolPauseWindowEndTime(),
            pauseManager,
            poolHooks,
            liquidityManagement
        );
    }

    // For tests; otherwise can't get the exact event arguments.
    function registerPoolAtTimestamp(
        address pool,
        TokenConfig[] memory tokenConfig,
        address pauseManager,
        PoolHooks calldata poolHooks,
        LiquidityManagement calldata liquidityManagement,
        uint256 timestamp
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            timestamp,
            pauseManager,
            poolHooks,
            liquidityManagement
        );
    }
}
