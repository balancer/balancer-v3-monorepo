// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BaseStablePoolFactoryTest } from "./utils/BaseStablePoolFactoryTest.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";

contract StablePoolFactoryTest is BaseStablePoolFactoryTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    StablePoolFactory internal stablePoolFactory;

    function setUp() public override {
        super.setUp();

        stablePoolFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        vm.label(address(stablePoolFactory), "stable pool factory");
    }

    function createStablePool(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        PoolRoleAccounts memory roleAccounts,
        bool enableDonation
    ) internal override returns (address) {
        return
            stablePoolFactory.create(
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
        uint32 pauseWindowDuration = stablePoolFactory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testFactoryVersions() public view {
        assertEq(stablePoolFactory.version(), "Factory v1", "Wrong factory version");
        assertEq(stablePoolFactory.getPoolVersion(), "Pool v1", "Wrong pool version");
    }

    function testPauseManagerCanPausePool() public {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.pauseManager = admin;

        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        address stablePool = createStablePool(
            "Pausable Pool",
            "PAUSABLE",
            vault.buildTokenConfig(tokens),
            roleAccounts,
            false
        );

        (, uint32 pauseWindowEndTime, , address pauseManager) = vault.getPoolPausedState(stablePool);
        assertEq(pauseManager, admin, "Wrong pause manager");
        assertEq(
            pauseWindowEndTime,
            stablePoolFactory.getOriginalPauseWindowEndTime(),
            "Wrong pool pause window end time"
        );

        vm.prank(admin);
        vault.pausePool(stablePool);

        assertTrue(vault.isPoolPaused(stablePool), "Pool not paused");
    }
}
