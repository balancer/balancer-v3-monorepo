// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { BaseTest } from "solidity-utils/test/foundry/utils/BaseTest.sol";

import { RateProviderMock } from "../../../contracts/test/RateProviderMock.sol";
import { VaultMock } from "../../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../../contracts/test/VaultExtensionMock.sol";
import { Router } from "../../../contracts/Router.sol";
import { VaultStorage } from "../../../contracts/VaultStorage.sol";
import { RouterMock } from "../../../contracts/test/RouterMock.sol";
import { PoolMock } from "../../../contracts/test/PoolMock.sol";

import { VaultMockDeployer } from "./VaultMockDeployer.sol";

abstract contract BaseVaultTest is VaultStorage, BaseTest {
    using ArrayHelpers for *;

    struct Balances {
        uint256[] userTokens;
        uint256 userBpt;
        uint256[] poolTokens;
    }

    bytes32 constant ZERO_BYTES32 = 0x0000000000000000000000000000000000000000000000000000000000000000;

    // Vault mock.
    IVaultMock internal vault;
    // Vault extension mock.
    VaultExtensionMock internal vaultExtension;
    // Router mock.
    RouterMock internal router;
    // Authorizer mock.
    BasicAuthorizerMock internal authorizer;
    // Pool for tests.
    address internal pool;
    // Rate provider mock.
    RateProviderMock internal rateProvider;

    // Default amount to use in tests for user operations.
    uint256 internal defaultAmount = 1e3 * 1e18;
    // Default amount round up.
    uint256 internal defaultAmountRoundUp = defaultAmount + 1;
    // Default amount round down.
    uint256 internal defaultAmountRoundDown = defaultAmount - 1;
    // Default amount of BPT to use in tests for user operations.
    uint256 internal bptAmount = 2e3 * 1e18;
    // Default amount of BPT round down.
    uint256 internal bptAmountRoundDown = bptAmount - 1;
    // Amount to use to init the mock pool.
    uint256 internal poolInitAmount = 1e3 * 1e18;
    // Default rate for the rate provider mock.
    uint256 internal mockRate = 2e18;
    // Default swap fee percentage.
    uint256 internal swapFeePercentage = 0.01e18; // 1%
    // Default protocol swap fee percentage.
    uint256 internal protocolSwapFeePercentage = 0.50e18; // 50%

    function setUp() public virtual override {
        BaseTest.setUp();

        vault = IVaultMock(address(VaultMockDeployer.deploy()));
        authorizer = BasicAuthorizerMock(address(vault.getAuthorizer()));
        router = new RouterMock(IVault(address(vault)), weth);
        pool = createPool();

        // Approve vault allowances
        approveVault(admin);
        approveVault(lp);
        approveVault(alice);
        approveVault(bob);
        approveVault(broke);

        // Add initial liquidity
        initPool();
    }

    function approveVault(address user) internal {
        vm.startPrank(user);

        for (uint256 index = 0; index < tokens.length; index++) {
            tokens[index].approve(address(vault), type(uint256).max);
        }

        vm.stopPrank();
    }

    function initPool() internal virtual {
        (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(address(pool));
        vm.prank(lp);
        router.initialize(address(pool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, "");
    }

    function createPool() internal virtual returns (address) {
        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "pool");
        return address(newPool);
    }

    function setSwapFeePercentage(uint256 percentage) internal {
        authorizer.grantRole(vault.getActionId(IVaultExtension.setStaticSwapFeePercentage.selector), admin);
        vm.prank(admin);
        vault.setStaticSwapFeePercentage(address(pool), percentage);
    }

    function setProtocolSwapFeePercentage(uint256 percentage) internal {
        authorizer.grantRole(vault.getActionId(IVaultExtension.setProtocolSwapFeePercentage.selector), admin);
        vm.prank(admin);
        vault.setProtocolSwapFeePercentage(percentage);
    }

    function getBalances(address user) internal view returns (Balances memory balances) {
        balances.userTokens = new uint256[](2);

        balances.userTokens[0] = dai.balanceOf(user);
        balances.userTokens[1] = usdc.balanceOf(user);
        balances.userBpt = PoolMock(pool).balanceOf(user);

        (, , uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        balances.poolTokens = poolBalances;
    }
}
