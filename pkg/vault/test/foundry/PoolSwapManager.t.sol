// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { PoolFactoryMock } from "../../contracts/test/PoolFactoryMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract PoolSwapManagerTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal constant NEW_SWAP_FEE = 0.012345e18;

    PoolMock internal unmanagedPool;
    PoolMock internal otherPool;

    PoolFactoryMock internal factory;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        PoolRoleAccounts memory defaultRoleAccounts;
        PoolRoleAccounts memory adminRoleAccounts;
        adminRoleAccounts.swapFeeManager = admin;

        pool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        // Make admin the swap fee manager.
        factoryMock.registerGeneralTestPool(
            address(pool),
            tokenConfig,
            0,
            365 days,
            adminRoleAccounts,
            poolHooksContract
        );

        unmanagedPool = new PoolMock(IVault(address(vault)), "Unmanaged Pool", "UNMANAGED");

        // Pass zero for the swap fee manager.
        factoryMock.registerGeneralTestPool(
            address(unmanagedPool),
            tokenConfig,
            0,
            365 days,
            defaultRoleAccounts,
            poolHooksContract
        );

        // Pass zero for the swap fee manager.
        otherPool = new PoolMock(IVault(address(vault)), "Other Pool", "OTHER");

        // Pass zero for the swap fee manager.
        factoryMock.registerGeneralTestPool(
            address(otherPool),
            tokenConfig,
            0,
            365 days,
            defaultRoleAccounts,
            poolHooksContract
        );

        factory = new PoolFactoryMock(IVault(address(vault)), 365 days);
    }

    function testHasSwapFeeManager() public {
        address swapFeeManager = vault.getStaticSwapFeeManager(address(pool));
        assertEq(swapFeeManager, admin, "swapFeeManager is not admin");

        swapFeeManager = vault.getStaticSwapFeeManager(address(unmanagedPool));
        assertEq(swapFeeManager, address(0), "swapFeeManager is not zero");
    }

    function testSwapFeeManagerCanSetFees() public {
        require(vault.getStaticSwapFeePercentage(address(pool)) == 0, "initial swap fee non-zero");

        // swap fee manager can set the static swap fee.
        vm.prank(admin);
        vault.setStaticSwapFeePercentage(address(pool), NEW_SWAP_FEE);

        assertEq(vault.getStaticSwapFeePercentage(address(pool)), NEW_SWAP_FEE, "Wrong swap fee");
    }

    function testCannotSetSwapFeePercentageIfNotManager() public {
        require(vault.getStaticSwapFeeManager(address(pool)) == address(admin), "Wrong swap fee manager");

        vm.prank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(address(pool), NEW_SWAP_FEE);
    }

    function testGovernanceCanSetSwapFeeIfNoManager() public {
        require(vault.getStaticSwapFeePercentage(address(unmanagedPool)) == 0, "initial swap fee non-zero");

        vm.prank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(address(unmanagedPool), NEW_SWAP_FEE);

        bytes32 setSwapFeeRole = vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector);
        authorizer.grantSpecificRole(setSwapFeeRole, bob, address(unmanagedPool));

        vm.prank(bob);
        vault.setStaticSwapFeePercentage(address(unmanagedPool), NEW_SWAP_FEE);

        assertEq(vault.getStaticSwapFeePercentage(address(unmanagedPool)), NEW_SWAP_FEE, "Could not set swap fee");

        // Granting speciic permission to bob on unmanagedPool doesn't grant it on otherPool
        vm.prank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(address(otherPool), NEW_SWAP_FEE);
    }

    // It is onlyOwner, so governance cannot override
    function testGovernanceCannotSetSwapFeeWithManager() public {
        require(vault.getStaticSwapFeePercentage(address(pool)) == 0, "initial swap fee non-zero");

        vm.prank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(address(pool), NEW_SWAP_FEE);

        bytes32 setSwapFeeRole = vault.getActionId(IVaultAdmin.setStaticSwapFeePercentage.selector);
        authorizer.grantRole(setSwapFeeRole, bob);

        vm.prank(bob);
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        vault.setStaticSwapFeePercentage(address(pool), NEW_SWAP_FEE);
    }
}
