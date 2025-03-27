// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";
import { ICowPoolFactory } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowPoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { PoolFactoryMock } from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { CowPoolContractsDeployer } from "./CowPoolContractsDeployer.sol";
import { CowRouter } from "../../../contracts/CowRouter.sol";
import { CowPoolFactory } from "../../../contracts/CowPoolFactory.sol";

contract BaseCowTest is CowPoolContractsDeployer, BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    uint256 internal constant _INITIAL_PROTOCOL_FEE_PERCENTAGE = 1e16;
    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%
    string internal constant POOL_VERSION = "CoW Pool v1";

    ICowRouter internal cowRouter;
    ICowPoolFactory internal cowFactory;
    address internal feeSweeper;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        // Set router permissions.
        authorizer.grantRole(
            CowRouter(address(cowRouter)).getActionId(ICowRouter.setProtocolFeePercentage.selector),
            admin
        );
        authorizer.grantRole(CowRouter(address(cowRouter)).getActionId(ICowRouter.setFeeSweeper.selector), admin);

        // Set factory permissions.
        authorizer.grantRole(
            CowPoolFactory(address(cowFactory)).getActionId(ICowPoolFactory.setTrustedCowRouter.selector),
            admin
        );

        _approveCowRouterForAllUsers();

        if (pool != address(0)) {
            approveCowRouterForPool(IERC20(pool));
        }
    }

    function createPoolFactory() internal override returns (address) {
        // Set fee sweeper before the router is created.
        feeSweeper = bob;

        // Creates cowRouter before the factory, so we have an address to set as trusted router.
        cowRouter = deployCowPoolRouter(vault, _INITIAL_PROTOCOL_FEE_PERCENTAGE, feeSweeper);

        cowFactory = deployCowPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            POOL_VERSION,
            address(cowRouter)
        );
        vm.label(address(cowFactory), "CoW Factory");

        return address(cowFactory);
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Cow AMM Pool";
        string memory symbol = "COWPOOL";
        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        IERC20[] memory sortedTokens = InputHelpers.sortTokens(tokens.asIERC20());

        PoolRoleAccounts memory roleAccounts;

        newPool = CowPoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(sortedTokens),
            weights,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            ZERO_BYTES32
        );
        vm.label(newPool, label);

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: sortedTokens.length,
                normalizedWeights: weights,
                version: POOL_VERSION
            }),
            vault,
            poolFactory,
            cowRouter
        );
    }

    function _approveCowRouterForAllUsers() private {
        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];
            vm.startPrank(user);
            approveCowRouterForSender();
            vm.stopPrank();
        }
    }

    function approveCowRouterForSender() internal {
        for (uint256 i = 0; i < tokens.length; ++i) {
            tokens[i].approve(address(cowRouter), type(uint160).max);
        }

        for (uint256 i = 0; i < erc4626Tokens.length; ++i) {
            erc4626Tokens[i].approve(address(cowRouter), type(uint160).max);
        }
    }

    function approveCowRouterForPool(IERC20 bpt) internal {
        for (uint256 i = 0; i < users.length; ++i) {
            vm.startPrank(users[i]);
            bpt.approve(address(cowRouter), type(uint256).max);
            vm.stopPrank();
        }
    }
}
