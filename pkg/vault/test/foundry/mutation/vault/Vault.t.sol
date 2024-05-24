// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BaseVaultTest } from "../../utils/BaseVaultTest.sol";
import {
    AddLiquidityParams,
    AddLiquidityKind,
    RemoveLiquidityParams,
    RemoveLiquidityKind,
    SwapParams,
    SwapKind
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract VaultMutationTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256[] internal amountsIn = [poolInitAmount, poolInitAmount].toMemoryArray();

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*
        settle
    */
    function testSettleWithLockedVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.settle(dai);
    }

    /*
        sendTo
    */
    function testSendToWithLockedVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.sendTo(dai, address(0), 1);
    }

    /*
        swap
    */
    function testSwapWithLockedVault() public {
        SwapParams memory params = SwapParams(SwapKind.EXACT_IN, address(pool), dai, usdc, 1, 0, bytes(""));

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.swap(params);
    }

    /*
        addLiquidity
    */
    function testAddLiquidityWithLockedVault() public {
        AddLiquidityParams memory params = AddLiquidityParams(
            address(pool),
            address(0),
            amountsIn,
            0,
            AddLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.addLiquidity(params);
    }

    /*
        removeLiquidity
    */
    function testRemoveLiquidityWithLockedVault() public {
        RemoveLiquidityParams memory params = RemoveLiquidityParams(
            address(pool),
            address(0),
            0,
            amountsIn,
            RemoveLiquidityKind.PROPORTIONAL,
            bytes("")
        );

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.VaultIsNotUnlocked.selector));
        vault.removeLiquidity(params);
    }
}
