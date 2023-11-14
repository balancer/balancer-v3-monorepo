// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault, PoolCallbacks, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { FactoryWidePauseWindow } from "../factories/FactoryWidePauseWindow.sol";

contract PoolFactoryMock is FactoryWidePauseWindow {
    IVault private immutable _vault;

    constructor(
        IVault vault,
        uint256 initialPauseWindowDuration,
        uint256 bufferPeriodDuration
    ) FactoryWidePauseWindow(initialPauseWindowDuration, bufferPeriodDuration) {
        _vault = vault;
    }

    function registerPool(
        address pool,
        IERC20[] memory tokens,
        PoolCallbacks calldata poolCallbacks,
        LiquidityManagement calldata liquidityManagement
    ) external {
        (uint256 pauseWindowDuration, uint256 bufferPeriodDuration) = getPauseConfiguration();

        _vault.registerPool(
            pool,
            tokens,
            pauseWindowDuration,
            bufferPeriodDuration,
            poolCallbacks,
            liquidityManagement
        );
    }
}
