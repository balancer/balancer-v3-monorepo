// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterBoostedTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 constant DELTA = 1e10;

    uint256 internal bufferInitialAmount = 1e5 * 1e18;
    uint256 internal boostedPoolInitialAmount = 10e6 * 1e18;
    uint256 internal boostedPoolInitialBPTAmount = boostedPoolInitialAmount * 2;
    uint256 internal operationAmount = bufferInitialAmount / 2;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;
    address internal boostedPool;

    uint256 internal waDaiIdx;
    uint256 internal waUsdcIdx;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        (waDaiIdx, waUsdcIdx) = getSortedIndexes(address(waDAI), address(waUSDC));

        initializeBuffers();
        initializeBoostedPool();
    }

    function initializeBuffers() private {
        // Create and fund buffer pools
        vm.startPrank(lp);
        dai.mint(lp, 2 * bufferInitialAmount);
        dai.approve(address(waDAI), 2 * bufferInitialAmount);
        waDAI.deposit(2 * bufferInitialAmount, lp);

        usdc.mint(lp, 2 * bufferInitialAmount);
        usdc.approve(address(waUSDC), 2 * bufferInitialAmount);
        waUSDC.deposit(2 * bufferInitialAmount, lp);
        vm.stopPrank();

        vm.startPrank(lp);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);

        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);

        router.addLiquidityToBuffer(waDAI, bufferInitialAmount, bufferInitialAmount, lp);
        router.addLiquidityToBuffer(waUSDC, bufferInitialAmount, bufferInitialAmount, lp);
        vm.stopPrank();
    }

    function initializeBoostedPool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(address(waUSDC));

        PoolMock newPool = new PoolMock(IVault(address(vault)), "Boosted Pool", "BOOSTYBOI");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

        vm.label(address(newPool), "boosted pool");
        boostedPool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);

        dai.mint(bob, boostedPoolInitialAmount);
        dai.approve(address(waDAI), boostedPoolInitialAmount);
        waDAI.deposit(boostedPoolInitialAmount, bob);

        usdc.mint(bob, boostedPoolInitialAmount);
        usdc.approve(address(waUSDC), boostedPoolInitialAmount);
        waUSDC.deposit(boostedPoolInitialAmount, bob);

        _initPool(
            boostedPool,
            [boostedPoolInitialAmount, boostedPoolInitialAmount].toMemoryArray(),
            boostedPoolInitialBPTAmount - MIN_BPT
        );

        IERC20(address(boostedPool)).approve(address(permit2), MAX_UINT256);
        permit2.approve(address(boostedPool), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(boostedPool), address(batchRouter), type(uint160).max, type(uint48).max);

        IERC20(address(boostedPool)).approve(address(router), type(uint256).max);
        IERC20(address(boostedPool)).approve(address(batchRouter), type(uint256).max);

        vm.stopPrank();
    }

    modifier checkBuffersWhenStaticCall(address sender) {
        uint256 beforeUSDCBalance = usdc.balanceOf(sender);
        uint256 beforeDAIBalance = dai.balanceOf(sender);
        (uint256 beforeWaUSDCBufferBalanceUnderling, uint256 beforeWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        (uint256 beforeWaDAIBufferBalanceUnderling, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        _;

        uint256 afterUSDCBalance = usdc.balanceOf(sender);
        assertEq(beforeUSDCBalance - afterUSDCBalance, 0, "USDC balance should be the same");

        uint256 afterDAIBalance = dai.balanceOf(sender);
        assertEq(beforeDAIBalance - afterDAIBalance, 0, "DAI balance should be the same");

        (uint256 afterWaUSDCBufferBalanceUnderling, uint256 afterWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        assertEq(
            beforeWaUSDCBufferBalanceWrapped - afterWaUSDCBufferBalanceWrapped,
            0,
            "waUSDC wrapped buffer balance should be the same"
        );
        assertEq(
            afterWaUSDCBufferBalanceUnderling - beforeWaUSDCBufferBalanceUnderling,
            0,
            "waUSDC underlying buffer balance should be the same"
        );

        (uint256 afterWaDAIBufferBalanceUnderling, uint256 afterWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );
        assertEq(
            beforeWaDAIBufferBalanceWrapped - afterWaDAIBufferBalanceWrapped,
            0,
            "waDAI wrapped buffer balance should be the same"
        );
        assertEq(
            afterWaDAIBufferBalanceUnderling - beforeWaDAIBufferBalanceUnderling,
            0,
            "waDAI underlying buffer balance should be the same"
        );
    }

    function testAddLiquidityUnbalancedToBoostedPool() public {
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(boostedPool, exactUnderlyingAmountsIn, new bytes(0));

        uint256 beforeUSDCBalance = usdc.balanceOf(alice);
        uint256 beforeDAIBalance = dai.balanceOf(alice);
        (uint256 beforeWaUSDCBufferBalanceUnderling, uint256 beforeWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        (uint256 beforeWaDAIBufferBalanceUnderling, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(alice);
        uint256 bptOut = batchRouter.addLiquidityUnbalancedToBoostedPool(
            boostedPool,
            exactUnderlyingAmountsIn,
            1,
            false,
            new bytes(0)
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(beforeUSDCBalance - afterUSDCBalance, operationAmount, "USDC balance should decrease");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(beforeDAIBalance - afterDAIBalance, operationAmount, "DAI balance should decrease");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderling, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                beforeWaUSDCBufferBalanceWrapped - afterWaUSDCBufferBalanceWrapped,
                operationAmount,
                "waUSDC wrapped buffer balance should decrease"
            );
            assertEq(
                afterWaUSDCBufferBalanceUnderling - beforeWaUSDCBufferBalanceUnderling,
                operationAmount,
                "waUSDC underlying buffer balance should increase"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderling, uint256 afterWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
                waDAI
            );
            assertEq(
                beforeWaDAIBufferBalanceWrapped - afterWaDAIBufferBalanceWrapped,
                operationAmount,
                "waDAI wrapped buffer balance should decrease"
            );
            assertEq(
                afterWaDAIBufferBalanceUnderling - beforeWaDAIBufferBalanceUnderling,
                operationAmount,
                "waDAI underlying buffer balance should increase"
            );
        }

        assertApproxEqAbs(bptOut, expectBPTOut, DELTA, "BPT operationAmount should match expected");
        assertEq(IERC20(address(boostedPool)).balanceOf(alice), bptOut, "BPT balance should increase");
    }

    function testAddLiquidityUnbalancedToBoostedPoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityUnbalancedToBoostedPool(boostedPool, exactUnderlyingAmountsIn, new bytes(0));
    }

    function testAddLiquidityProportionalToBoostedPool() public {
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        _prankStaticCall();
        uint256[] memory expectedAmountsIn = router.queryAddLiquidityProportional(
            boostedPool,
            maxAmountsIn,
            exactBptAmountOut,
            new bytes(0)
        );

        uint256 beforeUSDCBalance = usdc.balanceOf(alice);
        uint256 beforeDAIBalance = dai.balanceOf(alice);
        (uint256 beforeWaUSDCBufferBalanceUnderling, uint256 beforeWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        (uint256 beforeWaDAIBufferBalanceUnderling, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(alice);
        uint256[] memory amountsIn = batchRouter.addLiquidityProportionalToBoostedPool(
            boostedPool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            new bytes(0)
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(beforeUSDCBalance - afterUSDCBalance, amountsIn[0], "USDC balance should decrease");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(beforeDAIBalance - afterDAIBalance, amountsIn[1], "DAI balance should decrease");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderling, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                beforeWaUSDCBufferBalanceWrapped - afterWaUSDCBufferBalanceWrapped,
                amountsIn[0],
                "waUSDC wrapped buffer balance should decrease"
            );
            assertEq(
                afterWaUSDCBufferBalanceUnderling - beforeWaUSDCBufferBalanceUnderling,
                amountsIn[1],
                "waUSDC underlying buffer balance should increase"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderling, uint256 afterWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
                waDAI
            );
            assertEq(
                beforeWaDAIBufferBalanceWrapped - afterWaDAIBufferBalanceWrapped,
                amountsIn[0],
                "waDAI wrapped buffer balance should decrease"
            );
            assertEq(
                afterWaDAIBufferBalanceUnderling - beforeWaDAIBufferBalanceUnderling,
                amountsIn[1],
                "waDAI underlying buffer balance should increase"
            );
        }

        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertApproxEqAbs(amountsIn[i], expectedAmountsIn[i], DELTA, "AmountIn should match expected");
        }

        assertEq(IERC20(address(boostedPool)).balanceOf(alice), exactBptAmountOut, "BPT balance should increase");
    }

    function testAddLiquidityProportionalToBoostedPoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityProportionalToBoostedPool(
            boostedPool,
            maxAmountsIn,
            operationAmount,
            new bytes(0)
        );
    }

    function testRemoveLiquidityProportionalToBoostedPool() public {
        uint256[] memory minAmountsOut = [uint256(0), 0].toMemoryArray();
        uint256 exactBptAmountIn = operationAmount;

        _prankStaticCall();
        uint256[] memory expectedAmountsOut = router.queryRemoveLiquidityProportional(
            boostedPool,
            exactBptAmountIn,
            new bytes(0)
        );

        uint256 beforeBPTBalance = IERC20(address(boostedPool)).balanceOf(bob);
        uint256 beforeUSDCBalance = usdc.balanceOf(bob);
        uint256 beforeDAIBalance = dai.balanceOf(bob);
        (uint256 beforeWaUSDCBufferBalanceUnderling, uint256 beforeWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        (uint256 beforeWaDAIBufferBalanceUnderling, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(bob);
        uint256[] memory amountsOut = batchRouter.removeLiquidityProportionalToBoostedPool(
            boostedPool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            new bytes(0)
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(bob);
            assertEq(afterUSDCBalance - beforeUSDCBalance, amountsOut[0], "USDC balance should increase");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(bob);
            assertEq(afterDAIBalance - beforeDAIBalance, amountsOut[1], "DAI balance should increase");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderling, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                afterWaUSDCBufferBalanceWrapped - beforeWaUSDCBufferBalanceWrapped,
                amountsOut[0],
                "waUSDC wrapped buffer balance should increase"
            );
            assertEq(
                beforeWaUSDCBufferBalanceUnderling - afterWaUSDCBufferBalanceUnderling,
                amountsOut[1],
                "waUSDC underlying buffer balance should decrease"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderling, uint256 afterWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
                waDAI
            );
            assertEq(
                afterWaDAIBufferBalanceWrapped - beforeWaDAIBufferBalanceWrapped,
                amountsOut[0],
                "waDAI wrapped buffer balance should increase"
            );
            assertEq(
                beforeWaDAIBufferBalanceUnderling - afterWaDAIBufferBalanceUnderling,
                amountsOut[1],
                "waDAI underlying buffer balance should decrease"
            );
        }

        for (uint256 i = 0; i < amountsOut.length; i++) {
            assertApproxEqAbs(amountsOut[i], expectedAmountsOut[i], DELTA, "AmountOut should match expected");
        }

        uint256 afterBPTBalance = IERC20(address(boostedPool)).balanceOf(bob);
        assertEq(beforeBPTBalance - afterBPTBalance, exactBptAmountIn);
    }

    function testRemoveLiquidityProportionalToBoostedPoolWhenStaticCall() public checkBuffersWhenStaticCall(bob) {
        uint256 exactBptAmountIn = operationAmount;

        vm.prank(bob, address(0));
        batchRouter.queryRemoveLiquidityProportionalToBoostedPool(boostedPool, exactBptAmountIn, new bytes(0));
    }
}
