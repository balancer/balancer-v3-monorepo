// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "../vault/VaultTypes.sol";
import { IRateProvider } from "../vault/IRateProvider.sol";

interface IVaultMainMock {
    function getPoolFactoryMock() external view returns (address);

    function burnERC20(address token, address from, uint256 amount) external;

    function mintERC20(address token, address to, uint256 amount) external;

    function setConfig(address pool, PoolConfig calldata config) external;

    function setRateProvider(address pool, IERC20 token, IRateProvider rateProvider) external;

    function manualRegisterPool(address pool, IERC20[] memory tokens) external;

    function manualRegisterPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        uint256 timestamp,
        address pauseManager
    ) external;

    function getDecimalScalingFactors(address pool) external view returns (uint256[] memory);

    function recoveryModeExit(address pool) external view;

    function computePoolData(address pool, Rounding roundingDirection) external returns (PoolData memory);

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw);

    function getLastLiveBalances(address pool) external view returns (uint256[] memory lastLiveBalances);
}
