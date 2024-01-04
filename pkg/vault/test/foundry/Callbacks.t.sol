// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IPoolCallbacks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolCallbacks.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";
import { RouterAdaptor } from "../../contracts/test/RouterAdaptor.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

import { VaultUtils } from "./utils/VaultUtils.sol";

contract CallbacksTest is VaultUtils {
    using ArrayHelpers for *;
    using RouterAdaptor for IRouter;

    function setUp() public virtual override {
        VaultUtils.setUp();

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterSwap = true;
        vault.setConfig(address(pool), config);
    }

    function testOnAfterSwapCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: IVault.SwapKind.GIVEN_IN,
                    tokenIn: IERC20(usdc),
                    tokenOut: IERC20(dai),
                    amountGivenScaled18: defaultAmount,
                    balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, 0, type(uint256).max, false, bytes(""));
    }

    function testOnAfterSwapCallbackRevert() public {
        // should fail
        pool.setFailOnAfterSwapCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVault.CallbackFailed.selector));
        router.swapExactIn(address(pool), usdc, dai, defaultAmount, defaultAmount, type(uint256).max, false, bytes(""));
    }

    // Before add

    function testOnBeforeAddLiquidityFlag() public {
        pool.setFailOnBeforeAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnBeforeAddLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeAddLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onBeforeAddLiquidity.selector,
                bob,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmountRoundDown,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    // Before remove

    function testOnBeforeRemoveLiquidityFlag() public {
        pool.setFailOnBeforeRemoveLiquidityCallback(true);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onBeforeRemoveLiquidity.selector,
                alice,
                bptAmount,
                [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    // After add

    function testOnAfterAddLiquidityFlag() public {
        pool.setFailOnAfterAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );
    }

    function testOnAfterAddLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterAddLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onAfterAddLiquidity.selector,
                bob,
                [defaultAmount, defaultAmount].toMemoryArray(),
                bptAmount,
                [2 * defaultAmount, 2 * defaultAmount].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmountRoundDown,
            false,
            bytes("")
        );
    }

    // After remove

    function testOnAfterRemoveLiquidityFlag() public {
        pool.setFailOnAfterRemoveLiquidityCallback(true);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(alice);
        router.addLiquidityUnbalanced(
            address(pool),
            [defaultAmount, defaultAmount].toMemoryArray(),
            bptAmount,
            false,
            bytes("")
        );

        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onAfterRemoveLiquidity.selector,
                alice,
                bptAmount,
                [defaultAmount, defaultAmount].toMemoryArray(),
                [defaultAmount, defaultAmount].toMemoryArray(),
                bytes("")
            )
        );

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            bptAmount,
            [defaultAmountRoundDown, defaultAmountRoundDown].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
