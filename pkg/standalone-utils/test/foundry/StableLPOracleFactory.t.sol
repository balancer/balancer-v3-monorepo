// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleFactoryBase.sol";
import { PoolRoleAccounts, TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IStablePool } from "@balancer-labs/v3-interfaces/contracts/pool-stable/IStablePool.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import {
    StablePoolContractsDeployer
} from "@balancer-labs/v3-pool-stable/test/foundry/utils/StablePoolContractsDeployer.sol";

import { StableLPOracleFactory } from "../../contracts/StableLPOracleFactory.sol";
import { LPOracleFactoryBaseTest } from "./LPOracleFactoryBase.t.sol";

contract StableLPOracleFactoryTest is StablePoolContractsDeployer, LPOracleFactoryBaseTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    uint256 constant ORACLE_VERSION = 1;
    uint256 constant AMPLIFICATION_PARAMETER = 100;

    StablePoolFactory _stablePoolFactory;

    function setUp() public virtual override {
        super.setUp();

        _stablePoolFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function testCreateEmitsEvent() external {
        IBasePool pool = _createAndInitPool();
        AggregatorV3Interface[] memory feeds = _createFeeds(pool);

        // Snapshot is needed to predict what will be the oracle address.
        uint256 snapshot = vm.snapshotState();
        ILPOracleBase oracle = _factory.create(pool, feeds);
        vm.revertToState(snapshot);

        vm.expectEmit();
        emit StableLPOracleFactory.StableLPOracleCreated(IStablePool(address(pool)), feeds, oracle);
        _factory.create(pool, feeds);
    }

    function _createAndInitPool() internal override returns (IBasePool) {
        return
            _createAndInitPool(
                [poolInitAmount, poolInitAmount].toMemoryArray(),
                vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20())
            );
    }

    function _createAndInitPool(
        uint256[] memory initAmounts,
        TokenConfig[] memory tokenConfigs
    ) internal returns (IBasePool) {
        string memory name = "Stable Pool Test";
        string memory symbol = "STABLE-TEST";

        PoolRoleAccounts memory roleAccounts;

        address newPool = _stablePoolFactory.create(
            name,
            symbol,
            tokenConfigs,
            AMPLIFICATION_PARAMETER,
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
        return ILPOracleFactoryBase(address(new StableLPOracleFactory(vault, ORACLE_VERSION)));
    }
}
