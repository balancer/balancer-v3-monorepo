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
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { PoolMock } from "../../../../contracts/test/PoolMock.sol";
import { Router } from "../../../../contracts/Router.sol";
import { RouterCommon } from "../../../../contracts/RouterCommon.sol";
import { VaultMock } from "../../../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "../../utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

contract BatchRouterMutationTest is BaseVaultTest {
    using ArrayHelpers for *;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testSwapExactInHookWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths;

        IBatchRouter.SwapExactInHookParams memory params = IBatchRouter.SwapExactInHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.swapExactInHook(params);
    }

    function testSwapExactOutHookWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths;
        IBatchRouter.SwapExactOutHookParams memory params = IBatchRouter.SwapExactOutHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.swapExactOutHook(params);
    }

    function testQuerySwapExactInHookWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountIn[] memory paths;

        IBatchRouter.SwapExactInHookParams memory params = IBatchRouter.SwapExactInHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.querySwapExactInHook(params);
    }

    function testQuerySwapExactOutWhenNotVault() public {
        IBatchRouter.SwapPathExactAmountOut[] memory paths;
        IBatchRouter.SwapExactOutHookParams memory params = IBatchRouter.SwapExactOutHookParams(
            address(0),
            paths,
            0,
            false,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.SenderIsNotVault.selector, address(this)));
        batchRouter.querySwapExactOutHook(params);
    }
}
