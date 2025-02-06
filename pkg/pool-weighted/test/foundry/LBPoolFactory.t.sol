// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";
import { LBPool } from "../../contracts/lbp/LBPool.sol";

contract LBPoolFactoryTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 public constant swapFee = 1e16; // 1%

    string public constant factoryVersion = "Factory v1";
    string public constant poolVersion = "Pool v1";

    uint256 internal constant HIGH_WEIGHT = uint256(70e16);
    uint256 internal constant LOW_WEIGHT = uint256(30e16);

    IERC20 internal projectToken;
    IERC20 internal reserveToken;

    uint256[] internal startWeights;
    uint256[] internal endWeights;
    uint256 internal projectIdx;
    uint256 internal reserveIdx;

    LBPoolFactory internal lbPoolFactory;

    function setUp() public override {
        super.setUp();

        projectToken = dai;
        reserveToken = usdc;

        (projectIdx, reserveIdx) = projectToken < reserveToken ? (0, 1) : (1, 0);
        startWeights = new uint256[](2);
        endWeights = new uint256[](2);

        startWeights[projectIdx] = HIGH_WEIGHT;
        startWeights[reserveIdx] = LOW_WEIGHT;

        endWeights[projectIdx] = LOW_WEIGHT;
        endWeights[reserveIdx] = HIGH_WEIGHT;

        lbPoolFactory = new LBPoolFactory(
            IVault(address(vault)),
            365 days,
            factoryVersion,
            poolVersion,
            address(router)
        );
        vm.label(address(lbPoolFactory), "LB pool factory");
    }

    function testGetTrustedRouter() public view {
        assertEq(lbPoolFactory.getTrustedRouter(), address(router), "Wrong trusted router");
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = lbPoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testCreatePool() public {
        address lbPool = _deployAndInitializeLBPool(
            uint32(block.timestamp + 100),
            uint32(block.timestamp + 200),
            false
        );

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(lbPool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(lbPool), "Pool not initialized");
    }

    function testGetPoolVersion() public view {
        assert(keccak256(abi.encodePacked(lbPoolFactory.getPoolVersion())) == keccak256(abi.encodePacked(poolVersion)));
    }

    function testDonationNotAllowed() public {
        address lbPool = _deployAndInitializeLBPool(
            uint32(block.timestamp + 100),
            uint32(block.timestamp + 200),
            false
        );

        // Try to donate to the pool
        vm.expectRevert(IVaultErrors.BeforeAddLiquidityHookFailed.selector);
        router.donate(lbPool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
    }

    function testSetSwapFeeNoPermission() public {
        address lbPool = _deployAndInitializeLBPool(
            uint32(block.timestamp + 100),
            uint32(block.timestamp + 200),
            false
        );

        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(lbPool, 2.5e16);
    }

    function testSetSwapFee() public {
        uint256 newSwapFee = 2.5e16; // 2.5%

        address lbPool = _deployAndInitializeLBPool(
            uint32(block.timestamp + 100),
            uint32(block.timestamp + 200),
            false
        );

        // Starts out at the default
        assertEq(vault.getStaticSwapFeePercentage(lbPool), swapFee);

        vm.prank(bob);
        vault.setStaticSwapFeePercentage(lbPool, newSwapFee);

        assertEq(vault.getStaticSwapFeePercentage(lbPool), newSwapFee);
    }

    function _deployAndInitializeLBPool(
        uint32 startTime,
        uint32 endTime,
        bool enableProjectTokenSwapsIn
    ) private returns (address newPool) {
        LBPParams memory lbpParams = LBPParams({
            owner: bob,
            projectToken: projectToken,
            reserveToken: reserveToken,
            projectTokenStartWeight: startWeights[projectIdx],
            reserveTokenStartWeight: startWeights[reserveIdx],
            projectTokenEndWeight: endWeights[projectIdx],
            reserveTokenEndWeight: endWeights[reserveIdx],
            startTime: startTime,
            endTime: endTime,
            enableProjectTokenSwapsIn: enableProjectTokenSwapsIn
        });

        vm.startPrank(bob);
        newPool = lbPoolFactory.create("LB Pool", "LBP", lbpParams, swapFee, ZERO_BYTES32);

        router.initialize(
            newPool,
            vault.getPoolTokens(newPool),
            [poolInitAmount, poolInitAmount].toMemoryArray(),
            0,
            false,
            bytes("")
        );
        vm.stopPrank();
    }
}
