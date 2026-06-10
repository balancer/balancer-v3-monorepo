// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { UnpausableStablePoolFactory } from "../../contracts/UnpausableStablePoolFactory.sol";
import { BaseStablePoolFactoryTest } from "./utils/BaseStablePoolFactoryTest.sol";

contract UnpausableStablePoolFactoryTest is BaseStablePoolFactoryTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    UnpausableStablePoolFactory internal unpausablePoolFactory;

    function setUp() public override {
        super.setUp();

        unpausablePoolFactory = deployUnpausableStablePoolFactory(IVault(address(vault)), "Factory v1", "Pool v1");
        vm.label(address(unpausablePoolFactory), "unpausable stable pool factory");
    }

    function createStablePool(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        PoolRoleAccounts memory roleAccounts,
        bool enableDonation
    ) internal override returns (address) {
        return
            unpausablePoolFactory.create(
                name,
                symbol,
                tokenConfig,
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                MAX_SWAP_FEE_PERCENTAGE,
                address(0),
                enableDonation,
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            );
    }

    function testFactoryPausedState() public view {
        assertEq(unpausablePoolFactory.getPauseWindowDuration(), 0, "Pause window duration is not zero");

        // With a zero duration, the pause window ended at deployment time, so all pools created by this factory
        // register with a pause window end time of 0.
        assertEq(
            unpausablePoolFactory.getOriginalPauseWindowEndTime(),
            block.timestamp,
            "Original pause window end time is not the deployment time"
        );
        assertEq(unpausablePoolFactory.getNewPoolPauseWindowEndTime(), 0, "New pool pause window end time is not zero");
    }

    function testFactoryVersions() public view {
        assertEq(unpausablePoolFactory.version(), "Factory v1", "Wrong factory version");
        assertEq(unpausablePoolFactory.getPoolVersion(), "Pool v1", "Wrong pool version");
    }

    function testPoolPauseWindowEndTime() public {
        address stablePool = _deployAndInitializeStablePool(false);

        (bool paused, uint32 pauseWindowEndTime, , ) = vault.getPoolPausedState(stablePool);
        assertFalse(paused, "Pool is paused");
        assertEq(pauseWindowEndTime, 0, "Pool pause window end time is not zero");
    }

    function testPauseManagerCannotPausePool() public {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.pauseManager = admin;

        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        address stablePool = createStablePool(
            "Unpausable Pool",
            "UNPAUSABLE",
            vault.buildTokenConfig(tokens),
            roleAccounts,
            false
        );

        // The pause manager passes authentication, but pausing reverts: the pause window has already expired.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPauseWindowExpired.selector, stablePool));
        vault.pausePool(stablePool);
    }

    function testGovernanceCannotPausePool() public {
        address stablePool = _deployAndInitializeStablePool(false);

        // Authorize Alice, so that the revert reflects the expired pause window, not failed authentication.
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pausePool.selector), alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.PoolPauseWindowExpired.selector, stablePool));
        vault.pausePool(stablePool);
    }

    function testVaultPauseStillPausesPool() public {
        // Pool-level pausing is disabled, but pools from this factory cannot opt out of a Vault-wide pause.
        address stablePool = _deployAndInitializeStablePool(false);

        vault.manualPauseVault();

        vm.prank(bob);
        vm.expectRevert(IVaultErrors.VaultPaused.selector);
        router.swapSingleTokenExactIn(stablePool, dai, usdc, poolInitAmount / 10, 0, MAX_UINT256, false, bytes(""));
    }
}
