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

import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { BaseERC4626BufferTest } from "./utils/BaseERC4626BufferTest.sol";

contract BatchRouterERC4626PoolTest is BaseERC4626BufferTest {
    using ArrayHelpers for *;

    uint256 constant MIN_AMOUNT = 1e12;
    uint256 internal constant MAX_ERROR = 10;

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

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(erc4626Pool, exactWrappedAmountsIn, bytes(""));
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
            bytes("")
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(
                afterUSDCBalance,
                beforeUSDCBalance - exactUnderlyingAmountsIn[waUsdcIdx],
                "Alice: wrong USDC balance"
            );
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(
                afterDAIBalance,
                beforeDAIBalance - exactUnderlyingAmountsIn[waDaiIdx],
                "Alice: wrong DAI balance"
            );
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertEq(
                afterWaUSDCBufferBalanceWrapped,
                beforeWaUSDCBufferBalanceWrapped - exactWrappedAmountsIn[waUsdcIdx],
                "Vault: wrong waUSDC wrapped buffer balance"
            );
            assertEq(
                beforeWaUSDCBufferBalanceUnderlying,
                afterWaUSDCBufferBalanceUnderlying - exactUnderlyingAmountsIn[waUsdcIdx],
                "Vault: wrong waUSDC underlying buffer balance"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertEq(
                afterWaDAIBufferBalanceWrapped,
                beforeWaDAIBufferBalanceWrapped - exactWrappedAmountsIn[waDaiIdx],
                "Vault: wrong waDAI wrapped buffer balance"
            );
            assertEq(
                beforeWaDAIBufferBalanceUnderlying,
                afterWaDAIBufferBalanceUnderlying - exactUnderlyingAmountsIn[waDaiIdx],
                "Vault: wrong waDAI underlying buffer balance"
            );
        }
        {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(erc4626Pool));
            assertApproxEqAbs(
                lastBalancesLiveScaled18[waDaiIdx],
                erc4626PoolInitialAmount + exactUnderlyingAmountsIn[waDaiIdx],
                MAX_ERROR,
                "ERC4626 Pool: wrong waDAI balance"
            );
            assertApproxEqAbs(
                lastBalancesLiveScaled18[waUsdcIdx],
                erc4626PoolInitialAmount + exactUnderlyingAmountsIn[waUsdcIdx],
                MAX_ERROR,
                "ERC4626 Pool: wrong waUSDC balance"
            );
        }

        assertEq(bptOut, expectBPTOut, "BPT operationAmount should match expected");
        assertEq(IERC20(address(erc4626Pool)).balanceOf(alice), bptOut, "Alice: wrong BPT balance");
    }

    function testAddLiquidityUnbalancedToPartialERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);
        uint256[] memory exactUnderlyingAmountsIn = [operationAmount, operationAmount].toMemoryArray();

        uint256[] memory amountsInErc4626Pool = new uint256[](2);
        amountsInErc4626Pool[partialWaDaiIdx] = waDAI.convertToShares(operationAmount);
        amountsInErc4626Pool[partialUsdcIdx] = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256 expectBPTOut = router.queryAddLiquidityUnbalanced(partialErc4626Pool, amountsInErc4626Pool, bytes(""));
        vm.revertTo(snapshot);

        uint256 beforeUSDCBalance = usdc.balanceOf(alice);
        uint256 beforeDAIBalance = dai.balanceOf(alice);

        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(alice);
        uint256 bptOut = batchRouter.addLiquidityUnbalancedToERC4626Pool(
            partialErc4626Pool,
            exactUnderlyingAmountsIn,
            0,
            false,
            bytes("")
        );

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(afterUSDCBalance, beforeUSDCBalance - operationAmount, "Alice: wrong USDC balance");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(afterDAIBalance, beforeDAIBalance - operationAmount, "Alice: wrong DAI balance");
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertEq(
                afterWaDAIBufferBalanceWrapped,
                beforeWaDAIBufferBalanceWrapped - amountsInErc4626Pool[partialWaDaiIdx],
                "Vault: wrong waDAI wrapped buffer balance"
            );
            assertEq(
                beforeWaDAIBufferBalanceUnderlying,
                afterWaDAIBufferBalanceUnderlying - exactUnderlyingAmountsIn[partialWaDaiIdx],
                "Vault: wrong waDAI underlying buffer balance"
            );
        }
        {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(partialErc4626Pool));
            assertApproxEqAbs(
                lastBalancesLiveScaled18[partialWaDaiIdx],
                erc4626PoolInitialAmount + exactUnderlyingAmountsIn[partialWaDaiIdx],
                MAX_ERROR,
                "Partial ERC4626 Pool: wrong waDAI balance"
            );
            assertApproxEqAbs(
                lastBalancesLiveScaled18[partialUsdcIdx],
                erc4626PoolInitialAmount + exactUnderlyingAmountsIn[partialUsdcIdx],
                MAX_ERROR,
                "Partial ERC4626 Pool: wrong USDC balance"
            );
        }

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

        assertEq(queryBptAmountOut, actualBptAmountOut, "Query and actual bpt amount out do not match");
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

        assertEq(queryBptAmountOut, actualBptAmountOut, "Query and actual bpt amount out do not match");
    }

    function testAddLiquidityProportionalToERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 operationAmount = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256[] memory maxAmountsIn = [operationAmount, operationAmount].toMemoryArray();
        uint256 exactBptAmountOut = operationAmount;

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsIn = router.queryAddLiquidityProportional(
            erc4626Pool,
            exactBptAmountOut,
            bytes("")
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
            bytes("")
        );

        IERC20[] memory erc4626PoolTokens = vault.getPoolTokens(erc4626Pool);

        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertApproxEqAbs(
                IERC4626(address(erc4626PoolTokens[i])).convertToShares(amountsIn[i]),
                expectedAmountsIn[i],
                MAX_ERROR,
                "AmountIn should match expected"
            );
        }

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(afterUSDCBalance, beforeUSDCBalance - amountsIn[waUsdcIdx], "Alice: wrong USDC balance");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(afterDAIBalance, beforeDAIBalance - amountsIn[waDaiIdx], "Alice: wrong DAI balance");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertApproxEqAbs(
                afterWaUSDCBufferBalanceWrapped,
                beforeWaUSDCBufferBalanceWrapped - waUSDC.convertToShares(amountsIn[waUsdcIdx]),
                MAX_ERROR,
                "Vault: wrong waUSDC wrapped buffer balance"
            );
            assertApproxEqAbs(
                beforeWaUSDCBufferBalanceUnderlying,
                afterWaUSDCBufferBalanceUnderlying - amountsIn[1],
                MAX_ERROR,
                "Vault: wrong waUSDC underlying buffer balance"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertApproxEqAbs(
                afterWaDAIBufferBalanceWrapped,
                beforeWaDAIBufferBalanceWrapped - waDAI.convertToShares(amountsIn[0]),
                MAX_ERROR,
                "Vault: wrong waDAI wrapped buffer balance"
            );
            assertApproxEqAbs(
                beforeWaDAIBufferBalanceUnderlying,
                afterWaDAIBufferBalanceUnderlying - amountsIn[1],
                MAX_ERROR,
                "Vault: wrong waDAI underlying buffer balance"
            );
        }
        {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(erc4626Pool));
            assertApproxEqAbs(
                lastBalancesLiveScaled18[waDaiIdx],
                erc4626PoolInitialAmount + amountsIn[waDaiIdx],
                MAX_ERROR,
                "ERC4626 Pool: wrong waDAI balance"
            );
            assertApproxEqAbs(
                lastBalancesLiveScaled18[waUsdcIdx],
                erc4626PoolInitialAmount + amountsIn[waUsdcIdx],
                MAX_ERROR,
                "ERC4626 Pool: wrong waUSDC balance"
            );
        }

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

        uint256 beforeUSDCBalance = usdc.balanceOf(alice);
        uint256 beforeDAIBalance = dai.balanceOf(alice);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        vm.prank(alice);
        uint256[] memory underlyingAmountsIn = batchRouter.addLiquidityProportionalToERC4626Pool(
            partialErc4626Pool,
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        for (uint256 i = 0; i < underlyingAmountsIn.length; i++) {
            // The query and actual operation may differ by 1 wei.
            assertApproxEqAbs(
                underlyingAmountsIn[i],
                expectedUnderlyingAmountsIn[i],
                1,
                "underlyingAmountsIn should match expected"
            );
        }

        {
            uint256 afterUSDCBalance = usdc.balanceOf(alice);
            assertEq(
                afterUSDCBalance,
                beforeUSDCBalance - underlyingAmountsIn[partialUsdcIdx],
                "Alice: wrong USDC balance"
            );
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(alice);
            assertEq(
                afterDAIBalance,
                beforeDAIBalance - underlyingAmountsIn[partialWaDaiIdx],
                "Alice: wrong DAI balance"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);

            assertEq(
                afterWaDAIBufferBalanceWrapped,
                beforeWaDAIBufferBalanceWrapped - expectedWrappedAmountsIn[partialWaDaiIdx],
                "Vault: wrong waDAI wrapped buffer balance"
            );
            assertEq(
                afterWaDAIBufferBalanceUnderlying,
                beforeWaDAIBufferBalanceUnderlying + underlyingAmountsIn[partialWaDaiIdx],
                "Vault: wrong waDAI underlying buffer balance"
            );
        }
        {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(partialErc4626Pool));
            // There may be a difference of some wei between preview and actual wrap operation.
            assertApproxEqAbs(
                lastBalancesLiveScaled18[partialWaDaiIdx],
                erc4626PoolInitialAmount + expectedUnderlyingAmountsIn[partialWaDaiIdx],
                MAX_ERROR,
                "Partial ERC4626 Pool: wrong waDAI balance"
            );
            assertApproxEqAbs(
                lastBalancesLiveScaled18[partialUsdcIdx],
                erc4626PoolInitialAmount + expectedUnderlyingAmountsIn[partialUsdcIdx],
                MAX_ERROR,
                "Partial ERC4626 Pool: wrong waUSDC balance"
            );
        }

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
            // Real operation and preview may have a difference.
            assertApproxEqAbs(
                queryUnderlyingAmountsIn[i],
                actualUnderlyingAmountsIn[i],
                5,
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

        for (uint256 i = 0; i < queryUnderlyingAmountsIn.length; i++) {
            // Real operation and preview may have a difference.
            assertApproxEqAbs(
                queryUnderlyingAmountsIn[i],
                actualUnderlyingAmountsIn[i],
                5,
                "Query and actual underlying amounts in do not match"
            );
        }
    }

    function testRemoveLiquidityProportionalFromERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsOut = router.queryRemoveLiquidityProportional(
            erc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        uint256 beforeUSDCBalance = usdc.balanceOf(bob);
        uint256 beforeDAIBalance = dai.balanceOf(bob);
        (uint256 beforeWaUSDCBufferBalanceUnderlying, uint256 beforeWaUSDCBufferBalanceWrapped) = vault
            .getBufferBalance(waUSDC);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[waUsdcIdx] = waUSDC.convertToAssets(expectedAmountsOut[waUsdcIdx]);
        minAmountsOut[waDaiIdx] = waDAI.convertToAssets(expectedAmountsOut[waDaiIdx]);

        vm.prank(bob);
        uint256[] memory underlyingAmountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            erc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );
        uint256[] memory wrappedAmountsOut = new uint256[](2);
        wrappedAmountsOut[waDaiIdx] = waDAI.convertToShares(underlyingAmountsOut[waDaiIdx]);
        wrappedAmountsOut[waUsdcIdx] = waUSDC.convertToShares(underlyingAmountsOut[waUsdcIdx]);

        for (uint256 i = 0; i < underlyingAmountsOut.length; i++) {
            assertApproxEqAbs(
                wrappedAmountsOut[i],
                expectedAmountsOut[i],
                MAX_ERROR,
                "AmountOut should match expected"
            );
        }

        {
            uint256 afterUSDCBalance = usdc.balanceOf(bob);
            assertEq(beforeUSDCBalance, afterUSDCBalance - underlyingAmountsOut[waUsdcIdx], "Bob: wrong USDC balance");
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(bob);
            assertEq(beforeDAIBalance, afterDAIBalance - underlyingAmountsOut[waDaiIdx], "Bob: wrong DAI balance");
        }
        {
            (uint256 afterWaUSDCBufferBalanceUnderlying, uint256 afterWaUSDCBufferBalanceWrapped) = vault
                .getBufferBalance(waUSDC);
            assertApproxEqAbs(
                beforeWaUSDCBufferBalanceWrapped,
                afterWaUSDCBufferBalanceWrapped - wrappedAmountsOut[waUsdcIdx],
                MAX_ERROR,
                "Vault: wrong waUSDC wrapped buffer balance"
            );
            assertApproxEqAbs(
                beforeWaUSDCBufferBalanceUnderlying,
                afterWaUSDCBufferBalanceUnderlying + underlyingAmountsOut[waUsdcIdx],
                MAX_ERROR,
                "Vault: wrong waUSDC underlying buffer balance"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertApproxEqAbs(
                beforeWaDAIBufferBalanceWrapped,
                afterWaDAIBufferBalanceWrapped - wrappedAmountsOut[waDaiIdx],
                MAX_ERROR,
                "Vault: wrong waDAI wrapped buffer balance"
            );
            assertApproxEqAbs(
                afterWaDAIBufferBalanceUnderlying,
                beforeWaDAIBufferBalanceUnderlying - underlyingAmountsOut[waDaiIdx],
                MAX_ERROR,
                "Vault: wrong waDAI underlying buffer balance"
            );
        }
        {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(erc4626Pool));
            assertApproxEqAbs(
                lastBalancesLiveScaled18[waDaiIdx],
                erc4626PoolInitialAmount - underlyingAmountsOut[waDaiIdx],
                MAX_ERROR,
                "ERC4626 Pool: wrong waDAI balance"
            );
            assertApproxEqAbs(
                lastBalancesLiveScaled18[waUsdcIdx],
                erc4626PoolInitialAmount - underlyingAmountsOut[waUsdcIdx],
                MAX_ERROR,
                "ERC4626 Pool: wrong waUSDC balance"
            );
        }

        uint256 afterBPTBalance = IERC20(address(erc4626Pool)).balanceOf(bob);
        assertEq(afterBPTBalance, beforeBPTBalance - exactBptAmountIn, "Bob: wrong BPT balance");
    }

    function testRemoveLiquidityProportionalFromPartialERC4626Pool_Fuzz(uint256 rawOperationAmount) public {
        uint256 exactBptAmountIn = bound(rawOperationAmount, MIN_AMOUNT, bufferInitialAmount / 2);

        uint256 snapshot = vm.snapshot();
        _prankStaticCall();
        uint256[] memory expectedAmountsOut = router.queryRemoveLiquidityProportional(
            partialErc4626Pool,
            exactBptAmountIn,
            bytes("")
        );
        vm.revertTo(snapshot);

        uint256 beforeBPTBalance = IERC20(address(partialErc4626Pool)).balanceOf(bob);
        uint256 beforeUSDCBalance = usdc.balanceOf(bob);
        uint256 beforeDAIBalance = dai.balanceOf(bob);
        (uint256 beforeWaDAIBufferBalanceUnderlying, uint256 beforeWaDAIBufferBalanceWrapped) = vault.getBufferBalance(
            waDAI
        );

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[partialUsdcIdx] = expectedAmountsOut[partialUsdcIdx];
        minAmountsOut[partialWaDaiIdx] = waDAI.convertToAssets(expectedAmountsOut[partialWaDaiIdx]);

        vm.prank(bob);
        uint256[] memory underlyingAmountsOut = batchRouter.removeLiquidityProportionalFromERC4626Pool(
            partialErc4626Pool,
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );
        uint256[] memory wrappedAmountsOut = new uint256[](2);
        wrappedAmountsOut[partialWaDaiIdx] = waDAI.convertToShares(underlyingAmountsOut[partialWaDaiIdx]);
        // Wrapped and underlying treated as the same, because USDC is not a wrapped token.
        wrappedAmountsOut[partialUsdcIdx] = underlyingAmountsOut[partialUsdcIdx];

        for (uint256 i = 0; i < underlyingAmountsOut.length; i++) {
            assertApproxEqAbs(
                wrappedAmountsOut[i],
                expectedAmountsOut[i],
                MAX_ERROR,
                "wrappedAmountsOut should match expected"
            );
        }

        {
            uint256 afterUSDCBalance = usdc.balanceOf(bob);
            assertEq(
                beforeUSDCBalance,
                afterUSDCBalance - underlyingAmountsOut[partialUsdcIdx],
                "Bob: wrong USDC balance"
            );
        }
        {
            uint256 afterDAIBalance = dai.balanceOf(bob);
            assertEq(
                beforeDAIBalance,
                afterDAIBalance - underlyingAmountsOut[partialWaDaiIdx],
                "Bob: wrong DAI balance"
            );
        }
        {
            (uint256 afterWaDAIBufferBalanceUnderlying, uint256 afterWaDAIBufferBalanceWrapped) = vault
                .getBufferBalance(waDAI);
            assertApproxEqAbs(
                beforeWaDAIBufferBalanceWrapped,
                afterWaDAIBufferBalanceWrapped - wrappedAmountsOut[partialWaDaiIdx],
                MAX_ERROR,
                "Vault: wrong waDAI wrapped buffer balance"
            );
            assertApproxEqAbs(
                afterWaDAIBufferBalanceUnderlying,
                beforeWaDAIBufferBalanceUnderlying - underlyingAmountsOut[partialWaDaiIdx],
                MAX_ERROR,
                "Vault: wrong waDAI underlying buffer balance"
            );
        }
        {
            (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(partialErc4626Pool));
            assertApproxEqAbs(
                lastBalancesLiveScaled18[partialWaDaiIdx],
                erc4626PoolInitialAmount - underlyingAmountsOut[partialWaDaiIdx],
                MAX_ERROR,
                "Partial ERC4626 Pool: wrong waDAI balance"
            );
            assertApproxEqAbs(
                lastBalancesLiveScaled18[partialUsdcIdx],
                erc4626PoolInitialAmount - underlyingAmountsOut[partialUsdcIdx],
                MAX_ERROR,
                "Partial ERC4626 Pool: wrong waUSDC balance"
            );
        }

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
        minAmountsOut[waUsdcIdx] = waUSDC.convertToAssets(expectedAmountsOut[waUsdcIdx]);
        minAmountsOut[waDaiIdx] = waDAI.convertToAssets(expectedAmountsOut[waDaiIdx]);

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
            // Real operation and preview may have a difference.
            assertApproxEqAbs(
                queryUnderlyingAmountsOut[i],
                actualUnderlyingAmountsOut[i],
                5,
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
        minAmountsOut[partialWaDaiIdx] = waDAI.convertToAssets(expectedAmountsOut[partialWaDaiIdx]);

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

        for (uint256 i = 0; i < queryUnderlyingAmountsOut.length; i++) {
            // Real operation and preview may have a difference.
            assertApproxEqAbs(
                queryUnderlyingAmountsOut[i],
                actualUnderlyingAmountsOut[i],
                5,
                "Query and actual underlying amounts out do not match"
            );
        }
    }

    function testInvalidUnderlyingToken() public {
        vm.expectRevert(IVaultErrors.InvalidUnderlyingToken.selector);
        vm.prank(lp);
        router.initializeBuffer(waInvalid, bufferInitialAmount, bufferInitialAmount);
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
}
