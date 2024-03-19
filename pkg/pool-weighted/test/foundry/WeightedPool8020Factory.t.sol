// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, TokenType } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { WeightedPool8020Factory } from "../../contracts/WeightedPool8020Factory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

contract WeightedPool8020FactoryTest is Test {
    VaultMock vault;
    WeightedPool8020Factory factory;
    RateProviderMock rateProvider;
    ERC20TestToken tokenA;
    ERC20TestToken tokenB;
    ERC20TestToken tokenC;

    address alice = vm.addr(1);
    address governance = vm.addr(2);

    event TokenConfigAllowlisted(TokenConfig tokenConfig);

    function setUp() public {
        vault = VaultMockDeployer.deploy();
        factory = new WeightedPool8020Factory(IVault(address(vault)), 365 days);

        tokenA = new ERC20TestToken("Token A", "TKNA", 18);
        tokenB = new ERC20TestToken("Token B", "TKNB", 6);
        tokenC = new ERC20TestToken("Token C", "TKNC", 18);

        _grantSetTokenConfigPermissions(governance);
        _allowlistTokenConfig(IERC20(tokenB));
    }

    function _grantSetTokenConfigPermissions(address admin) internal {
        BasicAuthorizerMock authorizer = BasicAuthorizerMock(address(factory.getAuthorizer()));
        bytes32 actionId = factory.getActionId(WeightedPool8020Factory.allowlistTokenConfig.selector);
        authorizer.grantRole(actionId, admin);
    }

    function _allowlistTokenConfig(IERC20 lowWeightToken) internal {
        TokenConfig memory lowWeightTokenConfig = TokenConfig({
            token: lowWeightToken,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            yieldFeeExempt: false
        });
        vm.prank(governance);
        factory.allowlistTokenConfig(lowWeightTokenConfig);
    }

    function testTokenConfigReverts() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[1].token = tokenB;
        tokens[0].tokenType = TokenType.WITH_RATE;

        vm.expectRevert(WeightedPool8020Factory.HighWeightTokenMustBeStandard.selector);
        WeightedPool(factory.create(tokens[0], tokens[1].token));

        tokens[0].tokenType = TokenType.STANDARD;
        tokens[1].token = tokenC;

        vm.expectRevert(WeightedPool8020Factory.TokenConfigNotAllowlisted.selector);
        WeightedPool(factory.create(tokens[0], tokens[1].token));
    }

    function testTokenConfigSetterAndGetter() public {
        TokenConfig memory expectedTokenConfig = TokenConfig({
            token: tokenC,
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(0)),
            yieldFeeExempt: false
        });

        vm.expectEmit(true, true, true, true, address(factory));
        emit TokenConfigAllowlisted(expectedTokenConfig);

        _allowlistTokenConfig(tokenC);

        TokenConfig memory tokenConfig = factory.getTokenConfig(tokenC);
        assertEq(address(tokenConfig.token), address(expectedTokenConfig.token));
        assertEq(uint256(tokenConfig.tokenType), uint256(expectedTokenConfig.tokenType));
        assertEq(address(tokenConfig.rateProvider), address(expectedTokenConfig.rateProvider));
        assertEq(tokenConfig.yieldFeeExempt, expectedTokenConfig.yieldFeeExempt);

        TokenConfig memory nonAllowlistedConfig = factory.getTokenConfig(tokenA);
        assertEq(address(nonAllowlistedConfig.token), address(0));
    }

    function testFactoryPausedState() public {
        uint256 pauseWindowDuration = factory.getPauseWindowDuration();
        assertEq(pauseWindowDuration, 365 days);
    }

    function testPoolFetching() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[0].rateProvider = rateProvider;
        tokens[1].token = tokenB;

        WeightedPool pool = WeightedPool(factory.create(tokens[0], tokens[1].token));
        address expectedPoolAddress = factory.getPool(tokenA, tokenB);

        bytes32 salt = keccak256(abi.encode(block.chainid, tokenA, tokenB));
        address deploymentAddress = factory.getDeploymentAddress(salt);

        assertEq(address(pool), expectedPoolAddress, "Unexpected pool address");
        assertEq(deploymentAddress, expectedPoolAddress, "Unexpected deployment address");
    }

    function testPoolCreation() public {
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[1].token = tokenB;
        uint256 highWeightIdx = tokenA > tokenB ? 1 : 0;
        uint256 lowWeightIdx = highWeightIdx == 0 ? 1 : 0;

        WeightedPool pool = WeightedPool(factory.create(tokens[0], tokens[1].token));

        uint256[] memory poolWeights = pool.getNormalizedWeights();
        assertEq(poolWeights[highWeightIdx], 8e17, "Higher weight token is not 80%");
        assertEq(poolWeights[lowWeightIdx], 2e17, "Lower weight token is not 20%");
        assertEq(pool.name(), "Balancer 80 TKNA 20 TKNB", "Wrong pool name");
        assertEq(pool.symbol(), "B-80TKNA-20TKNB", "Wrong pool symbol");
    }

    function testPoolWithInvertedWeights() public {
        IERC20 highWeightToken = IERC20(tokenA);
        IERC20 lowWeightToken = IERC20(tokenB);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = highWeightToken;
        tokens[1].token = lowWeightToken;

        WeightedPool pool = WeightedPool(factory.create(tokens[0], tokens[1].token));

        _allowlistTokenConfig(tokens[0].token);

        WeightedPool invertedPool = WeightedPool(factory.create(tokens[1], tokens[0].token));

        assertFalse(
            address(pool) == address(invertedPool),
            "Pools with same tokens but different weight distributions should be different"
        );
    }

    function testPoolUniqueness() public {
        IERC20 highWeightToken = IERC20(tokenA);
        IERC20 lowWeightToken = IERC20(tokenB);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = highWeightToken;
        tokens[1].token = lowWeightToken;

        WeightedPool(factory.create(tokens[0], tokens[1].token));

        vm.expectRevert("DEPLOYMENT_FAILED");
        WeightedPool(factory.create(tokens[0], tokens[1].token));

        tokens[0].rateProvider = IRateProvider(address(1));

        // Trying to create the same pool with same highWeightToken but different token config should revert
        vm.expectRevert("DEPLOYMENT_FAILED");
        WeightedPool(factory.create(tokens[0], tokens[1].token));
    }

    function testPoolCrossChainProtection_Fuzz(uint16 chainId) public {
        vm.assume(chainId != 31337);

        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = tokenA;
        tokens[1].token = tokenB;
        tokens[0].rateProvider = rateProvider;

        vm.prank(alice);
        WeightedPool poolMainnet = WeightedPool(factory.create(tokens[0], tokens[1].token));

        vm.chainId(chainId);

        vm.prank(alice);
        WeightedPool poolL2 = WeightedPool(factory.create(tokens[0], tokens[1].token));

        // Same salt parameters, should still be different because of the chainId.
        assertFalse(address(poolL2) == address(poolMainnet), "L2 and mainnet pool addresses are equal");
    }
}
