// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILBPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";

import { LBPMigrationRouter } from "../../contracts/lbp/LBPMigrationRouter.sol";

contract LBPMigrationRouterMock is LBPMigrationRouter {
    constructor(
        BalancerContractRegistry contractRegistry,
        string memory version
    ) LBPMigrationRouter(contractRegistry, version) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function manualComputeExactAmountsIn(
        ILBPool lbp,
        uint256 shareToMigrate,
        uint256 migrationWeight0,
        uint256 migrationWeight1,
        uint256[] memory removeAmountsOut
    ) external view returns (uint256[] memory exactAmountsIn) {
        return _computeExactAmountsIn(lbp, shareToMigrate, migrationWeight0, migrationWeight1, removeAmountsOut);
    }

    function manualLockAmount(IERC20 token, address owner, uint256 amount, uint256 duration) external {
        _lockAmount(token, owner, amount, duration);
    }
}
