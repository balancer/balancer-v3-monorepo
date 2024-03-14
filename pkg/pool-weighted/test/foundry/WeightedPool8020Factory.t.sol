// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "@balancer-labs/v3-vault/contracts/test/VaultExtensionMock.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";

import { WeightedPool8020Factory } from "../../contracts/WeightedPool8020Factory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

contract WeightedPool8020FactoryTest is Test {
    VaultMock vault;
    WeightedPool8020Factory factory;
    RateProviderMock rateProvider;
    ERC20TestToken tokenA;
    ERC20TestToken tokenB;

    address alice = vm.addr(1);

    function setUp() public {
        vault = VaultMockDeployer.deploy();
        factory = new WeightedPool8020Factory(IVault(address(vault)), 365 days);

        tokenA = new ERC20TestToken("Token A", "TKNA", 18);
        tokenB = new ERC20TestToken("Token B", "TKNB", 6);
    }

    function testFactoryPausedState() public {
        uint256 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testPoolCreation__Fuzz(bytes32 salt) public {
        vm.assume(salt > 0);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[1].token = tokenB;
        uint256 highWeightIdx = tokenA > tokenB ? 1 : 0;
        uint256 lowWeightIdx = highWeightIdx == 0 ? 1 : 0;

        WeightedPool pool = WeightedPool(
            factory.create("Balancer 80/20 Pool", "Pool8020", tokens[0], tokens[1], bytes32(0))
        );

        uint256[] memory poolWeights = pool.getNormalizedWeights();
        assertEq(poolWeights[highWeightIdx], 8e17, "Higher weight token is not 80%");
        assertEq(poolWeights[lowWeightIdx], 2e17, "Lower weight token is not 20%");
        assertEq(pool.symbol(), "Pool8020", "Wrong pool symbol");
    }

    function testPoolSalt__Fuzz(bytes32 salt) public {
        vm.assume(salt > 0);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[1].token = tokenB;
        tokens[0].rateProvider = rateProvider;

        WeightedPool pool = WeightedPool(
            factory.create("Balancer 80/20 Pool", "Pool8020", tokens[0], tokens[1], bytes32(0))
        );
        address expectedPoolAddress = factory.getDeploymentAddress(salt);

        WeightedPool secondPool = WeightedPool(
            factory.create("Balancer 80/20 Pool", "Pool8020", tokens[0], tokens[1], salt)
        );

        assertFalse(address(pool) == address(secondPool), "Two deployed pool addresses are equal");
        assertEq(address(secondPool), expectedPoolAddress, "Unexpected pool address");
    }

    function testPoolSender__Fuzz(bytes32 salt) public {
        vm.assume(salt > 0);
        address expectedPoolAddress = factory.getDeploymentAddress(salt);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[1].token = tokenB;
        tokens[0].rateProvider = rateProvider;

        // Different sender should change the address of the pool, given the same salt value
        vm.prank(alice);
        WeightedPool pool = WeightedPool(factory.create("Balancer 80/20 Pool", "Pool8020", tokens[0], tokens[1], salt));
        assertFalse(address(pool) == expectedPoolAddress, "Unexpected pool address");

        vm.prank(alice);
        address aliceExpectedPoolAddress = factory.getDeploymentAddress(salt);
        assertTrue(address(pool) == aliceExpectedPoolAddress, "Unexpected pool address");
    }

    function testPoolCrossChainProtection__Fuzz(bytes32 salt, uint16 chainId) public {
        vm.assume(chainId > 1);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[1].token = tokenB;
        tokens[0].rateProvider = rateProvider;

        vm.prank(alice);
        WeightedPool poolMainnet = WeightedPool(
            factory.create("Balancer 80/20 Pool", "Pool8020", tokens[0], tokens[1], salt)
        );

        vm.chainId(chainId);

        vm.prank(alice);
        WeightedPool poolL2 = WeightedPool(
            factory.create("Balancer 80/20 Pool", "Pool8020", tokens[0], tokens[1], salt)
        );

        // Same sender and salt, should still be different because of the chainId.
        assertFalse(address(poolL2) == address(poolMainnet), "L2 and mainnet pool addresses are equal");
    }
}
