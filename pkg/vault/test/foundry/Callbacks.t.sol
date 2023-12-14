// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { ERC20PoolMock } from "../../contracts/test/ERC20PoolMock.sol";
import { Vault } from "../../contracts/Vault.sol";
import { Router } from "../../contracts/Router.sol";
import { PoolConfigLib } from "../../contracts/lib/PoolConfigLib.sol";
import { RouterAdaptor } from "../../contracts/test/RouterAdaptor.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";

contract VaultSwapTest is Test {
    using ArrayHelpers for *;
    using RouterAdaptor for IRouter;

    VaultMock vault;
    IRouter router;
    BasicAuthorizerMock authorizer;
    ERC20PoolMock pool;
    ERC20TestToken USDC;
    ERC20TestToken DAI;
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    uint256 constant USDC_AMOUNT_IN = 1e3 * 1e6;
    uint256 constant DAI_AMOUNT_IN = 1e3 * 1e18;
    uint256 constant USDC_SCALING = 1e12; // 18 - 6
    uint256 initialBptSupply;
    uint256[] maxAmountsIn = [DAI_AMOUNT_IN, USDC_AMOUNT_IN];
    uint256[] minAmountsOut = [DAI_AMOUNT_IN / 2, USDC_AMOUNT_IN / 2];

    function setUp() public {
        authorizer = new BasicAuthorizerMock();
        vault = new VaultMock(authorizer, 30 days, 90 days);
        router = new Router(IVault(vault), new WETHTestToken());
        USDC = new ERC20TestToken("USDC", "USDC", 6);
        DAI = new ERC20TestToken("DAI", "DAI", 18);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);

        pool = new ERC20PoolMock(
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

        USDC.mint(bob, USDC_AMOUNT_IN);
        DAI.mint(bob, DAI_AMOUNT_IN);

        USDC.mint(alice, USDC_AMOUNT_IN);
        DAI.mint(alice, DAI_AMOUNT_IN);

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
            [DAI_AMOUNT_IN, USDC_AMOUNT_IN].toMemoryArray(),
            0,
            false,
            bytes("")
        );
        initialBptSupply = IERC20(pool).totalSupply();

        vm.stopPrank();

        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(address(USDC), "USDC");
        vm.label(address(DAI), "DAI");
    }

    function testOnBeforeSwapCallback() public {
        // Calls `onSwap` in the pool.
        vm.prank(bob);
        // Balances are scaled to 18 decimals; DAI already has 18.
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onBeforeSwap.selector,
                IBasePool.SwapParams({
                    kind: IVault.SwapKind.GIVEN_IN,
                    tokenIn: IERC20(USDC),
                    tokenOut: IERC20(DAI),
                    amountGivenScaled18: USDC_AMOUNT_IN * USDC_SCALING,
                    balancesScaled18: [DAI_AMOUNT_IN, USDC_AMOUNT_IN * USDC_SCALING].toMemoryArray(),
                    indexIn: 1,
                    indexOut: 0,
                    sender: address(router),
                    userData: bytes("")
                })
            )
        );
        router.swapExactIn(
            address(pool),
            USDC,
            DAI,
            USDC_AMOUNT_IN,
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
        router.swapExactIn(
            address(pool),
            USDC,
            DAI,
            USDC_AMOUNT_IN,
            DAI_AMOUNT_IN,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    function testOnAfterSwapCallback() public {
        // Calls `onSwap` in the pool.
        vm.prank(bob);
        // Balances are scaled to 18 decimals; DAI already has 18.
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onAfterSwap.selector,
                IBasePool.AfterSwapParams({
                    kind: IVault.SwapKind.GIVEN_IN,
                    tokenIn: IERC20(USDC),
                    tokenOut: IERC20(DAI),
                    amountInScaled18: USDC_AMOUNT_IN * USDC_SCALING,
                    amountOutScaled18: DAI_AMOUNT_IN,
                    tokenInBalanceScaled18: DAI_AMOUNT_IN * 2,
                    tokenOutBalanceScaled18: 0,
                    sender: address(router),
                    userData: bytes("")
                }),
                DAI_AMOUNT_IN
            )
        );
        router.swapExactIn(
            address(pool),
            USDC,
            DAI,
            USDC_AMOUNT_IN,
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
        router.swapExactIn(
            address(pool),
            USDC,
            DAI,
            USDC_AMOUNT_IN,
            DAI_AMOUNT_IN,
            type(uint256).max,
            false,
            bytes("")
        );
    }

    // Before add

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeAddLiquidityFlag(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        pool.setFailOnBeforeAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidity(
            address(pool),
            RouterAdaptor.adaptMaxAmountsIn(kind, maxAmountsIn),
            initialBptSupply,
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeAddLiquidityCallback(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeAddLiquidity = true;
        vault.setConfig(address(pool), config);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory maxInputs = RouterAdaptor.adaptMaxAmountsIn(kind, maxAmountsIn);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onBeforeAddLiquidity.selector,
                bob,
                [maxInputs[0], maxInputs[1] * USDC_SCALING].toMemoryArray(),
                initialBptSupply,
                [poolBalances[0], poolBalances[1] * USDC_SCALING].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidity(address(pool), maxInputs, initialBptSupply, kind, bytes(""));
    }

    // Before remove

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeRemoveLiquidityFlag(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        pool.setFailOnBeforeRemoveLiquidityCallback(true);

        uint256 bptBalance = pool.balanceOf(alice);
        // Alice has LP tokens from initialization
        vm.prank(alice);
        // Doesn't fail, does not call callbacks
        router.removeLiquidity(
            address(pool),
            bptBalance,
            RouterAdaptor.adaptMinAmountsOut(kind, minAmountsOut),
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnBeforeRemoveLiquidityCallback(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallBeforeRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory minOutputs = RouterAdaptor.adaptMinAmountsOut(kind, minAmountsOut);

        // Alice has LP tokens from initialization
        uint256 bptBalance = pool.balanceOf(alice);
        vm.prank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onBeforeRemoveLiquidity.selector,
                alice,
                bptBalance,
                [minOutputs[0], minOutputs[1] * USDC_SCALING].toMemoryArray(),
                [poolBalances[0], poolBalances[1] * USDC_SCALING].toMemoryArray(),
                bytes("")
            )
        );
        router.removeLiquidity(
            address(pool),
            bptBalance,
            RouterAdaptor.adaptMinAmountsOut(kind, minAmountsOut),
            kind,
            bytes("")
        );
    }

    // After add

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterAddLiquidityFlag(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        pool.setFailOnAfterAddLiquidityCallback(true);

        vm.prank(bob);
        // Doesn't fail, does not call callbacks
        router.addLiquidity(
            address(pool),
            RouterAdaptor.adaptMaxAmountsIn(kind, maxAmountsIn),
            initialBptSupply,
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterAddLiquidityCallback(uint8 kindUint) public {
        IVault.AddLiquidityKind kind = IVault.AddLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.AddLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterAddLiquidity = true;
        vault.setConfig(address(pool), config);

        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        uint256[] memory amountsIn;
        uint256 bptAmountOut;

        // Dry run to get actual amounts in and bpt out from the operation
        uint256 snapshot = vm.snapshot();
        vm.prank(bob);
        (amountsIn, bptAmountOut) = router.addLiquidity(
            address(pool),
            RouterAdaptor.adaptMaxAmountsIn(kind, maxAmountsIn),
            initialBptSupply,
            kind,
            bytes("")
        );
        vm.revertTo(snapshot);

        vm.prank(bob);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onAfterAddLiquidity.selector,
                bob,
                [amountsIn[0], amountsIn[1] * USDC_SCALING].toMemoryArray(),
                bptAmountOut,
                [poolBalances[0] + amountsIn[0], (poolBalances[1] + amountsIn[1]) * USDC_SCALING].toMemoryArray(),
                bytes("")
            )
        );
        router.addLiquidity(
            address(pool),
            RouterAdaptor.adaptMaxAmountsIn(kind, maxAmountsIn),
            initialBptSupply,
            kind,
            bytes("")
        );
    }

    // After remove

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterRemoveLiquidityFlag(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        pool.setFailOnAfterRemoveLiquidityCallback(true);

        uint256 bptBalance = pool.balanceOf(alice);
        // Alice has LP tokens from initialization
        vm.prank(alice);
        // Doesn't fail, does not call callbacks
        router.removeLiquidity(
            address(pool),
            bptBalance,
            RouterAdaptor.adaptMinAmountsOut(kind, minAmountsOut),
            kind,
            bytes("")
        );
    }

    /// forge-config: default.fuzz.runs = 32
    function testOnAfterRemoveLiquidityCallback(uint8 kindUint) public {
        IVault.RemoveLiquidityKind kind = IVault.RemoveLiquidityKind(
            bound(kindUint, 0, uint256(type(IVault.RemoveLiquidityKind).max))
        );
        PoolConfig memory config = vault.getPoolConfig(address(pool));
        config.callbacks.shouldCallAfterRemoveLiquidity = true;
        vault.setConfig(address(pool), config);

        uint256 bptBalance = pool.balanceOf(alice);
        // Cut the tail so that there is no precision loss when calculating upscaled amounts out in proportional mode
        bptBalance -= bptBalance % USDC_SCALING;
        (, uint256[] memory poolBalances, , ) = vault.getPoolTokenInfo(address(pool));
        uint256 bptAmountIn;
        uint256[] memory amountsOut;

        // Dry run to get actual amounts out and bpt in from the operation
        uint256 snapshot = vm.snapshot();
        // Alice has LP tokens from initialization
        vm.prank(alice);
        (bptAmountIn, amountsOut) = router.removeLiquidity(
            address(pool),
            bptBalance,
            RouterAdaptor.adaptMinAmountsOut(kind, minAmountsOut),
            kind,
            bytes("")
        );
        vm.revertTo(snapshot);

        vm.prank(alice);
        vm.expectCall(
            address(pool),
            abi.encodeWithSelector(
                IBasePool.onAfterRemoveLiquidity.selector,
                alice,
                bptAmountIn,
                [amountsOut[0], amountsOut[1] * USDC_SCALING].toMemoryArray(),
                [poolBalances[0] - amountsOut[0], (poolBalances[1] - amountsOut[1]) * USDC_SCALING].toMemoryArray(),
                bytes("")
            )
        );
        router.removeLiquidity(
            address(pool),
            bptBalance,
            RouterAdaptor.adaptMinAmountsOut(kind, minAmountsOut),
            kind,
            bytes("")
        );
    }
}
