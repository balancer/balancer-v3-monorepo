// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract LBPoolTest is BaseLBPTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    /********************************************************
                        Pool Constructor
    ********************************************************/

    function testCreatePoolLowProjectStartWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the weighted pool is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            wrongWeight,
            wrongWeight.complement(),
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowReserveStartWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the weighted pool is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            wrongWeight.complement(),
            wrongWeight,
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowProjectEndWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the LBP is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            wrongWeight,
            wrongWeight.complement(),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolLowReserveEndWeight() public {
        // Min weight is 1e16 (1%).
        uint256 wrongWeight = 0.5e16;

        // The MinWeight error thrown by the LBP is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            wrongWeight.complement(),
            wrongWeight,
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolNotNormalizedStartWeights() public {
        // The NormalizedWeightInvariant error thrown by the weighted pool is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx] - 1,
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolNotNormalizedEndWeights() public {
        // The NormalizedWeightInvariant error thrown by the LBP is shadowed by the Create2 deployment error.
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx] - 1,
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolTimeTravel() public {
        vm.expectRevert(Create2.Create2FailedDeployment.selector);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            uint32(block.timestamp + 200),
            uint32(block.timestamp + 100), // EndTime after StartTime, it should revert.
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    function testCreatePoolEvent() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        vm.expectEmit();
        emit LBPool.GradualWeightUpdateScheduled(startTime, endTime, startWeights, endWeights);
        _deployAndInitializeWithCustomWeights(
            startWeights[projectIdx],
            startWeights[reserveIdx],
            endWeights[projectIdx],
            endWeights[reserveIdx],
            startTime,
            endTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );
    }

    /********************************************************
                            Getters
    ********************************************************/

    function testGetTrustedRouter() public view {
        assertEq(LBPool(pool).getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testGetTrustedFactory() public view {
        assertEq(LBPool(pool).getTrustedFactory(), address(lbPoolFactory), "Wrong trusted factory");
    }

    function testGradualWeightUpdateParams() public {
        uint32 customStartTime = uint32(block.timestamp + 1);
        uint32 customEndTime = uint32(block.timestamp + 300);
        uint256[] memory customStartWeights = [uint256(22e16), uint256(78e16)].toMemoryArray();
        uint256[] memory customEndWeights = [uint256(65e16), uint256(35e16)].toMemoryArray();

        (address newPool, ) = _deployAndInitializeWithCustomWeights(
            customStartWeights[projectIdx],
            customStartWeights[reserveIdx],
            customEndWeights[projectIdx],
            customEndWeights[reserveIdx],
            customStartTime,
            customEndTime,
            DEFAULT_PROJECT_TOKENS_SWAP_IN
        );

        (
            uint256 poolStartTime,
            uint256 poolEndTime,
            uint256[] memory poolStartWeights,
            uint256[] memory poolEndWeights
        ) = LBPool(newPool).getGradualWeightUpdateParams();
        assertEq(poolStartTime, customStartTime, "Start time mismatch");
        assertEq(poolEndTime, customEndTime, "End time mismatch");

        assertEq(poolStartWeights.length, customStartWeights.length, "Start Weights length mismatch");
        assertEq(poolStartWeights[projectIdx], customStartWeights[projectIdx], "Project Start Weight mismatch");
        assertEq(poolStartWeights[reserveIdx], customStartWeights[reserveIdx], "Reserve Start Weight mismatch");

        assertEq(poolEndWeights.length, customEndWeights.length, "End Weights length mismatch");
        assertEq(poolEndWeights[projectIdx], customEndWeights[projectIdx], "Project End Weight mismatch");
        assertEq(poolEndWeights[reserveIdx], customEndWeights[reserveIdx], "Reserve End Weight mismatch");
    }

    function testIsSwapEnabled() public {
        uint32 startTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        uint32 endTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        assertFalse(LBPool(pool).isSwapEnabled(), "Swap should be disabled before start time");

        vm.warp(startTime + 1);
        assertTrue(LBPool(pool).isSwapEnabled(), "Swap should be enabled after start time");

        vm.warp(endTime + 1);
        assertFalse(LBPool(pool).isSwapEnabled(), "Swap should be disabled after end time");
    }

    function testAddingLiquidityNotAllowed() public {
        // Try to add liquidity to the pool.
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.addLiquidityProportional(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), 1e18, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        // Try to donate to the pool.
        vm.expectRevert(LBPool.AddingLiquidityNotAllowed.selector);
        router.donate(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }
}
