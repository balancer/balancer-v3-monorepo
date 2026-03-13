// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseLBPFactory } from "../../contracts/lbp/BaseLBPFactory.sol";
import { LBPValidation } from "../../contracts/lbp/LBPValidation.sol";
import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { WeightedLBPTest } from "./utils/WeightedLBPTest.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract LBPoolFactoryTest is WeightedLBPTest {
    using ArrayHelpers for *;

    uint32 internal defaultStartTime;
    uint32 internal defaultEndTime;

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        defaultStartTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        defaultEndTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        return _createLBPool(alice, defaultStartTime, defaultEndTime, DEFAULT_PROJECT_TOKENS_SWAP_IN);
    }

    function testPoolRegistrationOnCreate() public view {
        // Verify pool was registered in the factory.
        assertTrue(lbPoolFactory.isPoolFromFactory(pool), "Pool is not from LBP factory");

        // Verify pool was created and initialized correctly in the vault by the factory.
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");
    }

    function testPoolInitialization() public view {
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(pool);

        assertEq(address(tokens[projectIdx]), address(projectToken), "Project token mismatch");
        assertEq(address(tokens[reserveIdx]), address(reserveToken), "Reserve token mismatch");

        assertEq(balancesRaw[projectIdx], poolInitAmount, "Balances of project token mismatch");
        assertEq(balancesRaw[reserveIdx], poolInitAmount, "Balances of reserve token mismatch");
    }

    function testGetPoolVersion() public view {
        assertEq(lbPoolFactory.getPoolVersion(), poolVersion, "Pool version mismatch");
    }

    function testInvalidTrustedRouter() public {
        vm.expectRevert(BaseLBPFactory.InvalidTrustedRouter.selector);
        new LBPoolFactory(
            vault,
            365 days,
            factoryVersion,
            poolVersion,
            ZERO_ADDRESS // invalid trusted router address
        );
    }

    function testGetTrustedRouter() public view {
        assertEq(lbPoolFactory.getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = lbPoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testCreatePoolWithInvalidOwner() public {
        LBPCommonParams memory commonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: ZERO_ADDRESS,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: true
        });

        // Create LBP params with owner set to zero address
        LBPParams memory params = LBPParams({
            projectTokenStartWeight: DEFAULT_WEIGHT,
            projectTokenEndWeight: DEFAULT_WEIGHT,
            reserveTokenStartWeight: DEFAULT_WEIGHT,
            reserveTokenEndWeight: DEFAULT_WEIGHT,
            reserveTokenVirtualBalance: 0
        });

        vm.expectRevert(LBPValidation.InvalidOwner.selector);
        lbPoolFactory.create(commonParams, params, swapFee, ZERO_BYTES32, address(0));
    }

    function testCreatePool() public {
        (pool, ) = _createLBPool(
            bob,
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            true
        );
        initPool();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        LBPoolImmutableData memory data = ILBPool(pool).getLBPoolImmutableData();

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(address(pool));

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token address mismatch");
            assertEq(data.decimalScalingFactors[i], decimalScalingFactors[i], "Decimal scaling factor mismatch");
            assertEq(data.startWeights[i], startWeights[i], "Wrong start weight");
            assertEq(data.endWeights[i], endWeights[i], "Wrong end weight");
        }

        assertEq(data.startTime, defaultStartTime, "Wrong start time");
        assertEq(data.endTime, defaultEndTime, "Wrong end time");
        assertEq(data.projectTokenIndex, projectIdx, "Wrong project token index");
        assertEq(data.reserveTokenIndex, reserveIdx, "Wrong reserve token index");
        assertEq(
            data.isProjectTokenSwapInBlocked,
            DEFAULT_PROJECT_TOKENS_SWAP_IN,
            "Wrong project token swap blocked flag"
        );

        assertEq(vault.getPoolRoleAccounts(pool).poolCreator, bob, "Incorrect pool creator");
    }

    function testAddLiquidityPermission() public {
        (pool, ) = _createLBPool(
            address(0),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            true
        );
        initPool();

        // Try to add to the pool without permission.
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));

        // The owner is allowed to add.
        vm.prank(bob);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        (pool, ) = _createLBPool(
            address(0),
            uint32(block.timestamp + DEFAULT_START_OFFSET),
            uint32(block.timestamp + DEFAULT_END_OFFSET),
            true
        );
        initPool();

        // Try to donate to the pool
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.donate(pool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testSetSwapFeeNoPermission() public {
        // The LBP Factory only allows the owner (a.k.a. bob) to set the static swap fee percentage of the pool.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(pool, 2.5e16);
    }

    function testSetSwapFee() public {
        uint256 newSwapFee = 2.5e16; // 2.5%

        // Starts out at the default
        assertEq(vault.getStaticSwapFeePercentage(pool), swapFee);

        vm.prank(bob);
        vault.setStaticSwapFeePercentage(pool, newSwapFee);

        assertEq(vault.getStaticSwapFeePercentage(pool), newSwapFee);
    }

    function _createLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime,
        bool blockProjectTokenSwapsIn
    ) internal override returns (address newPool, bytes memory poolArgs) {
        return
            _createLBPoolWithCustomWeights(
                poolCreator,
                startWeights[projectIdx],
                startWeights[reserveIdx],
                endWeights[projectIdx],
                endWeights[reserveIdx],
                startTime,
                endTime,
                blockProjectTokenSwapsIn
            );
    }
}
