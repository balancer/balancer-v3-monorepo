// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleFactoryBase.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { FeedMock } from "../../contracts/test/FeedMock.sol";

abstract contract LPOracleFactoryBaseTest is BaseVaultTest {
    ILPOracleFactoryBase internal _factory;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _factory = _createOracleFactory();

        authorizer.grantRole(
            IAuthentication(address(_factory)).getActionId(ILPOracleFactoryBase.disable.selector),
            admin
        );

        authorizer.grantRole(
            IAuthentication(address(_factory)).getActionId(ILPOracleFactoryBase.disableOracleFromPool.selector),
            admin
        );
    }

    function testCreateOracle() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, feeds);

        assertEq(address(oracle), address(_factory.getOracle(IBasePool(address(pool)))), "Oracle address mismatch");
        assertTrue(_factory.isOracleFromFactory(oracle), "Oracle should be from factory");
    }

    function testCreateOracleRevertsWhenOracleAlreadyExists() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, feeds);

        // Since there already is an oracle for the pool in the factory, reverts with the correct parameters.
        vm.expectRevert(abi.encodeWithSelector(ILPOracleFactoryBase.OracleAlreadyExists.selector, pool, oracle));
        _factory.create(pool, feeds);
    }

    function testDisableOracleFromPool() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, feeds);

        // Since there already is an oracle for the pool in the factory, reverts with the correct parameters.
        vm.expectRevert(abi.encodeWithSelector(ILPOracleFactoryBase.OracleAlreadyExists.selector, pool, oracle));
        _factory.create(pool, feeds);

        vm.prank(admin);
        _factory.disableOracleFromPool(pool);

        assertEq(address(_factory.getOracle(pool)), address(0), "Oracle should not exist");

        ILPOracleBase newOracle = _factory.create(pool, feeds);

        assertEq(address(_factory.getOracle(pool)), address(newOracle), "Oracle should have been created");
    }

    function testDisableOracleFromPoolRevertsWhenOracleDoesNotExist() external {
        IBasePool pool = _createAndInitPool();

        // The oracle does not exist, so it should revert.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILPOracleFactoryBase.OracleDoesNotExists.selector, pool));
        _factory.disableOracleFromPool(pool);
    }

    function testDisableOracleFromPoolRevertsWhenFactoryIsDisabled() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        _factory.create(pool, feeds);

        vm.prank(admin);
        _factory.disable();

        // Since the oracle factory is disabled, it should not be possible to disable oracles.
        vm.prank(admin);
        vm.expectRevert(ILPOracleFactoryBase.OracleFactoryDisabled.selector);
        _factory.disableOracleFromPool(pool);
    }

    function testDisableOracleFromPoolIsAuthenticated() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, feeds);

        // Since the caller is not the admin, it should revert.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _factory.disableOracleFromPool(pool);
    }

    function testDisableIsDisabled() public {
        vm.prank(admin);
        _factory.disable();

        vm.expectRevert(ILPOracleFactoryBase.OracleFactoryDisabled.selector);
        _factory.create(IBasePool(address(123)), new AggregatorV3Interface[](0));
    }

    function testDisableIsAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _factory.disable();
    }

    function _createFeeds(IBasePool pool) internal returns (AggregatorV3Interface[] memory feeds) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        feeds = new AggregatorV3Interface[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            feeds[i] = AggregatorV3Interface(address(new FeedMock(IERC20Metadata(address(tokens[i])).decimals())));
        }
    }

    function _createOracleFactory() internal virtual returns (ILPOracleFactoryBase);

    function _createAndInitPool() internal virtual returns (IBasePool);
}
