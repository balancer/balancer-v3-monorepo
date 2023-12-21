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
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract CallbacksTest is Test {
    using ArrayHelpers for *;

    VaultMock vault;
    IRouter router;
    BasicAuthorizerMock authorizer;
    PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant MINIMUM_AMOUNT = 1e6;
    uint256 constant MINIMUM_AMOUNT_ROUND_UP = 1e6 + 1;

    uint256 constant BPT_AMOUNT = 1e3 * 1e18;
    uint256 constant BPT_AMOUNT_ROUND_DOWN = BPT_AMOUNT - 1;
    uint256 constant DEFAULT_AMOUNT = 1e3 * 1e18;
    uint256 constant DEFAULT_AMOUNT_ROUND_UP = DEFAULT_AMOUNT + 1;
    uint256 constant DEFAULT_AMOUNT_ROUND_DOWN = DEFAULT_AMOUNT - 1;

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), new WETHTestToken());
        USDC = new ERC20TestToken("USDC", "USDC", 18);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new PoolMock(
            vault,
            "ERC20 Pool",
            "ERC20POOL",
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            rateProviders,
            true,
            365 days,
            address(0)
        );

        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeSwap = true;
        config.callbacks.shouldCallAfterSwap = true;
        vault.setConfig(address(pool), config);

        USDC.mint(bob, DEFAULT_AMOUNT);
        DAI.mint(bob, DEFAULT_AMOUNT);

        USDC.mint(alice, DEFAULT_AMOUNT + MINIMUM_AMOUNT);
        DAI.mint(alice, DEFAULT_AMOUNT + MINIMUM_AMOUNT);

        vm.startPrank(bob);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        vm.stopPrank();

        vm.startPrank(alice);

        USDC.approve(address(vault), type(uint256).max);
        DAI.approve(address(vault), type(uint256).max);

        router.initialize(
            address(pool),
            [address(DAI), address(USDC)].toMemoryArray().asIERC20(),
            [MINIMUM_AMOUNT, MINIMUM_AMOUNT].toMemoryArray(),
            0,
            false,
            bytes("")
        );

        router.addLiquidityUnbalanced(
            address(pool),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            BPT_AMOUNT,
            false,
            bytes("")
        );

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testOnBeforeSwapCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: IVault.SwapKind.GIVEN_IN,
                    amountGivenScaled18: DEFAULT_AMOUNT,
                    balancesScaled18: [DEFAULT_AMOUNT + MINIMUM_AMOUNT, DEFAULT_AMOUNT + MINIMUM_AMOUNT]
                        .toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );
        router.swapSingleTokenExactIn(
            address(pool),
            USDC,
            DAI,
            DEFAULT_AMOUNT,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testOnBeforeSwapCallbackRevert() public {
        // should fail
        pool.setFailOnBeforeSwapCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVault.CallbackFailed.selector));
        router.swapSingleTokenExactIn(
            address(pool),
            USDC,
            DAI,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testOnAfterSwapCallback() public {
        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onSwap.selector,
                IBasePool.SwapParams({
                    kind: IVault.SwapKind.GIVEN_IN,
                    amountGivenScaled18: DEFAULT_AMOUNT,
                    balancesScaled18: [DEFAULT_AMOUNT + MINIMUM_AMOUNT, DEFAULT_AMOUNT + MINIMUM_AMOUNT]
                        .toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );
        router.swapSingleTokenExactIn(
            address(pool),
            USDC,
            DAI,
            DEFAULT_AMOUNT,
            0,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testOnAfterSwapCallbackRevert() public {
        // should fail
        pool.setFailOnAfterSwapCallback(true);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IVault.CallbackFailed.selector));
        router.swapSingleTokenExactIn(
            address(pool),
            USDC,
            DAI,
            DEFAULT_AMOUNT,
            DEFAULT_AMOUNT,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    // Before add

    function testOnBeforeAddLiquidityFlag() public {
        pool.setFailOnBeforeAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidityUnbalanced(
            address(pool),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            MINIMUM_AMOUNT,
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
                [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                BPT_AMOUNT_ROUND_DOWN,
                [DEFAULT_AMOUNT + MINIMUM_AMOUNT, DEFAULT_AMOUNT + MINIMUM_AMOUNT].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            address(pool),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    // Before remove

    function testOnBeforeRemoveLiquidityFlag() public {
        pool.setFailOnBeforeRemoveLiquidityCallback(true);

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            BPT_AMOUNT,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnBeforeRemoveLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onBeforeRemoveLiquidity.selector,
                alice,
                BPT_AMOUNT,
                [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
                [DEFAULT_AMOUNT + MINIMUM_AMOUNT, DEFAULT_AMOUNT + MINIMUM_AMOUNT].toMemoryArray(),
                bytes("")
            )
        );
        router.removeLiquidityProportional(
            address(pool),
            BPT_AMOUNT,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
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
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            MINIMUM_AMOUNT,
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
                [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
                BPT_AMOUNT_ROUND_DOWN,
                [2 * DEFAULT_AMOUNT + MINIMUM_AMOUNT, 2 * DEFAULT_AMOUNT + MINIMUM_AMOUNT].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidityUnbalanced(
            address(pool),
            [DEFAULT_AMOUNT, DEFAULT_AMOUNT].toMemoryArray(),
            BPT_AMOUNT_ROUND_DOWN,
            false,
            bytes("")
        );
    }

    // After remove

    function testOnAfterRemoveLiquidityFlag() public {
        pool.setFailOnAfterRemoveLiquidityCallback(true);

        vm.prank(alice);
        router.removeLiquidityProportional(
            address(pool),
            BPT_AMOUNT,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }

    function testOnAfterRemoveLiquidityCallback() public {
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        vm.prank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IPoolCallbacks.onAfterRemoveLiquidity.selector,
                alice,
                BPT_AMOUNT,
                [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
                [MINIMUM_AMOUNT_ROUND_UP, MINIMUM_AMOUNT_ROUND_UP].toMemoryArray(),
                bytes("")
            )
        );

        router.removeLiquidityProportional(
            address(pool),
            BPT_AMOUNT,
            [DEFAULT_AMOUNT_ROUND_DOWN, DEFAULT_AMOUNT_ROUND_DOWN].toMemoryArray(),
            false,
            bytes("")
        );
    }
}
