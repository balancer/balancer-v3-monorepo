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

    uint256 internal minAmount = 1e6 * 1e18;

    uint256 internal initBPTAmount;
    uint256 internal maxBPTAmount;
    uint256 internal maxAdditionalBPTAmount;
    uint256 internal maxAdditionalAmountIn;
    uint256 internal minInvariantRatio;
    uint256 internal maxInvariantRatio;

    //#region Test setup
    function setUp() public virtual override {
        BaseVaultTest.setUp();

        initBPTAmount = IBasePool(pool).computeInvariant([poolInitAmount, poolInitAmount].toMemoryArray());
        maxBPTAmount = IBasePool(pool).computeInvariant([MAX_UINT128, MAX_UINT128].toMemoryArray());
        if (maxBPTAmount > MAX_UINT128) {
            maxBPTAmount = MAX_UINT128;
        }

        maxAdditionalBPTAmount = maxBPTAmount - initBPTAmount;
        maxAdditionalAmountIn = MAX_UINT128 - poolInitAmount;
        minInvariantRatio = IBasePool(pool).getMinimumInvariantRatio();
        maxInvariantRatio = IBasePool(pool).getMaximumInvariantRatio();
    }

    //#endregion

    //#region Tests
    function testAddAndRemoveLiquidityProportional_Fuzz(uint256 exactBPTAmount) public {
        vault.forceUnlock();
        exactBPTAmount = bound(exactBPTAmount, minAmount, maxAdditionalBPTAmount);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [maxAdditionalAmountIn, maxAdditionalAmountIn].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        assertEq(bptAmountOut, exactBPTAmount, "bptAmountOut should be equal to exactBPTAmount");

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: exactBPTAmount,
                minAmountsOut: [0, uint256(1)].toMemoryArray(),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        assertEq(bptAmountIn, bptAmountOut, "bptAmountIn should be equal to bptAmountOut");
        assertLe(amountsOut[0], amountsIn[0], "amountsOut[0] should be less or equal to amountsIn[0]");
        assertLe(amountsOut[1], amountsIn[1], "amountsOut[1] should be less or equal to amountsIn[1]");
    }

    function testAddUnbalancedAndRemoveLiquidityProportional_Fuzz(
        uint256[2] memory maxAmountsInRaw,
        uint256 addLiquidityProportionalAmount
    ) public {
        vault.forceUnlock();

        addLiquidityProportionalAmount = bound(addLiquidityProportionalAmount, minAmount, maxAdditionalBPTAmount / 2);
        (uint256[] memory amountsIn, , ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: lp,
                maxAmountsIn: [maxAdditionalAmountIn, maxAdditionalAmountIn].toMemoryArray(),
                minBptAmountOut: addLiquidityProportionalAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        uint256[] memory maxAmountsIn = new uint256[](2);
        for (uint256 i = 0; i < maxAmountsIn.length; i++) {
            uint256 currentBalance = amountsIn[i] + poolInitAmount;
            uint256 restMaxAdditionalAmountIn = maxAdditionalAmountIn - amountsIn[i];
            unchecked {
                maxAmountsIn[i] = ((currentBalance * maxInvariantRatio) / 1e18);
            }

            if (maxAmountsIn[i] > restMaxAdditionalAmountIn) {
                maxAmountsIn[i] = restMaxAdditionalAmountIn;
            } else if (maxAmountsIn[i] < currentBalance) {
                maxAmountsIn[i] = currentBalance;
            }
        }

        uint256 bptAmountOut;
        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = bound(maxAmountsInRaw[0], minAmount, maxAmountsIn[0] / 2);
        exactAmountsIn[1] = bound(maxAmountsInRaw[1], minAmount, maxAmountsIn[1] / 2);
        (amountsIn, bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: exactAmountsIn,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.UNBALANCED,
                userData: bytes("")
            })
        );

        assertEq(amountsIn[0], exactAmountsIn[0], "amountsIn[0] should be equal to exactAmountsIn[0]");
        assertEq(amountsIn[1], exactAmountsIn[1], "amountsIn[1] should be equal to exactAmountsIn[1]");

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: bptAmountOut,
                minAmountsOut: new uint256[](2),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );
        assertEq(bptAmountIn, bptAmountOut, "bptAmountIn should be equal to bptAmountOut");

        // if amountsOut[0] more then amountsIn[0], then amountsOut[1] should be less than amountsIn[1] otherwise user gets free tokens
        // if amountsOut[0] equal to amountsIn[0], then amountsOut[1] should be less or equal to amountsIn[1] otherwise user gets free tokens
        // if amountsOut[0] less then amountsIn[0], we can't check anything because user doesn't get free tokens
        if (amountsOut[0] > amountsIn[0]) {
            assertLt(amountsOut[1], amountsIn[1], "amountsOut[1] should be less than amountsIn[1]");
        } else if (amountsOut[0] == amountsIn[0]) {
            assertLe(amountsOut[1], amountsIn[1], "amountsOut[1] should be less or equal to amountsIn[1]");
        }
    }

    function testAddProportionalAndRemoveLiquidityExactIn_Fuzz(uint256 exactBPTAmount) public {
        vault.forceUnlock();
        exactBPTAmount = bound(exactBPTAmount, minAmount, maxAdditionalBPTAmount);

        (, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [maxAdditionalAmountIn, maxAdditionalAmountIn].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );
        assertEq(bptAmountOut, exactBPTAmount, "bptAmountOut should be equal to exactBPTAmount");

        // removeAmount is 2 times less than maxBPTAmount because we will do two different SINGLE_TOKEN_EXACT_IN removals
        uint256 removeAmount = ((exactBPTAmount * (1e18 - minInvariantRatio)) / 1e18) / 2;

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
            "bptAmountInProportional should be equal to removeAmount * 2"
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
        assertEq(removeAmount, bptAmountInTokenOne, "removeAmount should be equal to bptAmountInTokenOne");

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
        assertEq(removeAmount, bptAmountInTokenTwo, "bptAmountInTokenTwo should be equal to removeAmount");

        assertLe(
            amountsOutTokenOne[1],
            amountsOutProportional[1],
            "amountsOutTokenOne[1] should be less or equal to amountsOutProportional[1]"
        );
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn_Fuzz(uint256 addLiquidityProportionalAmount) public {
        vault.forceUnlock();

        addLiquidityProportionalAmount = bound(addLiquidityProportionalAmount, minAmount, maxAdditionalBPTAmount / 2);

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: lp,
                maxAmountsIn: [maxAdditionalAmountIn, maxAdditionalAmountIn].toMemoryArray(),
                minBptAmountOut: addLiquidityProportionalAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        uint256 exactBPTAmount = (((bptAmountOut + initBPTAmount) * (1e18 - minInvariantRatio)) / 1e18);
        (amountsIn, bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [0, maxAdditionalAmountIn - amountsIn[1]].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: bytes("")
            })
        );
        assertEq(bptAmountOut, exactBPTAmount, "bptAmountOut should be equal to exactBPTAmount");

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: bptAmountOut,
                minAmountsOut: [0, uint256(1)].toMemoryArray(),
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                userData: bytes("")
            })
        );

        assertEq(bptAmountIn, bptAmountOut, "bptAmountIn should be equal to bptAmountOut");
        assertLe(amountsOut[0], amountsIn[0], "amountsOut[0] should be less or equal to amountsIn[0]");
        assertLe(amountsOut[1], amountsIn[1], "amountsOut[1] should be less or equal to amountsIn[1]");
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut_Fuzz(uint256 addLiquidityProportionalAmount) public {
        vault.forceUnlock();

        addLiquidityProportionalAmount = bound(addLiquidityProportionalAmount, minAmount, maxAdditionalBPTAmount / 2);
        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: lp,
                maxAmountsIn: [maxAdditionalAmountIn, maxAdditionalAmountIn].toMemoryArray(),
                minBptAmountOut: addLiquidityProportionalAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        uint256 exactBPTAmount = (((bptAmountOut + initBPTAmount) * (1e18 - minInvariantRatio)) / 1e18);
        (amountsIn, bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [0, maxAdditionalAmountIn - amountsIn[1]].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: bytes("")
            })
        );

        assertEq(bptAmountOut, exactBPTAmount, "bpAmountOut should be equal to exactBPTAmount");

        try
            vault.removeLiquidity(
                RemoveLiquidityParams({
                    pool: pool,
                    from: address(this),
                    maxBptAmountIn: MAX_UINT128,
                    minAmountsOut: [0, amountsIn[1]].toMemoryArray(),
                    kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                    userData: bytes("")
                })
            )
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory) {
            assertEq(bptAmountIn, bptAmountOut, "bptAmountIn should be equal to bptAmountOut");
            assertEq(amountsOut[0], amountsIn[0], "amountsOut[0] should be equal to amountsIn[0]");
            assertEq(amountsOut[1], amountsIn[1], "amountsOut[1] should be equal to amountsIn[1]");
        } catch (bytes memory reason) {
            (bytes4 selector, bytes memory reasonWithoutSelector) = _removeSelectorFromErrorReason(reason);
            (, uint256 balance, uint256 needed) = abi.decode(reasonWithoutSelector, (address, uint256, uint256));

            assertEq(
                selector,
                IERC20Errors.ERC20InsufficientBalance.selector,
                "Selector should be ERC20InsufficientBalance"
            );

            assertGe(needed, bptAmountOut, "needed should be greater or equal to bptAmountOut");
            assertEq(balance, bptAmountOut, "balance should be equal to bptAmountOut");
            return;
        }
    }

    function testSwap(uint256 swapAmount, uint256 addLiquidityProportionalAmount) public {
        vault.forceUnlock();

        addLiquidityProportionalAmount = bound(addLiquidityProportionalAmount, minAmount, maxAdditionalBPTAmount / 2);
        (uint256[] memory amountsIn, , ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: lp,
                maxAmountsIn: [maxAdditionalAmountIn, maxAdditionalAmountIn].toMemoryArray(),
                minBptAmountOut: addLiquidityProportionalAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );

        swapAmount = bound(swapAmount, amountsIn[0] / 10, amountsIn[0] / 5);
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

        assertEq(amountIn, swapAmount, "amountIn should be equal to swapAmount");

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

        assertEq(amountInReturn, amountOut, "amountInReturn should be equal to amountOut");
        assertLe(amountOutReturn, amountIn, "amountOutReturn should be less or equal to amountIn");
    }
    //#endregion

    //#region Internal functions
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
    //#endregion
}
