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

    function testGetTrustedFactory() public view {
        assertEq(LBPool(pool).getTrustedFactory(), address(lbPoolFactory), "Wrong trusted factory");
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
