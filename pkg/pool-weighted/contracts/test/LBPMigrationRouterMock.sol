// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    function manualLockAmount(IERC20 token, address owner, uint256 amount, uint256 duration) external {
        _lockAmount(token, owner, amount, duration);
    }

    function manualAddLockedAmount(address owner, IERC20 token, uint256 amount, uint256 unlockTimestamp) external {
        _timeLockedAmounts[owner].push(
            TimeLockedAmount({ token: token, amount: amount, unlockTimestamp: unlockTimestamp })
        );
    }
}
