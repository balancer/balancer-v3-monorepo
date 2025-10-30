// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { ISequencerUptimeFeed } from "@balancer-labs/v3-interfaces/contracts/oracles/ISequencerUptimeFeed.sol";
import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleFactoryBase.sol";
import { IVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LPOracleBase } from "../../contracts/LPOracleBase.sol";
import { FeedMock } from "../../contracts/test/FeedMock.sol";

abstract contract LPOracleFactoryBaseTest is BaseVaultTest {
    string constant ORACLE_FACTORY_VERSION = "Factory v1";
    uint256 constant ORACLE_VERSION = 1;
    uint256 constant UPTIME_RESYNC_WINDOW = 1 hours;

    ILPOracleFactoryBase internal _factory;
    ILPOracleFactoryBase internal _factoryUseBlockTime;
    FeedMock internal _uptimeFeed;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _uptimeFeed = new FeedMock(18);
        // Default to indicating the feed has been up for a day.
        _uptimeFeed.setLastRoundData(0, block.timestamp - 1 days);

        _factory = _createOracleFactory();

        authorizer.grantRole(
            IAuthentication(address(_factory)).getActionId(ILPOracleFactoryBase.disable.selector),
            admin
        );
    }

    function testOracleFactoryVersion() public view {
        assertEq(IVersion(address(_factory)).version(), ORACLE_FACTORY_VERSION, "Wrong oracle factory version");
    }

    function testOracleVersion() public view {
        assertEq(_factory.getOracleVersion(), ORACLE_VERSION, "Wrong oracle version");
    }

    function testCreateOracle() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        bool shouldUseBlockTimeForOldestFeedUpdate = true;

        ILPOracleBase oracle = _factory.create(pool, shouldUseBlockTimeForOldestFeedUpdate, feeds);

        assertEq(
            address(oracle),
            address(_factory.getOracle(IBasePool(address(pool)), shouldUseBlockTimeForOldestFeedUpdate, feeds)),
            "Oracle address mismatch"
        );
        assertTrue(_factory.isOracleFromFactory(oracle), "Oracle should be from factory");
    }

    function testGetNonExistentOracle() external view {
        assertEq(
            address(_factory.getOracle(IBasePool(address(0x123)), false, new AggregatorV3Interface[](0))),
            address(0)
        );
    }

    function testCreateOracleDifferentFeeds() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        bool shouldUseBlockTimeForOldestFeedUpdate = false;

        ILPOracleBase oracle = _factory.create(pool, shouldUseBlockTimeForOldestFeedUpdate, feeds);

        assertEq(
            address(oracle),
            address(_factory.getOracle(IBasePool(address(pool)), shouldUseBlockTimeForOldestFeedUpdate, feeds)),
            "Oracle address mismatch"
        );
        assertTrue(_factory.isOracleFromFactory(oracle), "Oracle should be from factory");

        AggregatorV3Interface[] memory feeds2 = _createFeeds(pool);

        ILPOracleBase oracle2 = _factory.create(pool, shouldUseBlockTimeForOldestFeedUpdate, feeds2);

        assertEq(
            address(oracle2),
            address(_factory.getOracle(IBasePool(address(pool)), shouldUseBlockTimeForOldestFeedUpdate, feeds2)),
            "Oracle address mismatch"
        );
        assertTrue(_factory.isOracleFromFactory(oracle2), "Oracle2 should be from factory");
    }

    function testCreateOracleRevertsWhenOracleAlreadyExists() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        // Set updatedAt flag to true initially.
        ILPOracleBase oracle = _factory.create(pool, true, feeds);

        // Since there already is an oracle for the pool in the factory, reverts with the correct parameters.
        vm.expectRevert(
            abi.encodeWithSelector(ILPOracleFactoryBase.OracleAlreadyExists.selector, pool, true, feeds, oracle)
        );
        _factory.create(pool, true, feeds);

        // Can create an otherwise identical oracle with a different flag setting.
        _factory.create(pool, false, feeds);
    }

    function testDisable() public {
        vm.prank(admin);
        _factory.disable();

        vm.expectRevert(ILPOracleFactoryBase.OracleFactoryIsDisabled.selector);
        _factory.create(IBasePool(address(123)), false, new AggregatorV3Interface[](0));

        // Revert the second time
        vm.prank(admin);
        vm.expectRevert(ILPOracleFactoryBase.OracleFactoryIsDisabled.selector);
        _factory.disable();
    }

    function testDisableIsAuthenticated() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        _factory.disable();
    }

    function testGetRoundData() public {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        ILPOracleBase oracle = _factory.create(pool, false, feeds);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = LPOracleBase(
            address(oracle)
        ).getRoundData(0);
        assertEq(roundId, 0, "roundId not zero");
        assertEq(answer, 0, "answer not zero");
        assertEq(startedAt, 0, "startedAt not zero");
        assertEq(updatedAt, 0, "updatedAt not zero");
        assertEq(answeredInRound, 0, "answeredInRound not zero");
    }

    function testGetUptimeFeed() public view {
        assertEq(
            address(ISequencerUptimeFeed(address(_factory)).getSequencerUptimeFeed()),
            address(_uptimeFeed),
            "Wrong uptime feed"
        );
    }

    function testGetUptimeResyncWindow() public view {
        assertEq(
            ISequencerUptimeFeed(address(_factory)).getUptimeResyncWindow(),
            UPTIME_RESYNC_WINDOW,
            "Wrong uptime resync window"
        );
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
