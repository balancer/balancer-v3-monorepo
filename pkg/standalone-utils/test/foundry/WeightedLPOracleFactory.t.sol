// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import {
    IWeightedLPOracleFactory
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracleFactory.sol";
import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracle.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import {
    WeightedPoolContractsDeployer
} from "@balancer-labs/v3-pool-weighted/test/foundry/utils/WeightedPoolContractsDeployer.sol";

import { FeedMock } from "../../contracts/test/FeedMock.sol";
import { WeightedLPOracleFactory } from "../../contracts/WeightedLPOracleFactory.sol";
import { WeightedLPOracleMock } from "../../contracts/test/WeightedLPOracleMock.sol";

contract WeightedLPOracleFactoryTest is BaseVaultTest, WeightedPoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    uint256 constant ORACLE_VERSION = 1;

    WeightedPoolFactory _weightedPoolFactory;
    WeightedLPOracleFactory _weightedLPOracleFactory;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        _weightedLPOracleFactory = new WeightedLPOracleFactory(vault, ORACLE_VERSION);

        _weightedPoolFactory = deployWeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function createFeeds(IWeightedPool pool) internal returns (AggregatorV3Interface[] memory feeds) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        feeds = new AggregatorV3Interface[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            feeds[i] = AggregatorV3Interface(address(new FeedMock(IERC20Metadata(address(tokens[i])).decimals())));
        }
    }

    function createAndInitPool() internal returns (IWeightedPool) {
        return
            createAndInitPool(
                [poolInitAmount, poolInitAmount].toMemoryArray(),
                [50e16, uint256(50e16)].toMemoryArray(),
                vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20())
            );
    }

    function createAndInitPool(
        uint256[] memory initAmounts,
        uint256[] memory weights,
        TokenConfig[] memory tokenConfigs
    ) internal returns (IWeightedPool) {
        string memory name = "Weighted Pool Test";
        string memory symbol = "WEIGHTED-TEST";

        PoolRoleAccounts memory roleAccounts;

        address newPool = _weightedPoolFactory.create(
            name,
            symbol,
            tokenConfigs,
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE_PERCENTAGE,
            address(0),
            true,
            false,
            bytes32("")
        );

        vm.startPrank(lp);
        _initPool(newPool, initAmounts, 0);
        vm.stopPrank();

        _setSwapFeePercentage(newPool, 0);

        return IWeightedPool(newPool);
    }

    function testCreateOracle() external {
        IWeightedPool pool = createAndInitPool();
        AggregatorV3Interface[] memory feeds = createFeeds(pool);

        uint256 snapshot = vm.snapshot();
        IWeightedLPOracle oracle = _weightedLPOracleFactory.create(pool, feeds);
        vm.revertTo(snapshot);

        vm.expectEmit();
        emit IWeightedLPOracleFactory.WeightedLPOracleCreated(pool, oracle);
        _weightedLPOracleFactory.create(pool, feeds);

        assertEq(address(oracle), address(_weightedLPOracleFactory.getOracle(pool)), "Oracle address mismatch");
        assertTrue(_weightedLPOracleFactory.isOracleFromFactory(oracle), "Oracle should be from factory");
    }

    function testCreateOracleRevertsWhenOracleAlreadyExists() external {
        IWeightedPool pool = createAndInitPool();
        AggregatorV3Interface[] memory feeds = createFeeds(pool);

        _weightedLPOracleFactory.create(pool, feeds);

        vm.expectRevert(IWeightedLPOracleFactory.OracleAlreadyExists.selector);
        _weightedLPOracleFactory.create(pool, feeds);
    }
}
