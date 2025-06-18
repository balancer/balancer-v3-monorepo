// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ContractType } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerContractRegistry.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LBPoolImmutableData,
    LBPoolDynamicData,
    ILBPool
} from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BalancerContractRegistry } from "@balancer-labs/v3-standalone-utils/contracts/BalancerContractRegistry.sol";

import { LBPMigrationRouter } from "../../contracts/lbp/LBPMigrationRouter.sol";
import { GradualValueChange } from "../../contracts/lib/GradualValueChange.sol";
import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract LBMigrationPoolTest is BaseLBPTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    /*******************************************************************************
                                      Pool Hooks
    *******************************************************************************/

    function testOnBeforeInitialize() public {
        // Warp to before start time (initialization is allowed before start time)
        vm.warp(block.timestamp + DEFAULT_START_OFFSET - 1);

        vm.prank(address(vault));
        _mockGetSender(bob);

        assertTrue(
            LBPool(pool).onBeforeInitialize(new uint256[](0), ""),
            "onBeforeInitialize should return true with correct sender and before startTime"
        );
    }

    function testOnBeforeRemoveLiquidity() public {
        // Warp to after end time, where removing liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.prank(address(vault));
        bool success = LBPool(pool).onBeforeRemoveLiquidity(
            address(router),
            address(0),
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );

        assertTrue(success, "onBeforeRemoveLiquidity should return true after end time");
    }

    function testOnBeforeRemoveLiquidityWithMigrationRouter() public {
        // Warp to before start time, where removing liquidity is not allowed.
        vm.warp(block.timestamp + DEFAULT_START_OFFSET - 1);

        vm.prank(address(vault));
        bool success = LBPool(pool).onBeforeRemoveLiquidity(
            address(migrationRouter),
            address(0),
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );

        assertFalse(success, "onBeforeRemoveLiquidity should return false before start time");
    }

    function testOnBeforeRemoveLiquidityWithWrongSender() public {
        // Warp to after end time, where removing liquidity is allowed.
        vm.warp(block.timestamp + DEFAULT_END_OFFSET + 1);

        vm.prank(address(vault));
        _mockGetSender(bob);
        bool success = LBPool(pool).onBeforeRemoveLiquidity(
            address(router),
            address(0),
            RemoveLiquidityKind.PROPORTIONAL,
            0,
            new uint256[](0),
            new uint256[](0),
            bytes("")
        );

        assertFalse(success, "onBeforeRemoveLiquidity should return false if sender is not the migration router");
    }

    /*******************************************************************************
                                   Private Helpers
    *******************************************************************************/

    function _mockGetSender(address sender) private {
        vm.mockCall(address(router), abi.encodeWithSelector(ISenderGuard.getSender.selector), abi.encode(sender));
    }
}
