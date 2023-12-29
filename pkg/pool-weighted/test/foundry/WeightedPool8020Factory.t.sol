// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IVault, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
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
        BasicAuthorizerMock authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        factory = new WeightedPool8020Factory(vault, 365 days);

        tokenA = new ERC20TestToken("Token A", "TKNA", 18);
        tokenB = new ERC20TestToken("Token B", "TKNB", 6);
    }

    function testFactoryPausedState() public {
        uint256 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testPoolCreation(bytes32 salt) public {
        vm.assume(salt > 0);

        WeightedPool pool = WeightedPool(
            factory.create(
                "Balancer 80/20 Pool",
                "Pool8020",
                tokenA,
                tokenB,
                TokenType.STANDARD,
                TokenType.STANDARD,
                IRateProvider(address(0)),
                IRateProvider(address(0)),
                bytes32(0)
            )
        );

        uint256[] memory poolWeights = pool.getNormalizedWeights();
        assertEq(poolWeights[0], 8e17);
        assertEq(poolWeights[1], 2e17);
        assertEq(pool.symbol(), "Pool8020");
    }

    function testPoolSalt(bytes32 salt) public {
        vm.assume(salt > 0);

        WeightedPool pool = WeightedPool(
            factory.create(
                "Balancer 80/20 Pool",
                "Pool8020",
                tokenA,
                tokenB,
                TokenType.STANDARD,
                TokenType.STANDARD,
                IRateProvider(address(rateProvider)),
                IRateProvider(address(0)),
                bytes32(0)
            )
        );
        address expectedPoolAddress = factory.getDeploymentAddress(salt);

        WeightedPool secondPool = WeightedPool(
            factory.create(
                "Balancer 80/20 Pool",
                "Pool8020",
                tokenA,
                tokenB,
                TokenType.STANDARD,
                TokenType.STANDARD,
                IRateProvider(address(rateProvider)),
                IRateProvider(address(0)),
                salt
            )
        );

        assertFalse(address(pool) == address(secondPool));
        assertEq(address(secondPool), expectedPoolAddress);
    }

    function testPoolSender(bytes32 salt) public {
        vm.assume(salt > 0);
        address expectedPoolAddress = factory.getDeploymentAddress(salt);

        // Different sender should change the address of the pool, given the same salt value
        vm.prank(alice);
        WeightedPool pool = WeightedPool(
            factory.create(
                "Balancer 80/20 Pool",
                "Pool8020",
                tokenA,
                tokenB,
                TokenType.STANDARD,
                TokenType.STANDARD,
                IRateProvider(address(rateProvider)),
                IRateProvider(address(0)),
                salt
            )
        );
        assertFalse(address(pool) == expectedPoolAddress);

        vm.prank(alice);
        address aliceExpectedPoolAddress = factory.getDeploymentAddress(salt);
        assertTrue(address(pool) == aliceExpectedPoolAddress);
    }

    function testPoolCrossChainProtection(bytes32 salt, uint16 chainId) public {
        vm.assume(chainId > 1);

        vm.prank(alice);
        WeightedPool poolMainnet = WeightedPool(
            factory.create(
                "Balancer 80/20 Pool",
                "Pool8020",
                tokenA,
                tokenB,
                TokenType.STANDARD,
                TokenType.STANDARD,
                IRateProvider(address(rateProvider)),
                IRateProvider(address(0)),
                salt
            )
        );

        vm.chainId(chainId);

        vm.prank(alice);
        WeightedPool poolL2 = WeightedPool(
            factory.create(
                "Balancer 80/20 Pool",
                "Pool8020",
                tokenA,
                tokenB,
                TokenType.STANDARD,
                TokenType.STANDARD,
                IRateProvider(address(rateProvider)),
                IRateProvider(address(0)),
                salt
            )
        );

        // Same sender and salt, should still be different because of the chainId.
        assertFalse(address(poolL2) == address(poolMainnet));
    }
}
