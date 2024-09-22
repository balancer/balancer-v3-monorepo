// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPoolFactory } from "../../contracts/LBPoolFactory.sol";

contract LBPoolFactoryTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint64 public constant swapFee = 1e16; //1%

    LBPoolFactory internal lbPoolFactory;

    function setUp() public override {
        super.setUp();

        lbPoolFactory = new LBPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1", address(router));
        vm.label(address(lbPoolFactory), "LB pool factory");
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
