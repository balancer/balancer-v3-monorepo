// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { BaseVaultTest } from "./BaseVaultTest.sol";

abstract contract BaseExtremeAmountsTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal startBPTAmount;
    uint256 internal maxBPTAmount;
    uint256 internal maxAmountIn = MAX_UINT128 - poolInitAmount;
    uint256 internal maxInvariantChangePercentOfAmount = 30;

    //#region Test setup
    function setUp() public virtual override {
        BaseVaultTest.setUp();

        maxBPTAmount = IBasePool(pool).computeInvariant([MAX_UINT128, MAX_UINT128].toMemoryArray());
        if (maxBPTAmount > MAX_UINT128) {
            maxBPTAmount = MAX_UINT128;
        }

        startBPTAmount = IBasePool(pool).computeInvariant([poolInitAmount, poolInitAmount].toMemoryArray());
        maxBPTAmount -= startBPTAmount;
    }

    //#endregion

    //#region Tests
    function testAddAndRemoveLiquidityProportional_Fuzz(uint256 exactBPTAmount) public {
        vault.forceUnlock();
        exactBPTAmount = bound(exactBPTAmount, 100e6 * 1e18, maxBPTAmount);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [maxAmountIn, maxAmountIn].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        assertEq(bptAmountOut, exactBPTAmount, "BPT amount out should be equal to exactBPTAmount");

        (uint256 totalBPTAmountIn, uint256[] memory totalAmountsOut, uint256 diff) = _removeExactInPartial(
            bptAmountOut,
            new uint256[](2),
            RemoveLiquidityKind.PROPORTIONAL
        );

        assertEq(totalBPTAmountIn + diff, bptAmountOut, "BPT amount in should be equal to BPT amount out");
        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertLe(totalAmountsOut[i], amountsIn[i], "Amounts out should be less than amounts in");
        }
    }

    function testAddUnbalancedAndRemoveLiquidityProportional_Fuzz(uint256[2] memory maxAmountsInRaw) public {
        vault.forceUnlock();

        (uint256 newMaxAmountIn, ) = _addLiquidityProportionalAndUpdateMaxAmounts();

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = bound(maxAmountsInRaw[0], 100e6 * 1e18, newMaxAmountIn);
        exactAmountsIn[1] = bound(maxAmountsInRaw[1], 100e6 * 1e18, newMaxAmountIn);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: exactAmountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.UNBALANCED,
                userData: bytes("")
            })
        );

        console.log("bptAmountOut: %d", bptAmountOut);
        console.log("amountsIn 0: %d", amountsIn[0]);
        console.log("amountsIn 1: %d", amountsIn[1]);
        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertEq(amountsIn[i], exactAmountsIn[i], "AmountsIn should be equal to exactAmountsIn");
        }

        (uint256 totalBPTAmountIn, uint256[] memory totalAmountsOut, ) = _removeExactInPartial(
            bptAmountOut,
            new uint256[](2),
            RemoveLiquidityKind.PROPORTIONAL
        );

        console.log("totalBPTAmountIn: %d", totalBPTAmountIn);
        assertEq(totalBPTAmountIn, bptAmountOut, "BPT amount in should be equal to BPT amount out");

        console.log("totalAmountsOut 0: %d", totalAmountsOut[0]);
        console.log("totalAmountsOut 1: %d", totalAmountsOut[1]);

        console.log("totalAmountsOut 0 > amountsIn 0: ", totalAmountsOut[0] > amountsIn[0]);
        console.log("totalAmountsOut 1 > amountsIn 1: ", totalAmountsOut[1] > amountsIn[1]);

        if (totalAmountsOut[0] > amountsIn[0]) {
            assertLt(totalAmountsOut[1], amountsIn[1], "Total amount out should be less than amount in");
        } else if (totalAmountsOut[0] == amountsIn[0]) {
            assertLe(totalAmountsOut[1], amountsIn[1], "Total amount out should be less or equal to amount in");
        }
    }

    function testAddProportionalAndRemoveLiquidityExactIn_Fuzz(uint256 exactBPTAmount) public {
        vault.forceUnlock();
        exactBPTAmount = bound(exactBPTAmount, 100e6 * 1e18, maxBPTAmount);

        (, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [maxAmountIn, maxAmountIn].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        assertEq(bptAmountOut, exactBPTAmount, "BPT amount out should be equal to exactBPTAmount");

        uint256 removeAmount = exactBPTAmount / 10;
        uint256 snapshot = vm.snapshot();
        (uint256 bptAmountInProportional, uint256[] memory amountsOutProportional, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: removeAmount * 2,
                minAmountsOut: [0, uint256(1)].toMemoryArray(),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );
        vm.revertTo(snapshot);

        assertEq(
            bptAmountInProportional,
            removeAmount * 2,
            "BPT amount in for proportional should be equal to removeAmount * 2"
        );

        (uint256 bptAmountInTokenOne, uint256[] memory amountsOutTokenOne, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: removeAmount,
                minAmountsOut: [0, uint256(1)].toMemoryArray(),
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                userData: bytes("")
            })
        );
        assertEq(removeAmount, bptAmountInTokenOne, "BPT amount in for token one should be equal to removeAmount");

        (uint256 bptAmountInTokenTwo, , ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: removeAmount,
                minAmountsOut: [uint256(1), 0].toMemoryArray(),
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                userData: bytes("")
            })
        );
        assertEq(removeAmount, bptAmountInTokenTwo, "BPT amount in for token two should be equal to removeAmount");

        assertLe(
            amountsOutTokenOne[1],
            amountsOutProportional[1],
            "Amounts out for token one should be greater or equal to amounts in"
        );
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn_Fuzz(uint256 exactBPTAmount) public {
        vault.forceUnlock();

        (uint256 newMaxAmountIn, uint256 newMaxBPTAmount) = _addLiquidityProportionalAndUpdateMaxAmounts();

        exactBPTAmount = bound(exactBPTAmount, 100e6 * 1e18, newMaxBPTAmount);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [0, newMaxAmountIn].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: bytes("")
            })
        );
        assertEq(bptAmountOut, exactBPTAmount, "BPT amount out should be equal to exactBPTAmount");

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = _removeExactInPartial(
            bptAmountOut,
            [0, uint256(1)].toMemoryArray(),
            RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN
        );

        assertEq(bptAmountIn, bptAmountOut, "BPT amount in should be equal to BPT amount out");
        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertLe(amountsOut[i], amountsIn[i], "Amounts out should be less than amounts in");
        }
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut_Fuzz(uint256 exactBPTAmount) public {
        vault.forceUnlock();

        (uint256 newMaxAmountIn, uint256 newMaxBPTAmount) = _addLiquidityProportionalAndUpdateMaxAmounts();
        exactBPTAmount = bound(exactBPTAmount, 100e6 * 1e18, newMaxBPTAmount);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [0, newMaxAmountIn].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: bytes("")
            })
        );

        assertEq(bptAmountOut, exactBPTAmount, "BPT amount out should be equal to exactBPTAmount");

        uint256 totalBPTAmountIn = 0;
        uint256[] memory totalAmountsOut = new uint256[](2);

        (uint256[] memory splitAmounts, ) = _splitAmount(amountsIn[1]);
        for (uint256 i = 0; i < splitAmounts.length; i++) {
            try
                vault.removeLiquidity(
                    RemoveLiquidityParams({
                        pool: pool,
                        from: address(this),
                        maxBptAmountIn: MAX_UINT128,
                        minAmountsOut: [0, splitAmounts[i]].toMemoryArray(),
                        kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                        userData: bytes("")
                    })
                )
            returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory) {
                totalBPTAmountIn += bptAmountIn;
                totalAmountsOut[0] += amountsOut[0];
                totalAmountsOut[1] += amountsOut[1];
            } catch (bytes memory reason) {
                (bytes4 selector, bytes memory reasonWithoutSelector) = _removeSelectorFromErrorReason(reason);
                (, uint256 balance, uint256 needed) = abi.decode(reasonWithoutSelector, (address, uint256, uint256));

                assertEq(
                    selector,
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    "Selector should be ERC20InsufficientBalance"
                );

                uint256 restBPTAmount = bptAmountOut - totalBPTAmountIn;
                assertGe(needed, restBPTAmount, "Needed should be greater or equal to restBPTAmount");
                assertEq(balance, restBPTAmount, "Balance should be equal to restBPTAmount");
                return;
            }
        }
        console.log("balance before 3: %d", IERC20(pool).balanceOf(address(this)));
        assertEq(totalBPTAmountIn, bptAmountOut, "BPT amount in should be equal to BPT amount out");
        for (uint256 i = 0; i < amountsIn.length; i++) {
            assertEq(totalAmountsOut[i], amountsIn[i], "Amounts out should be equal to amounts in");
        }
    }

    function testSwap(uint256 exactBPTAmount, uint256 swapAmount) public {
        vault.forceUnlock();

        (uint256 newMaxAmountIn, uint256 newMaxBPTAmount) = _addLiquidityProportionalAndUpdateMaxAmounts();
        exactBPTAmount = bound(exactBPTAmount, 100e6 * 1e18, newMaxBPTAmount);

        (uint256[] memory amountsIn, , ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [newMaxAmountIn, newMaxAmountIn].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        swapAmount = bound(swapAmount, amountsIn[0] / 10, amountsIn[0]);
        (, uint256 amountIn, uint256 amountOut) = vault.swap(
            SwapParams({
                pool: pool,
                kind: SwapKind.EXACT_IN,
                tokenIn: tokens[0],
                tokenOut: tokens[1],
                amountGivenRaw: swapAmount,
                limitRaw: 0,
                userData: bytes("")
            })
        );

        assertEq(amountIn, swapAmount, "Amount in should be equal to swapAmount");

        (, uint256 amountInReturn, uint256 amountOutReturn) = vault.swap(
            SwapParams({
                pool: pool,
                kind: SwapKind.EXACT_IN,
                tokenIn: tokens[1],
                tokenOut: tokens[0],
                amountGivenRaw: amountOut,
                limitRaw: 0,
                userData: bytes("")
            })
        );

        assertEq(amountInReturn, amountOut, "Amount in should be equal to amountOut");
        assertLe(amountOutReturn, amountIn, "Amount out should be equal or less amountIn");
    }
    //#endregion

    //#region Internal functions

    function _addLiquidityProportionalAndUpdateMaxAmounts()
        internal
        returns (uint256 newMaxAmountIn, uint256 newMaxBPTAmount)
    {
        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: lp,
                maxAmountsIn: [maxAmountIn, maxAmountIn].toMemoryArray(),
                minBptAmountOut: maxBPTAmount / 2,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        newMaxAmountIn = ((maxAmountIn + amountsIn[1]) * maxInvariantChangePercentOfAmount) / 100;

        uint currentBPTAmount = startBPTAmount + bptAmountOut;
        newMaxBPTAmount = (currentBPTAmount * maxInvariantChangePercentOfAmount) / 100;
    }
    function _removeSelectorFromErrorReason(
        bytes memory reason
    ) internal pure returns (bytes4 selector, bytes memory res) {
        res = new bytes(reason.length - 4);
        for (uint256 i = 0; i < 4; i++) {
            selector |= bytes4(reason[i]) >> (i * 8);
        }
        for (uint256 i = 4; i < reason.length; i++) {
            res[i - 4] = reason[i];
        }
    }

    function _splitAmount(uint256 amount) internal view returns (uint256[] memory splitAmounts, uint256 diff) {
        uint256 splitAmount = (amount * maxInvariantChangePercentOfAmount) / 100;
        uint256 count = amount / splitAmount;
        uint256 restAmount = amount % splitAmount;

        if (restAmount >= 0) {
            if (restAmount >= MINIMUM_TRADE_AMOUNT) {
                count++;
            } else {
                diff = restAmount;
            }
        }

        splitAmounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            if (i == count - 1 && restAmount >= MINIMUM_TRADE_AMOUNT) {
                splitAmounts[i] = restAmount;
            } else {
                splitAmounts[i] = splitAmount;
            }
        }
    }

    function _removeExactInPartial(
        uint256 bptAmountOut,
        uint256[] memory minAmountsOut,
        RemoveLiquidityKind kind
    ) internal returns (uint256 totalBPTAmountIn, uint256[] memory totalAmountsOut, uint256 diff) {
        totalAmountsOut = new uint256[](2);

        uint256[] memory splitAmounts;
        (splitAmounts, diff) = _splitAmount(bptAmountOut);
        for (uint256 i = 0; i < splitAmounts.length; i++) {
            (uint256 bptAmountIn, uint256[] memory amountsOut, ) = vault.removeLiquidity(
                RemoveLiquidityParams({
                    pool: pool,
                    from: address(this),
                    maxBptAmountIn: splitAmounts[i],
                    minAmountsOut: minAmountsOut,
                    kind: kind,
                    userData: bytes("")
                })
            );

            totalBPTAmountIn += bptAmountIn;
            totalAmountsOut[0] += amountsOut[0];
            totalAmountsOut[1] += amountsOut[1];
        }
    }

    //#endregion
}
