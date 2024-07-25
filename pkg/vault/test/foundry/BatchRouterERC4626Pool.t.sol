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

contract BatchRouterERC4626PoolTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 constant DELTA = 1e10;

    uint256 internal bufferInitialAmount = 1e5 * 1e18;
    uint256 internal erc4626PoolInitialAmount = 10e6 * 1e18;
    uint256 internal erc4626PoolInitialBPTAmount = erc4626PoolInitialAmount * 2;
    uint256 internal operationAmount = bufferInitialAmount / 2;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;
    address internal erc4626Pool;

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
        initializeERC4626Pool();
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

    function initializeERC4626Pool() private {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[waDaiIdx].token = IERC20(waDAI);
        tokenConfig[waUsdcIdx].token = IERC20(waUSDC);
        tokenConfig[0].tokenType = TokenType.WITH_RATE;
        tokenConfig[1].tokenType = TokenType.WITH_RATE;
        tokenConfig[waDaiIdx].rateProvider = IRateProvider(address(waDAI));
        tokenConfig[waUsdcIdx].rateProvider = IRateProvider(address(waUSDC));

        PoolMock newPool = new PoolMock(IVault(address(vault)), "ERC4626 Pool", "ERC4626P");

        factoryMock.registerTestPool(address(newPool), tokenConfig, poolHooksContract);

        vm.label(address(newPool), "erc4626 pool");
        erc4626Pool = address(newPool);

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);

        dai.mint(bob, erc4626PoolInitialAmount);
        dai.approve(address(waDAI), erc4626PoolInitialAmount);
        waDAI.deposit(erc4626PoolInitialAmount, bob);

        usdc.mint(bob, erc4626PoolInitialAmount);
        usdc.approve(address(waUSDC), erc4626PoolInitialAmount);
        waUSDC.deposit(erc4626PoolInitialAmount, bob);

        _initPool(
            erc4626Pool,
            [erc4626PoolInitialAmount, erc4626PoolInitialAmount].toMemoryArray(),
            erc4626PoolInitialBPTAmount - MIN_BPT
        );

        IERC20(address(erc4626Pool)).approve(address(permit2), MAX_UINT256);
        permit2.approve(address(erc4626Pool), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(erc4626Pool), address(batchRouter), type(uint160).max, type(uint48).max);

        IERC20(address(erc4626Pool)).approve(address(router), type(uint256).max);
        IERC20(address(erc4626Pool)).approve(address(batchRouter), type(uint256).max);

        vm.stopPrank();
    }

    modifier checkBuffersWhenStaticCall(address sender) {
        uint256 beforeUSDCBalance = usdc.balanceOf(sender);
        uint256 beforeDAIBalance = dai.balanceOf(sender);
        (uint256 beforeWaUSDCBufferBalanceUnderlying, uint256 beforeWaUSDCBufferBalanceWrapped) = vault
            .getBufferBalance(waUSDC);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        _;

        uint256 afterUSDCBalance = usdc.balanceOf(sender);
        assertEq(beforeUSDCBalance - afterUSDCBalance, 0, "USDC balance should be the same");

        uint256 afterDAIBalance = dai.balanceOf(sender);
        assertEq(beforeDAIBalance - afterDAIBalance, 0, "DAI balance should be the same");

        (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        assertEq(
            beforeWaUSDCBufferBalanceWrapped - afterWaUSDCBufferBalanceWrapped,
            0,
            "waUSDC wrapped buffer balance should be the same"
        );
        assertEq(
            afterWaUSDCBufferBalanceUnderlying - beforeWaUSDCBufferBalanceUnderlying,
            0,
            "waUSDC underlying buffer balance should be the same"
        );

        (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );
        assertEq(
            beforeWaDAIBufferBalanceWrapped - afterWaDAIBufferBalanceWrapped,
            0,
            "waDAI wrapped buffer balance should be the same"
        );
        assertEq(
            afterWaDAIBufferBalanceUnderlying - beforeWaDAIBufferBalanceUnderlying,
            0,
            "waDAI underlying buffer balance should be the same"
        );
    }

    function testAddLiquidityUnbalancedToERC4626Pool() public {
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(erc4626Pool, exactUnderlyingAmountsIn, new bytes(0));

        uint256 beforeUSDCBalance = usdc.balanceOf(alice);
        uint256 beforeDAIBalance = dai.balanceOf(alice);
        (uint256 beforeWaUSDCBufferBalanceUnderlying, uint256 beforeWaUSDCBufferBalanceWrapped) = vault
            .getBufferBalance(waUSDC);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(alice);
        uint256 bptOut = batchRouter.addLiquidityUnbalancedToERC4626Pool(
            erc4626Pool,
            exactUnderlyingAmountsIn,
            1,
            false,
            new bytes(0)
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(afterUSDCBalance, beforeUSDCBalance - operationAmount, "Alice: USDC balance should decrease");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(afterDAIBalance, beforeDAIBalance - operationAmount, "Alice: DAI balance should decrease");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                afterWaUSDCBufferBalanceWrapped,
                beforeWaUSDCBufferBalanceWrapped - operationAmount,
                "Vault: waUSDC wrapped buffer balance should decrease"
            );
            assertEq(
                beforeWaUSDCBufferBalanceUnderlying,
                afterWaUSDCBufferBalanceUnderlying - operationAmount,
                "Vault: waUSDC underlying buffer balance should increase"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertEq(
                afterWaDAIBufferBalanceWrapped,
                beforeWaDAIBufferBalanceWrapped - operationAmount,
                "Vault: waDAI wrapped buffer balance should decrease"
            );
            assertEq(
                beforeWaDAIBufferBalanceUnderlying,
                afterWaDAIBufferBalanceUnderlying - operationAmount,
                "Vault: waDAI underlying buffer balance should increase"
            );
        }

        assertApproxEqAbs(bptOut, expectBPTOut, DELTA, "BPT operationAmount should match expected");
        assertEq(IERC20(address(erc4626Pool)).balanceOf(alice), bptOut, "Alice: BPT balance should increase");
    }

    function testAddLiquidityUnbalancedToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityUnbalancedToERC4626Pool(erc4626Pool, exactUnderlyingAmountsIn, new bytes(0));
    }

    function testAddLiquidityProportionalToERC4626Pool() public {
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        _prankStaticCall();
        uint256[] memory expectedAmountsIn = router.queryAddLiquidityProportional(
            erc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            new bytes(0)
        );

        uint256 beforeUSDCBalance = usdc.balanceOf(alice);
        uint256 beforeDAIBalance = dai.balanceOf(alice);
        (uint256 beforeWaUSDCBufferBalanceUnderlying, uint256 beforeWaUSDCBufferBalanceWrapped) = vault
            .getBufferBalance(waUSDC);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(alice);
        uint256[] memory amountsIn = batchRouter.addLiquidityProportionalToERC4626Pool(
            erc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            new bytes(0)
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(afterUSDCBalance, beforeUSDCBalance - amountsIn[0], "Alice: USDC balance should decrease");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(afterDAIBalance, beforeDAIBalance - amountsIn[1], "Alice: DAI balance should decrease");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                afterWaUSDCBufferBalanceWrapped,
                beforeWaUSDCBufferBalanceWrapped - amountsIn[0],
                "Vault: waUSDC wrapped buffer balance should decrease"
            );
            assertEq(
                beforeWaUSDCBufferBalanceUnderlying,
                afterWaUSDCBufferBalanceUnderlying - amountsIn[1],
                "Vault: waUSDC underlying buffer balance should increase"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertEq(
                afterWaDAIBufferBalanceWrapped,
                beforeWaDAIBufferBalanceWrapped - amountsIn[0],
                "Vault: waDAI wrapped buffer balance should decrease"
            );
            assertEq(
                beforeWaDAIBufferBalanceUnderlying,
                afterWaDAIBufferBalanceUnderlying - amountsIn[1],
                "Vault: waDAI underlying buffer balance should increase"
            );
        }

        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertApproxEqAbs(amountsIn[i], expectedAmountsIn[i], DELTA, "AmountIn should match expected");
        }

        assertEq(
            IERC20(address(erc4626Pool)).balanceOf(alice),
            exactBptAmountOut,
            "Alice: BPT balance should increase"
        );
    }

    function testAddLiquidityProportionalToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityProportionalToERC4626Pool(
            erc4626Pool,
            maxAmountsIn,
            operationAmount,
            new bytes(0)
        );
    }

    function testRemoveLiquidityProportionalToERC4626Pool() public {
        uint256[] memory minAmountsOut = [uint256(0), 0].toMemoryArray();
        uint256 exactBptAmountIn = operationAmount;

        _prankStaticCall();
        uint256[] memory expectedAmountsOut = router.queryRemoveLiquidityProportional(
            erc4626Pool,
            exactBptAmountIn,
            new bytes(0)
        );

        uint256 beforeBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        uint256 beforeUSDCBalance = usdc.balanceOf(bob);
        uint256 beforeDAIBalance = dai.balanceOf(bob);
        (uint256 beforeWaUSDCBufferBalanceUnderlying, uint256 beforeWaUSDCBufferBalanceWrapped) = vault
            .getBufferBalance(waUSDC);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(bob);
        uint256[] memory amountsOut = batchRouter.removeLiquidityProportionalToERC4626Pool(
            erc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            new bytes(0)
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(bob);
            assertEq(beforeUSDCBalance, afterUSDCBalance - amountsOut[0], "Bob: USDC balance should increase");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(bob);
            assertEq(beforeDAIBalance, afterDAIBalance - amountsOut[1], "Bob: DAI balance should increase");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                beforeWaUSDCBufferBalanceWrapped,
                afterWaUSDCBufferBalanceWrapped - amountsOut[0],
                "Vault: waUSDC wrapped buffer balance should increase"
            );
            assertEq(
                afterWaUSDCBufferBalanceUnderlying,
                beforeWaUSDCBufferBalanceUnderlying - amountsOut[1],
                "Vault: waUSDC underlying buffer balance should decrease"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertEq(
                beforeWaDAIBufferBalanceWrapped,
                afterWaDAIBufferBalanceWrapped - amountsOut[0],
                "Vault: waDAI wrapped buffer balance should increase"
            );
            assertEq(
                afterWaDAIBufferBalanceUnderlying,
                beforeWaDAIBufferBalanceUnderlying - amountsOut[1],
                "Vault: waDAI underlying buffer balance should decrease"
            );
        }

        for (uint256 i = 0; i < amountsOut.length; i++) {
            assertApproxEqAbs(amountsOut[i], expectedAmountsOut[i], DELTA, "AmountOut should match expected");
        }

        uint256 afterBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: BPT balance should decrease");
    }

    function testRemoveLiquidityProportionalToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(bob) {
        uint256 exactBptAmountIn = operationAmount;

        vm.prank(bob, address(0));
        batchRouter.queryRemoveLiquidityProportionalToERC4626Pool(erc4626Pool, exactBptAmountIn, new bytes(0));
    }
}
