// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { TokenConfig, TokenType, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { WeightedPool8020Factory } from "../../contracts/WeightedPool8020Factory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

contract WeightedPool8020FactoryTest is Test {
    uint256 internal DEFAULT_SWAP_FEE = 1e16; // 1%

    VaultMock vault;
    WeightedPool8020Factory factory;
    RateProviderMock rateProvider;
    ERC20TestToken tokenA;
    ERC20TestToken tokenB;

    address alice = vm.addr(1);

    function setUp() public {
        vault = VaultMockDeployer.deploy();
        factory = new WeightedPool8020Factory(IVault(address(vault)), 365 days, "Factory v1", "8020Pool v1");

        tokenA = new ERC20TestToken("Token A", "TKNA", 18);
        tokenB = new ERC20TestToken("Token B", "TKNB", 6);
    }

    function _createPool(IERC20 highToken, IERC20 lowToken) private returns (WeightedPool) {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        PoolRoleAccounts memory roleAccounts;
        tokenConfig[0].token = highToken;
        tokenConfig[1].token = lowToken;

        // The factory will sort the tokens.
        return WeightedPool(factory.create(tokenConfig[0], tokenConfig[1], roleAccounts, DEFAULT_SWAP_FEE));
    }

    function testFactoryPausedState() public view {
        uint32 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testPoolFetching() public {
        WeightedPool pool = _createPool(tokenA, tokenB);
        address expectedPoolAddress = factory.getPool(tokenA, tokenB);

        bytes32 salt = keccak256(abi.encode(block.chainid, tokenA, tokenB));
        address deploymentAddress = factory.getDeploymentAddress(salt);

        assertEq(address(pool), expectedPoolAddress, "Wrong pool address");
        assertEq(deploymentAddress, expectedPoolAddress, "Wrong deployment address");
    }

    function testPoolCreation() public {
        (uint256 highWeightIdx, uint256 lowWeightIdx) = tokenA > tokenB ? (1, 0) : (0, 1);

        WeightedPool pool = _createPool(tokenA, tokenB);

        uint256[] memory poolWeights = pool.getNormalizedWeights();
        assertEq(poolWeights[highWeightIdx], 80e16, "Higher weight token is not 80%");
        assertEq(poolWeights[lowWeightIdx], 20e16, "Lower weight token is not 20%");
        assertEq(pool.name(), "Balancer 80 TKNA 20 TKNB", "Wrong pool name");
        assertEq(pool.symbol(), "B-80TKNA-20TKNB", "Wrong pool symbol");
    }

    function testPoolWithInvertedWeights() public {
        WeightedPool pool = _createPool(tokenA, tokenB);
        WeightedPool invertedPool = _createPool(tokenB, tokenA);

        assertFalse(
            address(pool) == address(invertedPool),
            "Pools with same tokens but different weights should be different"
        );
    }

    function testPoolUniqueness() public {
        _createPool(tokenA, tokenB);

        // Should not be able to deploy identical pool
        vm.expectRevert("DEPLOYMENT_FAILED");
        _createPool(tokenA, tokenB);

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        PoolRoleAccounts memory roleAccounts;

        tokenConfig[0].token = tokenA;
        tokenConfig[0].rateProvider = IRateProvider(address(1));
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].token = tokenB;
        tokenConfig[1].rateProvider = IRateProvider(address(2));
        tokenConfig[1].tokenType = TokenType.WITH_RATE;

        // Trying to create the same pool with same tokens but different token configs should revert
        vm.expectRevert("DEPLOYMENT_FAILED");
        factory.create(tokenConfig[0], tokenConfig[1], roleAccounts, DEFAULT_SWAP_FEE);
    }

    /// forge-config: default.fuzz.runs = 10
    function testPoolCrossChainProtection_Fuzz(uint16 chainId) public {
        // Eliminate the test chain.
        vm.assume(chainId != 31337);

        vm.prank(alice);
        WeightedPool poolMainnet = _createPool(tokenA, tokenB);

        vm.chainId(chainId);

        vm.prank(alice);
        WeightedPool poolL2 = _createPool(tokenA, tokenB);

        // Same salt parameters, should still be different because of the chainId.
        assertFalse(address(poolL2) == address(poolMainnet), "L2 and mainnet pool addresses are equal");
    }
}
