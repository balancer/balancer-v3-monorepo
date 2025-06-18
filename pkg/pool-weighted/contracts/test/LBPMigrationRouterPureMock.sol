// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";

contract LBPMigrationRouterPureMock {
    bool private _isMigrationSetup;

    function isMigrationSetup(ILBPool) external view returns (bool) {
        return _isMigrationSetup;
    }

    function setMigrationSetup(bool isSetup) external {
        _isMigrationSetup = isSetup;
    }
}
