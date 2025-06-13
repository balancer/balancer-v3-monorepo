// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ILBPMigrationRouter } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPMigrationRouter.sol";
import {
    ILBPool,
    LBPoolImmutableData,
    LBPParams
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ContractType } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import {
    PoolRoleAccounts,
    TokenConfig,
    TokenType,
    RemoveLiquidityParams,
    RemoveLiquidityKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

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
