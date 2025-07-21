// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWeightedLPOracle } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IWeightedLPOracle.sol";
import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleFactoryBase.sol";
import { PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import {
    WeightedPoolContractsDeployer
} from "@balancer-labs/v3-pool-weighted/test/foundry/utils/WeightedPoolContractsDeployer.sol";

import { WeightedLPOracleFactory } from "../../contracts/WeightedLPOracleFactory.sol";
import { FeedMock } from "../../contracts/test/FeedMock.sol";
import { LPOracleFactoryBaseTest } from "./LPOracleFactoryBase.t.sol";

contract WeightedLPOracleFactoryTest is WeightedPoolContractsDeployer, LPOracleFactoryBaseTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    uint256 constant ORACLE_VERSION = 1;

    WeightedPoolFactory _weightedPoolFactory;

    function setUp() public virtual override {
        super.setUp();

        _weightedPoolFactory = deployWeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function testCreateEmitsEvent() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        // Snapshot is needed to predict what will be the oracle address.
        uint256 snapshot = vm.snapshotState();
        ILPOracleBase oracle = _factory.create(pool, feeds);
        vm.revertToState(snapshot);

        vm.expectEmit();
        emit WeightedLPOracleFactory.WeightedLPOracleCreated(
            IWeightedPool(address(pool)),
            feeds,
            IWeightedLPOracle(address(oracle))
        );
        _factory.create(pool, feeds);
    }

    function _createAndInitPool() internal override returns (IBasePool) {
        return
            _createAndInitPool(
                [poolInitAmount, poolInitAmount].toMemoryArray(),
                [50e16, uint256(50e16)].toMemoryArray(),
                vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20())
            );
    }

    function _createAndInitPool(
        uint256[] memory initAmounts,
        uint256[] memory weights,
        TokenConfig[] memory tokenConfigs
    ) internal returns (IBasePool) {
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

        return IBasePool(newPool);
    }

    function _createOracleFactory() internal override returns (ILPOracleFactoryBase) {
        return ILPOracleFactoryBase(address(new WeightedLPOracleFactory(vault, ORACLE_VERSION)));
    }
}
