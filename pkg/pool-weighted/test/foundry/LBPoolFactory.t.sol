// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPoolFactory } from "../../contracts/lbp/LBPoolFactory.sol";

contract LBPoolFactoryTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint64 public constant swapFee = 1e16; //1%

    LBPoolFactory internal lbPoolFactory;

    string public constant poolVersion = "Pool v1";

    function setUp() public override {
        super.setUp();

        lbPoolFactory = new LBPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            poolVersion,
            address(router),
            permit2
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
        address lbPool = _deployAndInitializeLBPool();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(lbPool), "Pool not registered in the vault");
    }

    function testCreateAndInitializePool() public {
        vm.startPrank(bob);

        uint256 snapshotId = vm.snapshot();

        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();
        uint256[] memory exactAmountsIn = [poolInitAmount, poolInitAmount].toMemoryArray();

        address expectedLbPoolAddress = lbPoolFactory.create(
            "LB Pool",
            "LBP",
            vault.buildTokenConfig(tokens),
            weights,
            swapFee,
            bob, // owner
            true, // swapEnabledOnStart
            ZERO_BYTES32
        );

        vm.revertTo(snapshotId);

        dai.approve(address(lbPoolFactory), poolInitAmount);
        usdc.approve(address(lbPoolFactory), poolInitAmount);

        vm.expectCall(
            address(router),
            abi.encodeCall(IRouter.initialize, (expectedLbPoolAddress, tokens, exactAmountsIn, 0, false, ""))
        );
        address lbPool = lbPoolFactory.createAndInitialize(
            "LB Pool",
            "LBP",
            vault.buildTokenConfig(tokens),
            weights,
            swapFee,
            bob, // owner
            true, // swapEnabledOnStart
            ZERO_BYTES32,
            exactAmountsIn
        );
        vm.stopPrank();

        // Verify pool was created and initialized correctly
        assertTrue(vault.isPoolRegistered(lbPool), "Pool not registered in the vault");
        assertTrue(vault.isPoolInitialized(lbPool), "Pool not initialized in the vault");
        assertEq(expectedLbPoolAddress, lbPool, "Unexpected pool address");

        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(lbPool);
        assertEq(balancesRaw.length, 2, "Unexpected balances raw length");
        assertEq(balancesRaw[0], exactAmountsIn[0], "Unexpected balances raw [0]");
        assertEq(balancesRaw[1], exactAmountsIn[1], "Unexpected balances raw [1]");
    }

    function testGetPoolVersion() public view {
        assert(keccak256(abi.encodePacked(lbPoolFactory.getPoolVersion())) == keccak256(abi.encodePacked(poolVersion)));
    }

    function testDonationNotAllowed() public {
        address lbPool = _deployAndInitializeLBPool();

        // Try to donate to the pool
        vm.startPrank(bob);
        vm.expectRevert(IVaultErrors.DoesNotSupportDonation.selector);
        router.donate(lbPool, [poolInitAmount, poolInitAmount].toMemoryArray(), false, bytes(""));
        vm.stopPrank();
    }

    function _deployAndInitializeLBPool() private returns (address) {
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        address lbPool = lbPoolFactory.create(
            "LB Pool",
            "LBP",
            vault.buildTokenConfig(tokens),
            weights,
            swapFee,
            bob, // owner
            true, // swapEnabledOnStart
            ZERO_BYTES32
        );

        // Initialize pool.
        vm.prank(bob); // Owner initializes the pool
        router.initialize(lbPool, tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, bytes(""));

        return lbPool;
    }
}
