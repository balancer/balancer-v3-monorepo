// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

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
import { FeedMock } from "../../contracts/test/FeedMock.sol";

contract StableLPOracleFactoryTest is BaseVaultTest, StablePoolContractsDeployer {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    uint256 constant ORACLE_VERSION = 1;
    uint256 constant AMPLIFICATION_PARAMETER = 100;

    StablePoolFactory _stablePoolFactory;
    StableLPOracleFactory _stableLPOracleFactory;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        _stableLPOracleFactory = new StableLPOracleFactory(vault, ORACLE_VERSION);

        _stablePoolFactory = deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
    }

    function createFeeds(IStablePool pool) internal returns (AggregatorV3Interface[] memory feeds) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        feeds = new AggregatorV3Interface[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            feeds[i] = AggregatorV3Interface(address(new FeedMock(IERC20Metadata(address(tokens[i])).decimals())));
        }
    }

    function createAndInitPool() internal returns (IStablePool) {
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
    ) internal returns (IStablePool) {
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

        return IStablePool(newPool);
    }

    function testCreateOracle() external {
        IStablePool pool = createAndInitPool();
        AggregatorV3Interface[] memory feeds = createFeeds(pool);

        uint256 snapshot = vm.snapshot();
        ILPOracleBase oracle = _stableLPOracleFactory.create(IBasePool(address(pool)), feeds);
        vm.revertTo(snapshot);

        vm.expectEmit();
        emit StableLPOracleFactory.StableLPOracleCreated(pool, ILPOracleBase(address(oracle)));
        _stableLPOracleFactory.create(IBasePool(address(pool)), feeds);

        assertEq(
            address(oracle),
            address(_stableLPOracleFactory.getOracle(IBasePool(address(pool)))),
            "Oracle address mismatch"
        );
        assertTrue(_stableLPOracleFactory.isOracleFromFactory(oracle), "Oracle should be from factory");
    }

    function testCreateOracleRevertsWhenOracleAlreadyExists() external {
        IStablePool pool = createAndInitPool();
        AggregatorV3Interface[] memory feeds = createFeeds(pool);

        _stableLPOracleFactory.create(IBasePool(address(pool)), feeds);

        vm.expectRevert(ILPOracleFactoryBase.OracleAlreadyExists.selector);
        _stableLPOracleFactory.create(IBasePool(address(pool)), feeds);
    }
}
