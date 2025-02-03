// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { PoolConfig, PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";

import { CowPoolFactory } from "../../contracts/CowPoolFactory.sol";
import { CowPool } from "../../contracts/CowPool.sol";
import { BaseCowTest } from "./utils/BaseCowTest.sol";

contract CowPoolFactoryTest is BaseCowTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    function testGetPoolVersion() public view {
        assertEq(IPoolVersion(address(cowFactory)).getPoolVersion(), POOL_VERSION, "Pool version does not match");
    }

    /********************************************************
                          Trusted Router
    ********************************************************/

    function testGetTrustedRouter() public view {
        assertEq(cowFactory.getTrustedCowRouter(), address(cowRouter), "Trusted Router is not CoW Router");
    }

    function testSetTrustedRouterIsPermissioned() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowFactory.setTrustedCowRouter(address(1));
    }

    function testSetTrustedRouter() public {
        assertEq(cowFactory.getTrustedCowRouter(), address(cowRouter), "Trusted Router is not CoW Router");

        vm.prank(admin);
        cowFactory.setTrustedCowRouter(address(1));

        assertEq(cowFactory.getTrustedCowRouter(), address(1), "Trusted Router is not set properly");
    }

    /********************************************************
                             Create
    ********************************************************/

    function testCreateWithPoolCreator() public {
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);

        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = lp;

        // Balancer factories do not allow poolCreator.
        vm.expectRevert(BasePoolFactory.StandardPoolWithCreator.selector);
        cowFactory.create("test", "test", tokenConfig, weights, roleAccounts, DEFAULT_SWAP_FEE_PERCENTAGE, bytes32(""));
    }

    function testCreateDonationAndUnbalancedLiquidity() public {
        IERC20[] memory tokens = [address(dai), address(usdc)].toMemoryArray().asIERC20();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);

        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        PoolRoleAccounts memory roleAccounts;

        address newPool = cowFactory.create(
            "test",
            "test",
            tokenConfig,
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE_PERCENTAGE,
            bytes32("")
        );

        PoolConfig memory poolConfig = vault.getPoolConfig(newPool);

        assertTrue(poolConfig.liquidityManagement.enableDonation, "Donations are not enabled");
        assertTrue(
            poolConfig.liquidityManagement.disableUnbalancedLiquidity,
            "Unbalanced liquidity operations are not disabled"
        );
    }
}
