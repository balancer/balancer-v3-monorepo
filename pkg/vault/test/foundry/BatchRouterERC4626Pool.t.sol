// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterERC4626PoolTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    uint256 constant MIN_AMOUNT = 1e12;
    uint256 internal constant MAX_ERROR = 2;

    ERC4626TestToken internal waInvalid;

    function setUp() public virtual override {
        BaseERC4626BufferTest.setUp();

        // Invalid wrapper, with a zero underlying asset.
        waInvalid = new ERC4626TestToken(IERC20(address(0)), "Invalid Wrapped", "waInvalid", 18);
    }

    modifier checkBuffersWhenStaticCall(address sender) {
        TestBalances memory balancesBefore = _getTestBalances(sender);

        _;

        TestBalances memory balancesAfter = _getTestBalances(sender);

        assertEq(
            balancesBefore.balances.userTokens[balancesBefore.usdcIdx],
            balancesAfter.balances.userTokens[balancesBefore.usdcIdx],
            "USDC balance should be the same"
        );

        assertEq(
            balancesBefore.balances.userTokens[balancesBefore.daiIdx],
            balancesAfter.balances.userTokens[balancesBefore.daiIdx],
            "DAI balance should be the same"
        );

        assertEq(
            balancesBefore.waUSDCBuffer.wrapped,
            balancesAfter.waUSDCBuffer.wrapped,
            "waUSDC wrapped buffer balance should be the same"
        );
        assertEq(
            balancesBefore.waUSDCBuffer.underlying,
            balancesAfter.waUSDCBuffer.underlying,
            "waUSDC underlying buffer balance should be the same"
        );

        assertEq(
            balancesBefore.waDAIBuffer.wrapped,
            balancesAfter.waDAIBuffer.wrapped,
            "waDAI wrapped buffer balance should be the same"
        );
        assertEq(
            balancesBefore.waDAIBuffer.underlying,
            balancesAfter.waDAIBuffer.underlying,
            "waDAI underlying buffer balance should be the same"
        );
    }

    function testAddLiquidityUnbalancedToERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[waDaiIdx] = (waDAI.convertToShares(exactUnderlyingAmountsIn[waDaiIdx]) -
            vaultConvertFactor);
        exactWrappedAmountsIn[waUsdcIdx] = (waUSDC.convertToShares(exactUnderlyingAmountsIn[waUsdcIdx]) -
            vaultConvertFactor);

        uint256 expectBPTOut;
        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        expectBPTOut = router.queryAddLiquidityUnbalanced(erc4626Pool, exactWrappedAmountsIn, bytes(""));
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256 bptOut = batchRouter.addLiquidityUnbalancedToERC4626Pool(
            erc4626Pool,
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        assertEq(
            balancesAfter.balances.aliceTokens[balancesAfter.usdcIdx],
            balancesBefore.balances.aliceTokens[balancesBefore.usdcIdx] - exactUnderlyingAmountsIn[waUsdcIdx],
            "Alice: wrong USDC balance"
        );
        assertEq(
            balancesAfter.balances.aliceTokens[balancesAfter.daiIdx],
            balancesBefore.balances.aliceTokens[balancesBefore.daiIdx] - exactUnderlyingAmountsIn[waDaiIdx],
            "Alice: wrong DAI balance"
        );

        assertEq(
            balancesAfter.waUSDCBuffer.wrapped,
            balancesBefore.waUSDCBuffer.wrapped - exactWrappedAmountsIn[waUsdcIdx],
            "Vault: wrong waUSDC wrapped buffer balance"
        );
        assertEq(
            balancesAfter.waUSDCBuffer.underlying,
            balancesBefore.waUSDCBuffer.underlying + exactUnderlyingAmountsIn[waUsdcIdx],
            "Vault: wrong waUSDC underlying buffer balance"
        );

        assertEq(
            balancesAfter.waDAIBuffer.wrapped,
            balancesBefore.waDAIBuffer.wrapped - exactWrappedAmountsIn[waDaiIdx],
            "Vault: wrong waDAI wrapped buffer balance"
        );
        assertEq(
            balancesAfter.waDAIBuffer.underlying,
            balancesBefore.waDAIBuffer.underlying + exactUnderlyingAmountsIn[waDaiIdx],
            "Vault: wrong waDAI underlying buffer balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(erc4626Pool));
        assertApproxEqAbs(
            balances[waDaiIdx],
            waDAI.convertToShares(erc4626PoolInitialAmount) + exactWrappedAmountsIn[waDaiIdx],
            MAX_ERROR,
            "ERC4626 Pool: wrong waDAI balance"
        );
        assertApproxEqAbs(
            balances[waUsdcIdx],
            waUSDC.convertToShares(erc4626PoolInitialAmount) + exactWrappedAmountsIn[waUsdcIdx],
            MAX_ERROR,
            "ERC4626 Pool: wrong waUSDC balance"
        );

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(address(erc4626Pool)).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityUnbalancedToERC4626Pool(erc4626Pool, exactUnderlyingAmountsIn, bytes(""));
    }

    function testAddLiquidityProportionalToERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsInWrapped = router.queryAddLiquidityProportional(
            erc4626Pool,
            exactBptAmountOut,
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256[] memory actualAmountsInUnderlying = batchRouter.addLiquidityProportionalToERC4626Pool(
            erc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        assertApproxEqAbs(
            actualAmountsInUnderlying[waDaiIdx],
            waDAI.convertToAssets(expectedAmountsInWrapped[waDaiIdx]) + vaultConvertFactor,
            MAX_ERROR,
            "DAI actualAmountsInUnderlying should match expected"
        );
        assertApproxEqAbs(
            actualAmountsInUnderlying[waUsdcIdx],
            waUSDC.convertToAssets(expectedAmountsInWrapped[waUsdcIdx]) + vaultConvertFactor,
            MAX_ERROR,
            "USDC actualAmountsInUnderlying should match expected"
        );

        assertEq(
            balancesAfter.balances.aliceTokens[balancesAfter.usdcIdx],
            balancesBefore.balances.aliceTokens[balancesBefore.usdcIdx] - actualAmountsInUnderlying[waUsdcIdx],
            "Alice: wrong USDC balance"
        );
        assertEq(
            balancesAfter.balances.aliceTokens[balancesAfter.daiIdx],
            balancesBefore.balances.aliceTokens[balancesBefore.daiIdx] - actualAmountsInUnderlying[waDaiIdx],
            "Alice: wrong DAI balance"
        );

        assertApproxEqAbs(
            balancesAfter.waUSDCBuffer.wrapped,
            balancesBefore.waUSDCBuffer.wrapped - expectedAmountsInWrapped[waUsdcIdx],
            MAX_ERROR,
            "Vault: wrong waUSDC wrapped buffer balance"
        );
        assertApproxEqAbs(
            balancesAfter.waUSDCBuffer.underlying,
            balancesBefore.waUSDCBuffer.underlying + actualAmountsInUnderlying[waUsdcIdx],
            MAX_ERROR,
            "Vault: wrong waUSDC underlying buffer balance"
        );

        assertApproxEqAbs(
            balancesAfter.waDAIBuffer.wrapped,
            balancesBefore.waDAIBuffer.wrapped - expectedAmountsInWrapped[waDaiIdx],
            MAX_ERROR,
            "Vault: wrong waDAI wrapped buffer balance"
        );
        assertApproxEqAbs(
            balancesAfter.waDAIBuffer.underlying,
            balancesBefore.waDAIBuffer.underlying + actualAmountsInUnderlying[waDaiIdx],
            MAX_ERROR,
            "Vault: wrong waDAI underlying buffer balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(erc4626Pool));
        assertApproxEqAbs(
            balances[waDaiIdx],
            waDAI.convertToShares(erc4626PoolInitialAmount) + expectedAmountsInWrapped[waDaiIdx],
            MAX_ERROR,
            "ERC4626 Pool: wrong waDAI balance"
        );
        assertApproxEqAbs(
            balances[waUsdcIdx],
            waUSDC.convertToShares(erc4626PoolInitialAmount) + expectedAmountsInWrapped[waUsdcIdx],
            MAX_ERROR,
            "ERC4626 Pool: wrong waUSDC balance"
        );

        assertEq(
            IERC20(address(erc4626Pool)).balanceOf(alice),
            exactBptAmountOut,
            "Alice: BPT balance should increase"
        );
    }

    function testAddLiquidityProportionalToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityProportionalToERC4626Pool(erc4626Pool, operationAmount, bytes(""));
    }

    function testRemoveLiquidityProportionalFromERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            erc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);

        TestBalances memory balancesBefore = _getTestBalances(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[waUsdcIdx] = waUSDC.convertToAssets(expectedWrappedAmountsOut[waUsdcIdx]) - vaultConvertFactor;
        minAmountsOut[waDaiIdx] = waDAI.convertToAssets(expectedWrappedAmountsOut[waDaiIdx]) - vaultConvertFactor;

        vm.prank(bob);
        uint256[] memory actualUnderlyingAmountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            erc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        assertApproxEqAbs(
            actualUnderlyingAmountsOut[waDaiIdx],
            waDAI.convertToAssets(expectedWrappedAmountsOut[waDaiIdx]) - vaultConvertFactor,
            MAX_ERROR,
            "DAI actualUnderlyingAmountsOut should match expected"
        );

        assertApproxEqAbs(
            actualUnderlyingAmountsOut[waUsdcIdx],
            waUSDC.convertToAssets(expectedWrappedAmountsOut[waUsdcIdx]) - vaultConvertFactor,
            MAX_ERROR,
            "USDC actualUnderlyingAmountsOut should match expected"
        );

        assertEq(
            balancesBefore.balances.bobTokens[balancesBefore.usdcIdx],
            balancesAfter.balances.bobTokens[balancesAfter.usdcIdx] - actualUnderlyingAmountsOut[waUsdcIdx],
            "Bob: wrong USDC balance"
        );
        assertEq(
            balancesBefore.balances.bobTokens[balancesBefore.daiIdx],
            balancesAfter.balances.bobTokens[balancesAfter.daiIdx] - actualUnderlyingAmountsOut[waDaiIdx],
            "Bob: wrong DAI balance"
        );

        assertApproxEqAbs(
            balancesAfter.waUSDCBuffer.wrapped,
            balancesBefore.waUSDCBuffer.wrapped + expectedWrappedAmountsOut[waUsdcIdx],
            MAX_ERROR,
            "Vault: wrong waUSDC wrapped buffer balance"
        );
        assertApproxEqAbs(
            balancesAfter.waUSDCBuffer.underlying,
            balancesBefore.waUSDCBuffer.underlying - actualUnderlyingAmountsOut[waUsdcIdx],
            MAX_ERROR,
            "Vault: wrong waUSDC underlying buffer balance"
        );

        assertApproxEqAbs(
            balancesAfter.waDAIBuffer.wrapped,
            balancesBefore.waDAIBuffer.wrapped + expectedWrappedAmountsOut[waDaiIdx],
            MAX_ERROR,
            "Vault: wrong waDAI wrapped buffer balance"
        );
        assertApproxEqAbs(
            balancesAfter.waDAIBuffer.underlying,
            balancesBefore.waDAIBuffer.underlying - actualUnderlyingAmountsOut[waDaiIdx],
            MAX_ERROR,
            "Vault: wrong waDAI underlying buffer balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(erc4626Pool));
        assertApproxEqAbs(
            balances[waDaiIdx],
            waDAI.convertToShares(erc4626PoolInitialAmount) - expectedWrappedAmountsOut[waDaiIdx],
            MAX_ERROR,
            "ERC4626 Pool: wrong waDAI balance"
        );
        assertApproxEqAbs(
            balances[waUsdcIdx],
            waUSDC.convertToShares(erc4626PoolInitialAmount) - expectedWrappedAmountsOut[waUsdcIdx],
            MAX_ERROR,
            "ERC4626 Pool: wrong waUSDC balance"
        );

        uint256 afterBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(bob) {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        vm.prank(bob, address(0));
        batchRouter.queryRemoveLiquidityProportionalFromERC4626Pool(erc4626Pool, exactBptAmountIn, bytes(""));
    }

    function testInvalidUnderlyingToken() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidUnderlyingToken.selector, waInvalid));
        vm.prank(lp);
        router.initializeBuffer(waInvalid, bufferInitialAmount, bufferInitialAmount);
    }

    struct BufferBalances {
        uint256 underlying;
        uint256 wrapped;
    }

    struct TestBalances {
        BaseVaultTest.Balances balances;
        BufferBalances waUSDCBuffer;
        BufferBalances waDAIBuffer;
        uint256 daiIdx;
        uint256 usdcIdx;
        uint256 waDaiIdx;
        uint256 waUsdcIdx;
    }

    function _getTestBalances(address sender) private view returns (TestBalances memory testBalances) {
        IERC20[] memory tokenArray = [address(dai), address(usdc), address(waDAI), address(waUSDC)]
            .toMemoryArray()
            .asIERC20();
        testBalances.balances = getBalances(sender, tokenArray);

        (uint256 waDAIBufferBalanceUnderlying, uint256 waDAIBufferBalanceWrapped) = vault.getBufferBalance(waDAI);
        testBalances.waDAIBuffer.underlying = waDAIBufferBalanceUnderlying;
        testBalances.waDAIBuffer.wrapped = waDAIBufferBalanceWrapped;

        (uint256 waUSDCBufferBalanceUnderlying, uint256 waUSDCBufferBalanceWrapped) = vault.getBufferBalance(waUSDC);
        testBalances.waUSDCBuffer.underlying = waUSDCBufferBalanceUnderlying;
        testBalances.waUSDCBuffer.wrapped = waUSDCBufferBalanceWrapped;

        testBalances.daiIdx = 0;
        testBalances.usdcIdx = 1;
        testBalances.waDaiIdx = 2;
        testBalances.waUsdcIdx = 3;
    }
}
