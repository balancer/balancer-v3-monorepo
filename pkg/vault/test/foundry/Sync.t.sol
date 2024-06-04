// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Router } from "../../contracts/Router.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "./utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract SyncTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256[] internal amountsIn = [poolInitAmount, poolInitAmount].toMemoryArray();

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        // Test Dos attack with 1 wei, related: https://github.com/balancer/balancer-v3-monorepo/issues/580
        // TODO: Buffer tests

        // Token in always dai
        deal(address(dai), address(this), 1, false);
        dai.transfer(address(vault), 1);

        // Token out always usdc
        deal(address(usdc), address(this), 1, false);
        usdc.transfer(address(usdc), 1);
    }

    /*
      Router
    */
    function testAddLiquidityProportionalDos() public {
        vm.prank(alice);

        router.addLiquidityProportional(pool, amountsIn, amountsIn[0], false, bytes(""));
    }

    function testAddLiquidityUnbalanced() public {
        vm.prank(alice);

        router.addLiquidityUnbalanced(pool, amountsIn, amountsIn[0], false, bytes(""));
    }

    function testAddLiquiditySingleTokenExactOut() public {
        vm.prank(alice);

        router.addLiquiditySingleTokenExactOut(pool, dai, amountsIn[0], amountsIn[0], false, bytes(""));
    }

    function testAddLiquidityCustomDos() public {
        vm.prank(alice);

        router.addLiquidityCustom(pool, amountsIn, amountsIn[0], false, bytes(""));
    }

    // addLiquidityHook?

    // Minimum error, need to work on bptAmountIn
    function testRemoveLiquidityProportionalDos() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquidityProportional(pool, (amountsIn[0] + 1) * 2, amountsIn, false, bytes(""));
    }

    function testRemoveLiquiditySingleTokenExactInDos() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquiditySingleTokenExactIn(pool, amountsIn[0], usdc, 1, false, bytes(""));
    }

    function testRemoveLiquiditySingleTokenExactOut() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquiditySingleTokenExactOut(pool, amountsIn[0], usdc, 1, false, bytes(""));
    }

    function testRemoveLiquidityCustomDos() public {
        _addLiquidity();

        vm.prank(alice);

        router.removeLiquidityCustom(pool, amountsIn[0], amountsIn, false, bytes(""));
    }

    function testRemoveLiquidityRecoveryDos() public {
        authorizer.grantRole(vault.getActionId(IVaultAdmin.enableRecoveryMode.selector), admin);

        vm.prank(admin);
        vault.enableRecoveryMode(pool);

        _addLiquidity();

        vm.prank(alice);

        router.removeLiquidityRecovery(pool, amountsIn[0]);
    }

    // removeLiquidityHook
    // removeLiquidityRecoveryHook

    function testSwapSingleTokenExactIn() public {
        _addLiquidity();

        vm.prank(bob);
        router.swapSingleTokenExactIn(pool, dai, usdc, amountsIn[0], amountsIn[0], block.timestamp, false, bytes(""));
    }

    function testSwapSingleTokenExactOut() public {
        _addLiquidity();

        vm.prank(bob);
        router.swapSingleTokenExactOut(pool, dai, usdc, amountsIn[0], amountsIn[0], block.timestamp, false, bytes(""));
    }

    function _addLiquidity() internal {
        vm.prank(alice);

        router.addLiquidityProportional(pool, amountsIn, amountsIn[0], false, bytes(""));
    }
}
