// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "../vault/IBasePool.sol";

/// @dev Struct with data for deploying a new AclAmmPool.
struct AclAmmPoolParams {
    string name;
    string symbol;
    string version;
    uint256 increaseDayRate;
    uint256 sqrtQ0;
    uint256 centernessMargin;
}

interface IAclAmmPool is IBasePool {
    event SqrtQ0Updated(uint256 startSqrtQ0, uint256 endSqrtQ0, uint256 startTime, uint256 endTime);
    event AclAmmPoolInitialized(uint256 increaseDayRate, uint256 sqrtQ0, uint256 centernessMargin);

    function getLastVirtualBalances() external view returns (uint256[] memory virtualBalances);

    function getLastTimestamp() external view returns (uint256);

    function getCurrentSqrtQ0() external view returns (uint256);

    function setSqrtQ0(uint256 newSqrtQ0, uint256 startTime, uint256 endTime) external;
}
