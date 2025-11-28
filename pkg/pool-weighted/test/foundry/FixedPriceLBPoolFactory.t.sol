// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/IFixedPriceLBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { FixedPriceLBPoolContractsDeployer } from "./utils/FixedPriceLBPoolContractsDeployer.sol";
import { FixedPriceLBPoolFactory } from "../../contracts/lbp/FixedPriceLBPoolFactory.sol";
import { FixedPriceLBPool } from "../../contracts/lbp/FixedPriceLBPool.sol";
import { BaseLBPFactory } from "../../contracts/lbp/BaseLBPFactory.sol";
import { LBPValidation } from "../../contracts/lbp/LBPValidation.sol";
import { BaseLBPTest } from "./utils/BaseLBPTest.sol";

contract FixedPriceLBPoolFactoryTest is BaseLBPTest, FixedPriceLBPoolContractsDeployer {
    using ArrayHelpers for *;

    uint256 internal constant DEFAULT_RATE = FixedPoint.ONE;

    // Bounds on the project token rate.
    uint256 private constant MIN_PROJECT_TOKEN_RATE = FixedPoint.ONE / 10_000;
    uint256 private constant MAX_PROJECT_TOKEN_RATE = FixedPoint.ONE * 10_000;

    FixedPriceLBPoolFactory internal lbPoolFactory;

    uint32 internal defaultStartTime;
    uint32 internal defaultEndTime;

    function setUp() public virtual override {
        super.setUp();
    }

    function createPoolFactory() internal virtual override returns (address) {
        lbPoolFactory = deployFixedPriceLBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router)
        );
        vm.label(address(lbPoolFactory), "Fixed Price LB pool factory");

        return address(lbPoolFactory);
    }

    function createPool() internal virtual override returns (address newPool, bytes memory poolArgs) {
        defaultStartTime = uint32(block.timestamp + DEFAULT_START_OFFSET);
        defaultEndTime = uint32(block.timestamp + DEFAULT_END_OFFSET);

        return _createFixedPriceLBPool(alice, defaultStartTime, defaultEndTime);
    }

    function initPool() internal virtual override {
        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[projectIdx] = poolInitAmount;

        vm.startPrank(bob); // Bob is the owner of the pool.
        _initPool(pool, initAmounts, 0);
        vm.stopPrank();
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

        assertEq(balancesRaw[projectIdx], poolInitAmount, "Balance of project token mismatch");
        assertEq(balancesRaw[reserveIdx], 0, "Non-zero balance of reserve token");
    }

    function testGetPoolVersion() public view {
        assertEq(lbPoolFactory.getPoolVersion(), poolVersion, "Pool version mismatch");
    }

    function testInvalidTrustedRouter() public {
        vm.expectRevert(BaseLBPFactory.InvalidTrustedRouter.selector);
        new FixedPriceLBPoolFactory(
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

    function testGetMigrationRouter() public view {
        assertEq(lbPoolFactory.getMigrationRouter(), address(0), "Non-zero migration router");
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = lbPoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testCreatePoolWithInvalidOwner() public {
        LBPCommonParams memory commonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: ZERO_ADDRESS,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: true
        });

        vm.expectRevert(LBPValidation.InvalidOwner.selector);
        lbPoolFactory.create(commonParams, DEFAULT_RATE, swapFee, ZERO_BYTES32, address(0));
    }

    function testCreatePool() public {
        (pool, ) = _createFixedPriceLBPool(bob, uint32(block.timestamp + 100), uint32(block.timestamp + 200));
        initPool();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(pool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(pool), "Pool not initialized");

        FixedPriceLBPoolImmutableData memory data = IFixedPriceLBPool(pool).getFixedPriceLBPoolImmutableData();

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(pool);
        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(address(pool));

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(address(data.tokens[i]), address(tokens[i]), "Token address mismatch");
            assertEq(data.decimalScalingFactors[i], decimalScalingFactors[i], "Decimal scaling factor mismatch");
        }

        assertEq(data.startTime, defaultStartTime, "Wrong start time");
        assertEq(data.endTime, defaultEndTime, "Wrong end time");
        assertEq(data.projectTokenIndex, projectIdx, "Wrong project token index");
        assertEq(data.reserveTokenIndex, reserveIdx, "Wrong reserve token index");
        assertTrue(data.isProjectTokenSwapInBlocked, "Project token swap in not disabled");

        assertEq(data.projectTokenRate, DEFAULT_RATE, "Wrong project token rate");
        assertEq(data.migrationRouter, address(0), "Migration router not zero");

        assertEq(data.lockDurationAfterMigration, 0, "BPT lock duration should be zero");
        assertEq(data.bptPercentageToMigrate, 0, "Share to migrate should be zero");
        assertEq(data.migrationWeightProjectToken, 0, "Project token weight should be zero");
        assertEq(data.migrationWeightReserveToken, 0, "Reserve token weight should be zero");
        assertEq(data.migrationRouter, ZERO_ADDRESS, "Migration router should be zero address");
        assertEq(vault.getPoolRoleAccounts(pool).poolCreator, bob, "Incorrect pool creator");
    }

    function testAddLiquidityPermission() public {
        (pool, ) = _createFixedPriceLBPool(uint32(block.timestamp + 100), uint32(block.timestamp + 200));
        initPool();

        // Try to add to the pool without permission.
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));

        // The owner is allowed to add.
        vm.prank(bob);
        router.addLiquidityProportional(pool, [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(), 0, false, bytes(""));
    }

    function testDonationNotAllowed() public {
        (pool, ) = _createFixedPriceLBPool(uint32(block.timestamp + 100), uint32(block.timestamp + 200));
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

    function testRatesInFactory() public {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: false
        });

        uint256 salt = _saltCounter++;

        vm.expectRevert(IFixedPriceLBPool.InvalidProjectTokenRate.selector);
        lbPoolFactory.create(lbpCommonParams, 0, swapFee, bytes32(salt), address(0));
    }

    function testBuyOnlyInFactory() public {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "LBPool",
            symbol: "LBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: uint32(block.timestamp + DEFAULT_START_OFFSET),
            endTime: uint32(block.timestamp + DEFAULT_END_OFFSET),
            blockProjectTokenSwapsIn: false
        });

        uint256 salt = _saltCounter++;

        vm.expectRevert(IFixedPriceLBPool.TokenSwapsInUnsupported.selector);
        lbPoolFactory.create(lbpCommonParams, DEFAULT_RATE, swapFee, bytes32(salt), address(0));
    }

    function _createFixedPriceLBPool(
        uint32 startTime,
        uint32 endTime
    ) internal returns (address newPool, bytes memory poolArgs) {
        return _createFixedPriceLBPool(address(0), startTime, endTime);
    }

    function _createFixedPriceLBPool(
        address poolCreator,
        uint32 startTime,
        uint32 endTime
    ) internal returns (address newPool, bytes memory poolArgs) {
        LBPCommonParams memory lbpCommonParams = LBPCommonParams({
            name: "FixedPriceLBPool",
            symbol: "FLBP",
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            startTime: startTime,
            endTime: endTime,
            blockProjectTokenSwapsIn: true // Fixed price LBPs are always "buy-only"
        });

        FactoryParams memory factoryParams = FactoryParams({
            vault: vault,
            trustedRouter: address(router),
            migrationRouter: address(0),
            poolVersion: poolVersion
        });

        uint256 salt = _saltCounter++;

        newPool = lbPoolFactory.create(lbpCommonParams, DEFAULT_RATE, swapFee, bytes32(salt), poolCreator);

        poolArgs = abi.encode(lbpCommonParams, factoryParams, DEFAULT_RATE);
    }
}
