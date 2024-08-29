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
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BatchRouterERC4626PoolTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for *;

    uint256 constant MIN_AMOUNT = 1e12;
    uint256 internal constant MAX_ERROR = 2;

    ERC4626TestToken internal waInvalid;

    uint256 internal partialWaDaiIdx;
    uint256 internal partialUsdcIdx;
    address internal partialErc4626Pool;

    function setUp() public virtual override {
        BaseERC4626BufferTest.setUp();

        // Invalid wrapper, with a zero underlying asset.
        waInvalid = new ERC4626TestToken(IERC20(address(0)), "Invalid Wrapped", "waInvalid", 18);

        // Calculate indexes of the pair waDAI/USDC.
        (partialWaDaiIdx, partialUsdcIdx) = getSortedIndexes(address(waDAI), address(usdc));
        partialErc4626Pool = _initializePartialERC4626Pool();
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
        exactWrappedAmountsIn[waDaiIdx] = waDAI.convertToShares(operationAmount) - vaultConvertFactor;
        exactWrappedAmountsIn[waUsdcIdx] = waUSDC.convertToShares(operationAmount) - vaultConvertFactor;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(erc4626Pool, exactWrappedAmountsIn, bytes(""));
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

        TestLocals memory vars;
        vars.daiAmountDelta = exactUnderlyingAmountsIn[waDaiIdx];
        vars.usdcAmountDelta = exactUnderlyingAmountsIn[waUsdcIdx];
        vars.waDaiBufferDelta = exactWrappedAmountsIn[waDaiIdx];
        vars.waUsdcBufferDelta = exactWrappedAmountsIn[waUsdcIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars);

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(address(erc4626Pool)).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToPartialERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory exactWrappedAmountsIn = new uint256[](2);
        exactWrappedAmountsIn[partialWaDaiIdx] = waDAI.convertToShares(operationAmount) - vaultConvertFactor;
        exactWrappedAmountsIn[partialUsdcIdx] = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(partialErc4626Pool, exactWrappedAmountsIn, bytes(""));
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256 bptOut = batchRouter.addLiquidityUnbalancedToERC4626Pool(
            partialErc4626Pool,
            exactUnderlyingAmountsIn,
            0,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.daiAmountDelta = exactUnderlyingAmountsIn[partialWaDaiIdx];
        vars.usdcAmountDelta = exactUnderlyingAmountsIn[partialUsdcIdx];
        vars.waDaiBufferDelta = exactWrappedAmountsIn[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars);

        assertEq(bptOut, expectBPTOut, "Wrong BPT out");
        assertEq(IERC20(address(partialErc4626Pool)).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityUnbalancedToERC4626Pool(erc4626Pool, exactUnderlyingAmountsIn, bytes(""));
    }

    function testQueryAddLiquidityUnbalancedToERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256 snapshotId = vm.snapshot();
        vm.prank(alice, address(0));
        uint256 queryBptAmountOut = batchRouter.queryAddLiquidityUnbalancedToERC4626Pool(
            erc4626Pool,
            exactUnderlyingAmountsIn,
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 actualBptAmountOut = batchRouter.addLiquidityUnbalancedToERC4626Pool(
            erc4626Pool,
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        // Query and actual operation have a small difference in the buffer operation: a query in the buffer returns
        // the amount of wrapped tokens calculated by a "preview" operation, while the actual operation in the buffer
        // returns the "convertToShares" result + vaultConvertFactor. Since the wrapped amount out of each buffer is
        // added to the yield-bearing pool and converted to the equivalent underlying amount to calculate the
        // poolInvariantDelta (which, in this case, is the bptAmountOut), we need to consider the error added by
        // vaultConvertFactor scaled by each token rate.
        uint256 invariantError = vaultConvertFactor.mulDown(waDAI.getRate()) +
            vaultConvertFactor.mulDown(waUSDC.getRate());

        assertApproxEqAbs(
            queryBptAmountOut,
            actualBptAmountOut + invariantError,
            MAX_ERROR,
            "Query and actual bpt amount out do not match"
        );
    }

    function testQueryAddLiquidityUnbalancedToPartialERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256 snapshotId = vm.snapshot();
        vm.prank(alice, address(0));
        uint256 queryBptAmountOut = batchRouter.queryAddLiquidityUnbalancedToERC4626Pool(
            partialErc4626Pool,
            exactUnderlyingAmountsIn,
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 actualBptAmountOut = batchRouter.addLiquidityUnbalancedToERC4626Pool(
            partialErc4626Pool,
            exactUnderlyingAmountsIn,
            1,
            false,
            bytes("")
        );

        // Query and actual operation have a small difference in the buffer operation: a query in the buffer returns
        // the amount of wrapped tokens calculated by a "preview" operation, while the actual operation in the buffer
        // returns the "convertToShares" result + vaultConvertFactor. Since the wrapped amount out of each buffer is
        // added to the yield-bearing pool and converted to the equivalent underlying amount to calculate the
        // poolInvariantDelta (which, in this case, is the bptAmountOut), we need to consider the error added by
        // vaultConvertFactor scaled by each token rate.
        uint256 invariantError = vaultConvertFactor.mulDown(waDAI.getRate());

        assertApproxEqAbs(
            queryBptAmountOut,
            actualBptAmountOut + invariantError,
            MAX_ERROR,
            "Query and actual bpt amount out do not match"
        );
    }

    function testAddLiquidityProportionalToERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsIn = router.queryAddLiquidityProportional(
            erc4626Pool,
            exactBptAmountOut,
            bytes("")
        );
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256[] memory actualUnderlyingAmountsIn = batchRouter.addLiquidityProportionalToERC4626Pool(
            erc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.daiAmountDelta = actualUnderlyingAmountsIn[waDaiIdx];
        vars.usdcAmountDelta = actualUnderlyingAmountsIn[waUsdcIdx];
        vars.waDaiBufferDelta = expectedWrappedAmountsIn[waDaiIdx];
        vars.waUsdcBufferDelta = expectedWrappedAmountsIn[waUsdcIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars);

        assertApproxEqAbs(
            actualUnderlyingAmountsIn[waDaiIdx],
            waDAI.convertToAssets(expectedWrappedAmountsIn[waDaiIdx]) + vaultConvertFactor,
            MAX_ERROR,
            "DAI actualAmountsInUnderlying should match expected"
        );
        assertApproxEqAbs(
            actualUnderlyingAmountsIn[waUsdcIdx],
            waUSDC.convertToAssets(expectedWrappedAmountsIn[waUsdcIdx]) + vaultConvertFactor,
            MAX_ERROR,
            "USDC actualAmountsInUnderlying should match expected"
        );

        assertEq(
            IERC20(address(erc4626Pool)).balanceOf(alice),
            exactBptAmountOut,
            "Alice: BPT balance should increase"
        );
    }

    function testAddLiquidityProportionalToPartialERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        // Make sure the operation is within the buffer liquidity.
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 10);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsIn = router.queryAddLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountOut,
            bytes("")
        );

        uint256[] memory expectedUnderlyingAmountsIn = new uint256[](2);
        expectedUnderlyingAmountsIn[partialWaDaiIdx] = waDAI.previewMint(expectedWrappedAmountsIn[partialWaDaiIdx]);
        expectedUnderlyingAmountsIn[partialUsdcIdx] = expectedWrappedAmountsIn[partialUsdcIdx];
        vm.revertTo(snapshot);

        TestBalances memory balancesBefore = _getTestBalances(alice);

        vm.prank(alice);
        uint256[] memory actualUnderlyingAmountsIn = batchRouter.addLiquidityProportionalToERC4626Pool(
            partialErc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(alice);

        TestLocals memory vars;
        vars.daiAmountDelta = actualUnderlyingAmountsIn[partialWaDaiIdx];
        vars.usdcAmountDelta = actualUnderlyingAmountsIn[partialUsdcIdx];
        vars.waDaiBufferDelta = expectedWrappedAmountsIn[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;

        _checkBalancesAfterAddLiquidity(balancesBefore, balancesAfter, vars);

        assertApproxEqAbs(
            actualUnderlyingAmountsIn[partialWaDaiIdx],
            waDAI.convertToAssets(expectedWrappedAmountsIn[partialWaDaiIdx]) + vaultConvertFactor,
            MAX_ERROR,
            "DAI actualAmountsInUnderlying should match expected"
        );
        // `expectedWrappedAmountsIn` in this case is equal to expected underlying since USDC is not a wrapped token.
        assertApproxEqAbs(
            actualUnderlyingAmountsIn[partialUsdcIdx],
            expectedWrappedAmountsIn[partialUsdcIdx],
            MAX_ERROR,
            "USDC actualAmountsInUnderlying should match expected"
        );

        assertEq(IERC20(address(partialErc4626Pool)).balanceOf(alice), exactBptAmountOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityProportionalToERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(alice) {
        uint256 operationAmount = bufferInitialAmount / 2;

        vm.prank(alice, address(0));
        batchRouter.queryAddLiquidityProportionalToERC4626Pool(erc4626Pool, operationAmount, bytes(""));
    }

    function testQueryAddLiquidityProportionalToERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshotId = vm.snapshot();
        vm.prank(alice, address(0));
        uint256[] memory queryUnderlyingAmountsIn = batchRouter.queryAddLiquidityProportionalToERC4626Pool(
            erc4626Pool,
            exactBptAmountOut,
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256[] memory actualUnderlyingAmountsIn = batchRouter.addLiquidityProportionalToERC4626Pool(
            erc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        for (uint256 i = 0; i < queryUnderlyingAmountsIn.length; i++) {
            // Query and actual operation have a small difference in the buffer operation: a query in the buffer
            // returns the amount of underlying tokens calculated by a "preview" operation, while the actual operation
            // in the buffer returns the "convertToAssets" result - vaultConvertFactor. In the addLiquidity case, we
            // charge "vaultConvertFactor" extra tokens from the user than the query predicted.
            assertApproxEqAbs(
                actualUnderlyingAmountsIn[i],
                queryUnderlyingAmountsIn[i] + vaultConvertFactor,
                MAX_ERROR,
                "Query and actual underlying amounts in do not match"
            );
        }
    }

    function testQueryAddLiquidityProportionalToPartialERC4626Pool() public {
        uint256 operationAmount = bufferInitialAmount / 2;
        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshotId = vm.snapshot();
        vm.prank(alice, address(0));
        uint256[] memory queryUnderlyingAmountsIn = batchRouter.queryAddLiquidityProportionalToERC4626Pool(
            partialErc4626Pool,
            exactBptAmountOut,
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256[] memory actualUnderlyingAmountsIn = batchRouter.addLiquidityProportionalToERC4626Pool(
            partialErc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        // Query and actual operation have a small difference in the buffer operation: a query in the buffer
        // returns the amount of underlying tokens calculated by a "preview" operation, while the actual operation
        // in the buffer returns the "convertToAssets" result - vaultConvertFactor. In the addLiquidity case, we charge
        // "vaultConvertFactor" extra tokens from the user than the query predicted.
        assertApproxEqAbs(
            actualUnderlyingAmountsIn[partialWaDaiIdx],
            queryUnderlyingAmountsIn[partialWaDaiIdx] + vaultConvertFactor,
            MAX_ERROR,
            "Query and actual DAI amounts in do not match"
        );

        assertApproxEqAbs(
            queryUnderlyingAmountsIn[partialUsdcIdx],
            actualUnderlyingAmountsIn[partialUsdcIdx],
            MAX_ERROR,
            "Query and actual USDC amounts in do not match"
        );
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

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[waUsdcIdx] = waUSDC.convertToAssets(expectedWrappedAmountsOut[waUsdcIdx]) - vaultConvertFactor;
        minAmountsOut[waDaiIdx] = waDAI.convertToAssets(expectedWrappedAmountsOut[waDaiIdx]) - vaultConvertFactor;

        TestBalances memory balancesBefore = _getTestBalances(bob);

        vm.prank(bob);
        uint256[] memory actualUnderlyingAmountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            erc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        TestLocals memory vars;
        vars.daiAmountDelta = actualUnderlyingAmountsOut[waDaiIdx];
        vars.usdcAmountDelta = actualUnderlyingAmountsOut[waUsdcIdx];
        vars.waDaiBufferDelta = expectedWrappedAmountsOut[waDaiIdx];
        vars.waUsdcBufferDelta = expectedWrappedAmountsOut[waUsdcIdx];
        vars.isPartialERC4626Pool = false;

        _checkBalancesAfterRemoveLiquidity(balancesBefore, balancesAfter, vars);

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

        uint256 afterBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromPartialERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedWrappedAmountsOut = router.queryRemoveLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(address(partialErc4626Pool)).balanceOf(bob);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[partialUsdcIdx] = expectedWrappedAmountsOut[partialUsdcIdx];
        minAmountsOut[partialWaDaiIdx] =
            waDAI.convertToAssets(expectedWrappedAmountsOut[partialWaDaiIdx]) -
            vaultConvertFactor;

        TestBalances memory balancesBefore = _getTestBalances(bob);

        vm.prank(bob);
        uint256[] memory actualUnderlyingAmountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            partialErc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        TestBalances memory balancesAfter = _getTestBalances(bob);

        TestLocals memory vars;
        vars.daiAmountDelta = actualUnderlyingAmountsOut[partialWaDaiIdx];
        vars.usdcAmountDelta = actualUnderlyingAmountsOut[partialUsdcIdx];
        vars.waDaiBufferDelta = expectedWrappedAmountsOut[partialWaDaiIdx];
        vars.isPartialERC4626Pool = true;

        _checkBalancesAfterRemoveLiquidity(balancesBefore, balancesAfter, vars);

        assertApproxEqAbs(
            actualUnderlyingAmountsOut[partialWaDaiIdx],
            waDAI.convertToAssets(expectedWrappedAmountsOut[partialWaDaiIdx]) - vaultConvertFactor,
            MAX_ERROR,
            "DAI actualUnderlyingAmountsOut should match expected"
        );

        // `expectedWrappedAmountsOut` in this case is equal to expected underlying since USDC is not a wrapped token.
        assertApproxEqAbs(
            actualUnderlyingAmountsOut[partialUsdcIdx],
            expectedWrappedAmountsOut[partialUsdcIdx],
            MAX_ERROR,
            "USDC actualUnderlyingAmountsOut should match expected"
        );

        uint256 afterBPTBalance = IERC20(address(partialErc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromERC4626PoolWhenStaticCall() public checkBuffersWhenStaticCall(bob) {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        vm.prank(bob, address(0));
        batchRouter.queryRemoveLiquidityProportionalFromERC4626Pool(erc4626Pool, exactBptAmountIn, bytes(""));
    }

    function testQueryRemoveLiquidityProportionalFromERC4626Pool() public {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsOut = router.queryRemoveLiquidityProportional(
            erc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[waUsdcIdx] = waUSDC.convertToAssets(expectedAmountsOut[waUsdcIdx]) - vaultConvertFactor;
        minAmountsOut[waDaiIdx] = waDAI.convertToAssets(expectedAmountsOut[waDaiIdx]) - vaultConvertFactor;

        uint256 snapshotId = vm.snapshot();
        vm.prank(bob, address(0));
        uint256[] memory queryUnderlyingAmountsOut = batchRouter.queryRemoveLiquidityProportionalFromERC4626Pool(
            erc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(bob);
        uint256[] memory actualUnderlyingAmountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            erc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        for (uint256 i = 0; i < queryUnderlyingAmountsOut.length; i++) {
            // Query and actual operation have a small difference in the buffer operation: a query in the buffer
            // returns the amount of underlying tokens calculated by a "preview" operation, while the actual operation
            // in the buffer returns the "convertToAssets" result - vaultConvertFactor. In the removeLiquidity case, we
            // return "vaultConvertFactor" less tokens to the user than the query predicted.
            assertApproxEqAbs(
                actualUnderlyingAmountsOut[i],
                queryUnderlyingAmountsOut[i] - vaultConvertFactor,
                MAX_ERROR,
                "Query and actual underlying amounts out do not match"
            );
        }
    }

    function testQueryRemoveLiquidityProportionalFromPartialERC4626Pool() public {
        uint256 exactBptAmountIn = bufferInitialAmount / 2;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsOut = router.queryRemoveLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[partialUsdcIdx] = expectedAmountsOut[partialUsdcIdx];
        minAmountsOut[partialWaDaiIdx] =
            waDAI.convertToAssets(expectedAmountsOut[partialWaDaiIdx]) -
            vaultConvertFactor;

        uint256 snapshotId = vm.snapshot();
        vm.prank(bob, address(0));
        uint256[] memory queryUnderlyingAmountsOut = batchRouter.queryRemoveLiquidityProportionalFromERC4626Pool(
            partialErc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(bob);
        uint256[] memory actualUnderlyingAmountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            partialErc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        // Query and actual operation have a small difference in the buffer operation: a query in the buffer
        // returns the amount of underlying tokens calculated by a "preview" operation, while the actual operation
        // in the buffer returns the "convertToAssets" result - vaultConvertFactor. In the removeLiquidity case, we
        // return "vaultConvertFactor" less tokens to the user than the query predicted.
        assertApproxEqAbs(
            actualUnderlyingAmountsOut[partialWaDaiIdx],
            queryUnderlyingAmountsOut[partialWaDaiIdx] - vaultConvertFactor,
            MAX_ERROR,
            "Query and actual DAI amounts out do not match"
        );

        assertApproxEqAbs(
            queryUnderlyingAmountsOut[partialUsdcIdx],
            actualUnderlyingAmountsOut[partialUsdcIdx],
            MAX_ERROR,
            "Query and actual USDC amounts out do not match"
        );
    }

    function testInvalidUnderlyingToken() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.InvalidUnderlyingToken.selector, waInvalid));
        vm.prank(lp);
        router.initializeBuffer(waInvalid, bufferInitialAmount, bufferInitialAmount);
    }

    struct TestLocals {
        uint256 daiAmountDelta;
        uint256 usdcAmountDelta;
        uint256 waDaiBufferDelta;
        uint256 waUsdcBufferDelta;
        bool isPartialERC4626Pool;
    }

    function _checkBalancesAfterAddLiquidity(
        TestBalances memory balancesBefore,
        TestBalances memory balancesAfter,
        TestLocals memory vars
    ) private {
        address ybPool = vars.isPartialERC4626Pool ? partialErc4626Pool : erc4626Pool;
        uint256 ybDaiIdx = vars.isPartialERC4626Pool ? partialWaDaiIdx : waDaiIdx;
        uint256 ybUsdcIdx = vars.isPartialERC4626Pool ? partialUsdcIdx : waUsdcIdx;

        assertEq(
            balancesAfter.balances.aliceTokens[balancesAfter.usdcIdx],
            balancesBefore.balances.aliceTokens[balancesBefore.usdcIdx] - vars.usdcAmountDelta,
            "Alice: wrong USDC balance"
        );
        assertEq(
            balancesAfter.balances.aliceTokens[balancesAfter.daiIdx],
            balancesBefore.balances.aliceTokens[balancesBefore.daiIdx] - vars.daiAmountDelta,
            "Alice: wrong DAI balance"
        );

        assertEq(
            balancesAfter.waDAIBuffer.wrapped,
            balancesBefore.waDAIBuffer.wrapped - vars.waDaiBufferDelta,
            "Vault: wrong waDAI wrapped buffer balance"
        );
        assertEq(
            balancesAfter.waDAIBuffer.underlying,
            balancesBefore.waDAIBuffer.underlying + vars.daiAmountDelta,
            "Vault: wrong waDAI underlying buffer balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(ybPool);
        assertApproxEqAbs(
            balances[ybDaiIdx],
            waDAI.convertToShares(erc4626PoolInitialAmount) + vars.waDaiBufferDelta,
            MAX_ERROR,
            "ERC4626 Pool: wrong waDAI balance"
        );

        if (vars.isPartialERC4626Pool == false) {
            assertEq(
                balancesAfter.waUSDCBuffer.wrapped,
                balancesBefore.waUSDCBuffer.wrapped - vars.waUsdcBufferDelta,
                "Vault: wrong waUSDC wrapped buffer balance"
            );
            assertEq(
                balancesAfter.waUSDCBuffer.underlying,
                balancesBefore.waUSDCBuffer.underlying + vars.usdcAmountDelta,
                "Vault: wrong waUSDC underlying buffer balance"
            );
            assertApproxEqAbs(
                balances[ybUsdcIdx],
                waUSDC.convertToShares(erc4626PoolInitialAmount) + vars.waUsdcBufferDelta,
                MAX_ERROR,
                "ERC4626 Pool: wrong waUSDC balance"
            );
        } else {
            assertApproxEqAbs(
                balances[ybUsdcIdx],
                erc4626PoolInitialAmount + vars.usdcAmountDelta,
                MAX_ERROR,
                "ERC4626 Pool: wrong USDC balance"
            );
        }
    }

    function _checkBalancesAfterRemoveLiquidity(
        TestBalances memory balancesBefore,
        TestBalances memory balancesAfter,
        TestLocals memory vars
    ) private {
        address ybPool = vars.isPartialERC4626Pool ? partialErc4626Pool : erc4626Pool;
        uint256 ybDaiIdx = vars.isPartialERC4626Pool ? partialWaDaiIdx : waDaiIdx;
        uint256 ybUsdcIdx = vars.isPartialERC4626Pool ? partialUsdcIdx : waUsdcIdx;

        assertEq(
            balancesAfter.balances.bobTokens[balancesAfter.usdcIdx],
            balancesBefore.balances.bobTokens[balancesBefore.usdcIdx] + vars.usdcAmountDelta,
            "Bob: wrong USDC balance"
        );
        assertEq(
            balancesAfter.balances.bobTokens[balancesAfter.daiIdx],
            balancesBefore.balances.bobTokens[balancesBefore.daiIdx] + vars.daiAmountDelta,
            "Bob: wrong DAI balance"
        );

        assertEq(
            balancesAfter.waDAIBuffer.wrapped,
            balancesBefore.waDAIBuffer.wrapped + vars.waDaiBufferDelta,
            "Vault: wrong waDAI wrapped buffer balance"
        );
        assertEq(
            balancesAfter.waDAIBuffer.underlying,
            balancesBefore.waDAIBuffer.underlying - vars.daiAmountDelta,
            "Vault: wrong waDAI underlying buffer balance"
        );

        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(ybPool);
        assertApproxEqAbs(
            balances[ybDaiIdx],
            waDAI.convertToShares(erc4626PoolInitialAmount) - vars.waDaiBufferDelta,
            MAX_ERROR,
            "ERC4626 Pool: wrong waDAI balance"
        );

        if (vars.isPartialERC4626Pool == false) {
            assertEq(
                balancesAfter.waUSDCBuffer.wrapped,
                balancesBefore.waUSDCBuffer.wrapped + vars.waUsdcBufferDelta,
                "Vault: wrong waUSDC wrapped buffer balance"
            );
            assertEq(
                balancesAfter.waUSDCBuffer.underlying,
                balancesBefore.waUSDCBuffer.underlying - vars.usdcAmountDelta,
                "Vault: wrong waUSDC underlying buffer balance"
            );
            assertApproxEqAbs(
                balances[ybUsdcIdx],
                waUSDC.convertToShares(erc4626PoolInitialAmount) - vars.waUsdcBufferDelta,
                MAX_ERROR,
                "ERC4626 Pool: wrong waUSDC balance"
            );
        } else {
            assertApproxEqAbs(
                balances[ybUsdcIdx],
                erc4626PoolInitialAmount - vars.usdcAmountDelta,
                MAX_ERROR,
                "ERC4626 Pool: wrong USDC balance"
            );
        }
    }

    function _initializePartialERC4626Pool() private returns (address newPool) {
        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        tokenConfig[partialWaDaiIdx].token = IERC20(waDAI);
        tokenConfig[partialUsdcIdx].token = IERC20(usdc);
        tokenConfig[partialWaDaiIdx].tokenType = TokenType.WITH_RATE;
        tokenConfig[partialUsdcIdx].tokenType = TokenType.STANDARD;
        tokenConfig[partialWaDaiIdx].rateProvider = IRateProvider(address(waDAI));

        newPool = address(new PoolMock(IVault(address(vault)), "PARTIAL ERC4626 Pool", "PART-ERC4626P"));

        factoryMock.registerTestPool(newPool, tokenConfig, poolHooksContract);

        vm.label(newPool, "partial erc4626 pool");

        vm.startPrank(bob);
        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);

        dai.mint(bob, erc4626PoolInitialAmount);
        dai.approve(address(waDAI), erc4626PoolInitialAmount);
        uint256 waDaiShares = waDAI.deposit(erc4626PoolInitialAmount, bob);

        usdc.mint(bob, erc4626PoolInitialAmount);

        uint256[] memory initAmounts = new uint256[](2);
        initAmounts[partialWaDaiIdx] = waDaiShares;
        initAmounts[partialUsdcIdx] = erc4626PoolInitialAmount;

        _initPool(newPool, initAmounts, erc4626PoolInitialBPTAmount - MAX_ERROR - MIN_BPT);

        IERC20(newPool).approve(address(permit2), MAX_UINT256);
        permit2.approve(newPool, address(router), type(uint160).max, type(uint48).max);
        permit2.approve(newPool, address(batchRouter), type(uint160).max, type(uint48).max);

        IERC20(address(newPool)).approve(address(router), type(uint256).max);
        IERC20(address(newPool)).approve(address(batchRouter), type(uint256).max);
        vm.stopPrank();
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
