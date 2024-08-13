// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";

contract BatchRouterERC4626PoolTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;

    uint256 constant MIN_AMOUNT = 1e12;

    ERC4626TestToken internal waInvalid;

    function setUp() public virtual override {
        BaseERC4626BufferTest.setUp();

        // Invalid wrapper, with a zero underlying asset.
        waInvalid = new ERC4626TestToken(IERC20(address(0)), "Invalid Wrapped", "waInvalid", 18);
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
        assertEq(beforeUSDCBalance, afterUSDCBalance, "USDC balance should be the same");

        uint256 afterDAIBalance = dai.balanceOf(sender);
        assertEq(beforeDAIBalance, afterDAIBalance, "DAI balance should be the same");

        (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault.getBufferBalance(
            waUSDC
        );
        assertEq(
            beforeWaUSDCBufferBalanceWrapped,
            afterWaUSDCBufferBalanceWrapped,
            "waUSDC wrapped buffer balance should be the same"
        );
        assertEq(
            beforeWaUSDCBufferBalanceUnderlying,
            afterWaUSDCBufferBalanceUnderlying,
            "waUSDC underlying buffer balance should be the same"
        );

        (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );
        assertEq(
            beforeWaDAIBufferBalanceWrapped,
            afterWaDAIBufferBalanceWrapped,
            "waDAI wrapped buffer balance should be the same"
        );
        assertEq(
            beforeWaDAIBufferBalanceUnderlying,
            afterWaDAIBufferBalanceUnderlying,
            "waDAI underlying buffer balance should be the same"
        );
    }

    function testAddLiquidityUnbalancedToERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        IERC20[] memory erc4626PoolTokens = vault.getPoolTokens(erc4626Pool);
        uint256[] memory exactWrappedAmountsIn = [
            IERC4626(address(erc4626PoolTokens[0])).convertToShares(exactUnderlyingAmountsIn[0]),
            IERC4626(address(erc4626PoolTokens[1])).convertToShares(exactUnderlyingAmountsIn[1])
        ].toMemoryArray();

        for (uint256 i = 0; i < erc4626PoolTokens.length; i++) {
            assertEq(
                exactUnderlyingAmountsIn[i],
                exactWrappedAmountsIn[i],
                "exactUnderlyingAmountsIn should be equal to exactWrappedAmountsIn"
            );
        }

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(erc4626Pool, exactUnderlyingAmountsIn, new bytes(0));
        vm.revertTo(snapshot);

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
            assertEq(
                afterUSDCBalance,
                beforeUSDCBalance - exactUnderlyingAmountsIn[waUsdcIdx],
                "Alice: USDC balance should decrease"
            );
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(
                afterDAIBalance,
                beforeDAIBalance - exactUnderlyingAmountsIn[waDaiIdx],
                "Alice: DAI balance should decrease"
            );
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                afterWaUSDCBufferBalanceWrapped,
                beforeWaUSDCBufferBalanceWrapped - exactWrappedAmountsIn[waUsdcIdx],
                "Vault: waUSDC wrapped buffer balance should decrease"
            );
            assertEq(
                beforeWaUSDCBufferBalanceUnderlying,
                afterWaUSDCBufferBalanceUnderlying - exactUnderlyingAmountsIn[waUsdcIdx],
                "Vault: waUSDC underlying buffer balance should increase"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertEq(
                afterWaDAIBufferBalanceWrapped,
                beforeWaDAIBufferBalanceWrapped - exactWrappedAmountsIn[waDaiIdx],
                "Vault: waDAI wrapped buffer balance should decrease"
            );
            assertEq(
                beforeWaDAIBufferBalanceUnderlying,
                afterWaDAIBufferBalanceUnderlying - exactUnderlyingAmountsIn[waDaiIdx],
                "Vault: waDAI underlying buffer balance should increase"
            );
        }
        {
            (, , , uint256[] memory balances) = vault.getPoolTokenInfo(address(erc4626Pool));
            assertEq(
                balances[waDaiIdx],
                erc4626PoolInitialAmount + exactWrappedAmountsIn[waDaiIdx],
                "ERC4626 Pool: waDAI balance should increase"
            );
            assertEq(
                balances[waUsdcIdx],
                erc4626PoolInitialAmount + exactWrappedAmountsIn[waUsdcIdx],
                "ERC4626 Pool: waUSDC balance should increase"
            );
        }

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(address(erc4626Pool)).balanceOf(alice), bptOut, "Alice: BPT balance should increase");
    }

    function testAddLiquidityUnbalancedToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityUnbalancedToERC4626Pool(erc4626Pool, exactUnderlyingAmountsIn, new bytes(0));
    }

    function testAddLiquidityProportionalToERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        IERC20[] memory erc4626PoolTokens = vault.getPoolTokens(erc4626Pool);
        for (uint256 i = 0; i < erc4626PoolTokens.length; i++) {
            assertEq(
                maxAmountsIn[i],
                IERC4626(address(erc4626PoolTokens[i])).convertToShares(maxAmountsIn[i]),
                "maxAmountIn should be equal to shares"
            );
        }

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsIn = router.queryAddLiquidityProportional(
            erc4626Pool,
            exactBptAmountOut,
            new bytes(0)
        );
        vm.revertTo(snapshot);

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

        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertEq(amountsIn[i], expectedAmountsIn[i], "AmountIn should match expected");
        }

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(afterUSDCBalance, beforeUSDCBalance - amountsIn[waUsdcIdx], "Alice: USDC balance should decrease");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(afterDAIBalance, beforeDAIBalance - amountsIn[waDaiIdx], "Alice: DAI balance should decrease");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                afterWaUSDCBufferBalanceWrapped,
                beforeWaUSDCBufferBalanceWrapped - amountsIn[waUsdcIdx],
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
        {
            (, , , uint256[] memory balances) = vault.getPoolTokenInfo(address(erc4626Pool));
            assertEq(
                balances[waDaiIdx],
                erc4626PoolInitialAmount + amountsIn[waDaiIdx],
                "ERC4626 Pool: waDAI balance should increase"
            );
            assertEq(
                balances[waUsdcIdx],
                erc4626PoolInitialAmount + amountsIn[waUsdcIdx],
                "ERC4626 Pool: waUSDC balance should increase"
            );
        }

        assertEq(
            IERC20(address(erc4626Pool)).balanceOf(alice),
            exactBptAmountOut,
            "Alice: BPT balance should increase"
        );
    }

    function testAddLiquidityProportionalToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityProportionalToERC4626Pool(erc4626Pool, operationAmount, new bytes(0));
    }

    function testRemoveLiquidityProportionalFromERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsOut = router.queryRemoveLiquidityProportional(
            erc4626Pool,
            exactBptAmountIn,
            new bytes(0)
        );
        vm.revertTo(snapshot);

        uint256[] memory minAmountsOut = expectedAmountsOut;
        {
            IERC20[] memory erc4626PoolTokens = vault.getPoolTokens(erc4626Pool);
            for (uint256 i = 0; i < erc4626PoolTokens.length; i++) {
                assertEq(
                    minAmountsOut[i],
                    IERC4626(address(erc4626PoolTokens[i])).convertToAssets(minAmountsOut[i]),
                    "minAmountsOut should be equal to assets"
                );
            }
        }

        uint256 beforeBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        uint256 beforeUSDCBalance = usdc.balanceOf(bob);
        uint256 beforeDAIBalance = dai.balanceOf(bob);
        (uint256 beforeWaUSDCBufferBalanceUnderlying, uint256 beforeWaUSDCBufferBalanceWrapped) = vault
            .getBufferBalance(waUSDC);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(bob);
        uint256[] memory amountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            erc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            new bytes(0)
        );

        for (uint256 i = 0; i < amountsOut.length; i++) {
            assertEq(amountsOut[i], expectedAmountsOut[i], "AmountOut should match expected");
        }

        {
            uint256 afterUSDCBalance = usdc.balanceOf(bob);
            assertEq(beforeUSDCBalance, afterUSDCBalance - amountsOut[waUsdcIdx], "Bob: USDC balance should increase");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(bob);
            assertEq(beforeDAIBalance, afterDAIBalance - amountsOut[waDaiIdx], "Bob: DAI balance should increase");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                beforeWaUSDCBufferBalanceWrapped,
                afterWaUSDCBufferBalanceWrapped - amountsOut[waUsdcIdx],
                "Vault: waUSDC wrapped buffer balance should increase"
            );
            assertEq(
                afterWaUSDCBufferBalanceUnderlying,
                beforeWaUSDCBufferBalanceUnderlying - amountsOut[waUsdcIdx],
                "Vault: waUSDC underlying buffer balance should decrease"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertEq(
                beforeWaDAIBufferBalanceWrapped,
                afterWaDAIBufferBalanceWrapped - amountsOut[waDaiIdx],
                "Vault: waDAI wrapped buffer balance should increase"
            );
            assertEq(
                afterWaDAIBufferBalanceUnderlying,
                beforeWaDAIBufferBalanceUnderlying - amountsOut[waDaiIdx],
                "Vault: waDAI underlying buffer balance should decrease"
            );
        }
        {
            (, , , uint256[] memory balances) = vault.getPoolTokenInfo(address(erc4626Pool));
            assertEq(
                balances[waDaiIdx],
                erc4626PoolInitialAmount - amountsOut[waDaiIdx],
                "ERC4626 Pool: waDAI balance should decrease"
            );
            assertEq(
                balances[waUsdcIdx],
                erc4626PoolInitialAmount - amountsOut[waUsdcIdx],
                "ERC4626 Pool: waUSDC balance should decrease"
            );
        }

        uint256 afterBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: BPT balance should decrease");
    }

    function testRemoveLiquidityProportionalFromERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(bob) {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        vm.prank(bob, address(0));
        batchRouter.queryRemoveLiquidityProportionalFromERC4626Pool(erc4626Pool, exactBptAmountIn, new bytes(0));
    }

    function testInvalidUnderlyingToken() public {
        vm.expectRevert(IVaultErrors.InvalidUnderlyingTokenAsset.selector);
        vm.prank(lp);
        router.addLiquidityToBuffer(waInvalid, bufferInitialAmount, bufferInitialAmount);
    }
}
