// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

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
        MigrationHookParams memory params,
        uint256[] memory removeAmountsOut
    ) external view returns (uint256[] memory exactAmountsIn) {
        return _computeExactAmountsIn(params, removeAmountsOut);
    }

    function manualLockAmount(MigrationHookParams memory params, uint256 bptAmountOut) external {
        _lockAmount(params, bptAmountOut);
    }
}
