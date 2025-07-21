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
    }

    function testCreateOracle() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, feeds);

        assertEq(
            address(oracle),
            address(_factory.getOracle(IBasePool(address(pool)), feeds)),
            "Oracle address mismatch"
        );
        assertTrue(_factory.isOracleFromFactory(oracle), "Oracle should be from factory");
    }

    function testGetNonExistentOracle() external view {
        assertEq(address(_factory.getOracle(IBasePool(address(0x123)), new AggregatorV3Interface[](0))), address(0));
    }

    function testCreateOracleDifferentFeeds() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, feeds);

        assertEq(
            address(oracle),
            address(_factory.getOracle(IBasePool(address(pool)), feeds)),
            "Oracle address mismatch"
        );
        assertTrue(_factory.isOracleFromFactory(oracle), "Oracle should be from factory");

        AggregatorV3Interface[] memory feeds2 = _createFeeds(pool);

        ILPOracleBase oracle2 = _factory.create(pool, feeds2);

        assertEq(
            address(oracle2),
            address(_factory.getOracle(IBasePool(address(pool)), feeds2)),
            "Oracle address mismatch"
        );
        assertTrue(_factory.isOracleFromFactory(oracle2), "Oracle should be from factory");
    }

    function testCreateOracleRevertsWhenOracleAlreadyExists() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, feeds);

        // Since there already is an oracle for the pool in the factory, reverts with the correct parameters.
        vm.expectRevert(abi.encodeWithSelector(ILPOracleFactoryBase.OracleAlreadyExists.selector, pool, feeds, oracle));
        _factory.create(pool, feeds);
    }

    function testDisable() public {
        vm.prank(admin);
        _factory.disable();

        vm.expectRevert(ILPOracleFactoryBase.OracleFactoryIsDisabled.selector);
        _factory.create(IBasePool(address(123)), new AggregatorV3Interface[](0));

        // Revert the second time
        vm.prank(admin);
        vm.expectRevert(ILPOracleFactoryBase.OracleFactoryIsDisabled.selector);
        _factory.disable();
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
