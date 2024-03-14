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
        // revoke user approval for users
        approveRouter(alice, aliceKey, false, 0);
    }

    function testApproveRouterByUser() public {
        assertEq(vault.isTrustedRouter(address(router), alice), false);

        bytes memory signature = getApproveRouterSignature(alice, aliceKey, true, 0);
        vm.prank(alice);
        router.approveRouter(true, type(uint256).max, signature);

        assertEq(vault.isTrustedRouter(address(router), alice), true);
    }

    function testApproveRouterByUserAndSwap() public {
        assertEq(vault.isTrustedRouter(address(router), alice), false);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            IRouter.approveRouter.selector,
            true,
            type(uint256).max,
            getApproveRouterSignature(alice, aliceKey, true, 0)
        );
        data[1] = abi.encodeWithSelector(
            IRouter.swapSingleTokenExactIn.selector,
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.multicall(data);

        assertEq(vault.isTrustedRouter(address(router), alice), true);
    }

    function testOneTimeApproveByUser() public {
        assertEq(vault.isTrustedRouter(address(router), alice), false);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(
            IRouter.approveRouter.selector,
            true,
            type(uint256).max,
            getApproveRouterSignature(alice, aliceKey, true, 0)
        );
        data[1] = abi.encodeWithSelector(
            IRouter.swapSingleTokenExactIn.selector,
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );
        data[2] = abi.encodeWithSelector(
            IRouter.approveRouter.selector,
            false,
            type(uint256).max,
            getApproveRouterSignature(alice, aliceKey, false, 1)
        );

        vm.prank(alice);
        router.multicall(data);

        assertEq(vault.isTrustedRouter(address(router), alice), false);
    }
}
