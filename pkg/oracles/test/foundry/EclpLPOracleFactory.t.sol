// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleFactoryBase.sol";
import { IGyroECLPPool } from "@balancer-labs/v3-interfaces/contracts/pool-gyro/IGyroECLPPool.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { GyroEclpPoolDeployer } from "@balancer-labs/v3-pool-gyro/test/foundry/utils/GyroEclpPoolDeployer.sol";
import { GyroECLPPoolFactory } from "@balancer-labs/v3-pool-gyro/contracts/GyroECLPPoolFactory.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { EclpLPOracleFactory } from "../../contracts/EclpLPOracleFactory.sol";
import { LPOracleFactoryBaseTest } from "./LPOracleFactoryBase.t.sol";

contract EclpLPOracleFactoryTest is GyroEclpPoolDeployer, LPOracleFactoryBaseTest {
    using ArrayHelpers for *;

    GyroECLPPoolFactory _eclpPoolFactory;

    function setUp() public virtual override {
        super.setUp();

        _eclpPoolFactory = deployGyroECLPPoolFactory(IVault(address(vault)));
    }

    function testCreateEmitsEvent() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        // Snapshot is needed to predict what will be the oracle address.
        uint256 snapshot = vm.snapshotState();
        ILPOracleBase oracle = _factory.create(pool, feeds);
        vm.revertToState(snapshot);

        vm.expectEmit();
        emit EclpLPOracleFactory.EclpLPOracleCreated(
            IGyroECLPPool(address(pool)),
            feeds,
            ILPOracleBase(address(oracle))
        );
        _factory.create(pool, feeds);
    }

    function _createAndInitPool() internal override returns (IBasePool) {
        string memory name = "ECLP Pool Test";

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        address[] memory tokens = [address(dai), address(usdc)].toMemoryArray();

        (address newPool, ) = createGyroEclpPool(tokens, rateProviders, name, vault, lp);

        vm.startPrank(lp);
        _initPool(newPool, [poolInitAmount, poolInitAmount].toMemoryArray(), 0);
        vm.stopPrank();

        _setSwapFeePercentage(newPool, 0);

        return IBasePool(newPool);
    }

    function _createOracleFactory() internal override returns (ILPOracleFactoryBase) {
        return
            ILPOracleFactoryBase(
                address(
                    new EclpLPOracleFactory(
                        vault,
                        _uptimeFeed,
                        UPTIME_RESYNC_WINDOW,
                        ORACLE_FACTORY_VERSION,
                        ORACLE_VERSION
                    )
                )
            );
    }
}
