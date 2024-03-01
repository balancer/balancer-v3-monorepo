// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Router } from "../../contracts/Router.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "./utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract TrustedRouterTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6;
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
    uint256 internal ethAmountIn = 1e3 ether;
    uint256 internal initBpt = 10e18;
    uint256 internal bptAmountOut = 1e18;

    PoolMock internal wethPool;
    PoolMock internal wethPoolNoInit;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
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

        wethPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(wethPool), "wethPool");

        wethPoolNoInit = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(wethPoolNoInit), "wethPoolNoInit");

        return address(newPool);
    }

    function initPool() internal override {
        (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(address(pool));
        vm.prank(lp);
        router.initialize(address(pool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, "");

        vm.prank(lp);
        bool wethIsEth = true;
        router.initialize{ value: ethAmountIn }(
            address(wethPool),
            [address(weth), address(dai)].toMemoryArray().asIERC20(),
            [uint256(ethAmountIn), uint256(daiAmountIn)].toMemoryArray(),
            initBpt,
            wethIsEth,
            bytes("")
        );
    }

    function testApproveRouter() public {
        assertEq(vault.isTrustedRouter(address(router), alice), true);

        bytes32 digest = vault.getRouterApprovalDigest(alice, address(router), false, type(uint256).max);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        // note the order here is different from line above.
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(alice);
        router.approveRouter(false, type(uint256).max, signature);

        assertEq(vault.isTrustedRouter(address(router), alice), false);
    }

    function testApproveRouterAndSwap() public {
        assertEq(vault.isTrustedRouter(address(router), alice), true);

        bytes32 digest = vault.getRouterApprovalDigest(alice, address(router), false, type(uint256).max);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        // note the order here is different from line above.
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(alice);
        router.approveRouter(false, type(uint256).max, signature);

        assertEq(vault.isTrustedRouter(address(router), alice), false);
    }
}
