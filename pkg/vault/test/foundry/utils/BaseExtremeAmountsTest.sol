// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { BaseVaultTest } from "./BaseVaultTest.sol";

abstract contract BaseExtremeAmountsTest is BaseTest, BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for *;

    uint256 constant HUGE_INIT_AMOUNT = 1e8 * 1e18; // 100M

    uint256 internal minSwapFee;
    uint256 internal maxSwapFee;
    uint256 internal minAmount = 1e6 * 1e18;
    uint256 internal initBPTAmount;
    uint256 internal maxBPTAmount;
    uint256 internal maxAdditionalBPTAmount;
    uint256[] maxAdditionalAmountsIn;
    uint256[] initBalances;
    uint256 internal minInvariantRatio;
    uint256 internal maxInvariantRatio;

    //#region Test setup
    function setUp() public virtual override(BaseTest, BaseVaultTest) {
        // This function is empty because we don't want to call BaseVaultTest.setUp() before when we have Fuzz arguments
        BaseTest.setUp();
        _setUpBaseVaultTest();
    }

    function initPool() internal override {
        vm.startPrank(lp);
        _initPool(pool, initBalances, 0);
        vm.stopPrank();
    }

    function _manualSetUp(uint256[] memory balances, uint256 swapFee) internal {
        require(balances.length == 2, "Balances array should have length 2");
        initBalances = balances;

        console.log("balances[%d] %d", 0, balances[0]);
        console.log("balances[%d] %d", 1, balances[1]);

        usdc.mint(lp, MAX_UINT128);
        dai.mint(lp, MAX_UINT128);

        initPool();
        minSwapFee = IBasePool(pool).getMinimumSwapFeePercentage();
        maxSwapFee = IBasePool(pool).getMaximumSwapFeePercentage();

        console.log("first computeInvariant");
        initBPTAmount = IBasePool(pool).computeInvariant(balances, Rounding.ROUND_DOWN);

        console.log("second computeInvariant");
        maxBPTAmount = _initMaxBPTAmount();

        console.log("calculate max");
        console.log("maxBPTAmount", maxBPTAmount);
        console.log("initBPTAmount", initBPTAmount);

        maxAdditionalBPTAmount = maxBPTAmount - initBPTAmount;

        console.log("calculate max 2");
        maxAdditionalAmountsIn.push(MAX_UINT128 - balances[0]);
        maxAdditionalAmountsIn.push(MAX_UINT128 - balances[1]);

        minInvariantRatio = IBasePool(pool).getMinimumInvariantRatio();
        maxInvariantRatio = IBasePool(pool).getMaximumInvariantRatio();

        vault.manualSetAggregateSwapFeePercentage(pool, swapFee);

        console.log("end init");
    }

    function _initMaxBPTAmount() internal virtual returns (uint256) {
        return
            IBasePool(pool).computeInvariant([1e12 * 1e18, uint256(1e12 * 1e18)].toMemoryArray(), Rounding.ROUND_DOWN);
    }

    //#endregion

    // #region testAddAndRemoveLiquidityProportional
    function testAddAndRemoveLiquidityProportional_Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _manualSetUp(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        exactBPTAmount = bound(exactBPTAmount, minAmount, _calculateMaxBPTAmountForProportionalOperations());
        _testAddAndRemoveLiquidityProportional(exactBPTAmount);
    }

    function testAddAndRemoveLiquidityProportionalMaxBPTAmount_FuzzSwapFee(uint256 swapFee) public {
        _manualSetUp([poolInitAmount, poolInitAmount].toMemoryArray(), _boundSwapFee(swapFee));

        _testAddAndRemoveLiquidityProportional(_calculateMaxBPTAmountForProportionalOperations());
    }

    function testAddAndRemoveLiquidityProportional_FuzzBPTAmount(uint256 exactBPTAmount) public {
        _manualSetUp([poolInitAmount, poolInitAmount].toMemoryArray(), maxSwapFee / 2);

        exactBPTAmount = bound(exactBPTAmount, minAmount, _calculateMaxBPTAmountForProportionalOperations());
        _testAddAndRemoveLiquidityProportional(exactBPTAmount);
    }

    function _calculateMaxBPTAmountForProportionalOperations() private view returns (uint256) {
        return
            Math.min(
                Math.min(
                    (maxAdditionalAmountsIn[0] * initBPTAmount) / initBalances[0],
                    (maxAdditionalAmountsIn[1] * initBPTAmount) / initBalances[1]
                ),
                MAX_UINT256 / MAX_UINT128
            );
    }

    function _testAddAndRemoveLiquidityProportional(uint256 exactBPTAmount) private {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [maxAdditionalAmountsIn[0], maxAdditionalAmountsIn[1]].toMemoryArray(),
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
                minAmountsOut: [0, uint256(0)].toMemoryArray(),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );
        assertEq(bptAmountIn, bptAmountOut, "bptAmountIn should be equal to bptAmountOut");

        assertLe(amountsOut[0], amountsIn[0], "amountsOut[0] should be less or equal to amountsIn[0]");
        assertLe(amountsOut[1], amountsIn[1], "amountsOut[1] should be less or equal to amountsIn[1]");
    }

    // #endregion

    // #region testAddUnbalancedAndRemoveLiquidityProportional
    function testAddUnbalancedAndRemoveLiquidityProportional_Fuzz(
        uint256[2] memory amountsIn,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        swapFee = _boundSwapFee(swapFee);
        uint256[] memory balances = _boundBalances(balancesRaw);
        _manualSetUp(balances, swapFee);

        console.log("\n---------------");
        console.log("swapFee", swapFee);
        uint256[] memory amounts = _calculateExactAmountsIn(amountsIn);
        console.log("amountsIn[%d] %d", 0, amounts[0]);
        console.log("amountsIn[%d] %d", 1, amounts[1]);

        console.log("balances[%d] %d", 0, balances[0]);
        console.log("balances[%d] %d", 1, balances[1]);
        console.log("\n---------------");

        _testAddUnbalancedAndRemoveLiquidityProportional(amounts);
    }

    function testAddUnbalancedAndRemoveLiquidityProportional_FuzzAmountsIn(uint256[2] memory amountsIn) public {
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        _testAddUnbalancedAndRemoveLiquidityProportional(_calculateExactAmountsIn(amountsIn));
    }

    function testAddUnbalancedAndRemoveLiquidityProportional_FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = minAmount;
        exactAmountsIn[1] = minAmount;

        _testAddUnbalancedAndRemoveLiquidityProportional(exactAmountsIn);
    }

    function _calculateExactAmountsIn(uint256[2] memory amountsIn) private view returns (uint256[] memory) {
        uint256[] memory exactAmountsIn = new uint256[](2);
        uint256[] memory maxAmountsIn = _calculateMaxAmountIn();
        console.log("maxAmountsIn[%d] %d", 0, maxAmountsIn[0] < minAmount);
        console.log("maxAmountsIn[%d] %d", 1, maxAmountsIn[1] < minAmount);
        exactAmountsIn[0] = bound(amountsIn[0], initBalances[0], maxAmountsIn[0]);
        exactAmountsIn[1] = bound(amountsIn[1], initBalances[1], maxAmountsIn[1]);

        return exactAmountsIn;
    }

    function _calculateMaxAmountIn() private view returns (uint256[] memory) {
        // get max amount inside invariant ratio
        uint256[] memory maxAmountsIn = new uint256[](2);
        for (uint256 i = 0; i < maxAmountsIn.length; i++) {
            // if we send more then this amount, then we will receive an overflow exception
            uint256 maxAmount = initBalances[i] * 100;

            // if invariant ratio is really high, then we don't need to receive an exception
            unchecked {
                maxAmountsIn[i] = ((initBalances[i] * maxInvariantRatio) / 1e18);
            }
            if (maxAmountsIn[i] > maxAmount || maxAmountsIn[i] < initBalances[i]) {
                maxAmountsIn[i] = maxAmount;
            }

            maxAmountsIn[i] = maxAmountsIn[i] - initBalances[i];
        }

        return maxAmountsIn;
    }

    function _testAddUnbalancedAndRemoveLiquidityProportional(uint256[] memory exactAmountsIn) private {
        vault.forceUnlock();

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
    // #endregion

    // #region testAddProportionalAndRemoveLiquidityExactIn
    function testAddProportionalAndRemoveLiquidityExactInTTT_Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _manualSetUp(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        uint256 maxAmount = _calculateMaxBPTAmountForSingleTokenOperations();
        exactBPTAmount = bound(exactBPTAmount, maxAmount / 100, maxAmount);
        console.log("exactBPTAmount %d", exactBPTAmount);
        _testAddProportionalAndRemoveLiquidityExactIn(exactBPTAmount);
    }

    function testAddProportionalAndRemoveLiquidityExactIn_FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testAddProportionalAndRemoveLiquidityExactIn(minAmount);
    }

    function testAddProportionalAndRemoveLiquidityExactIn_FuzzBPTAmount(uint256 exactBPTAmount) public {
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        exactBPTAmount = bound(exactBPTAmount, minAmount, _calculateMaxBPTAmountForSingleTokenOperations());
        _testAddProportionalAndRemoveLiquidityExactIn(exactBPTAmount);
    }

    function _testAddProportionalAndRemoveLiquidityExactIn(uint256 exactBPTAmount) private {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [maxAdditionalAmountsIn[0], maxAdditionalAmountsIn[1]].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );
        assertEq(bptAmountOut, exactBPTAmount, "bptAmountOut should be equal to exactBPTAmount");

        uint removePerOperation = exactBPTAmount / 2;

        // first single token exact in removal
        (uint256 bptAmountInTokenOne, uint256[] memory amountsOutTokenOne, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: removePerOperation,
                minAmountsOut: [uint256(1), 0].toMemoryArray(),
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                userData: bytes("")
            })
        );
        assertEq(removePerOperation, bptAmountInTokenOne, "removePerOperation should be equal to bptAmountInTokenOne");

        // second single token exact in removal
        (uint256 bptAmountInTokenTwo, uint256[] memory amountsOutTokenTwo, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool,
                from: address(this),
                maxBptAmountIn: removePerOperation,
                minAmountsOut: [0, uint256(1)].toMemoryArray(),
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_IN,
                userData: bytes("")
            })
        );
        assertEq(removePerOperation, bptAmountInTokenTwo, "bptAmountInTokenTwo should be equal to removePerOperation");

        if (amountsOutTokenOne[0] > amountsIn[0]) {
            assertLt(amountsOutTokenTwo[1], amountsIn[1], "amountsOutTokenTwo[1] should be less than amountsIn[1]");
        } else if (amountsOutTokenOne[0] == amountsIn[0]) {
            assertLe(
                amountsOutTokenTwo[1],
                amountsIn[1],
                "amountsOutTokenTwo[1] should be less or equal to amountsIn[1]"
            );
        }
    }
    // #endregion

    // #region testAddLiquiditySingleTokenExactOutAndRemoveExactIn
    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn_Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _manualSetUp(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        uint256 maxAmount = _calculateMaxBPTAmountForSingleTokenOperations();
        exactBPTAmount = bound(exactBPTAmount, maxAmount / 100, maxAmount);
        _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(exactBPTAmount);
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn_FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(minAmount);
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn_FuzzBPTAmount(uint256 exactBPTAmount) public {
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        exactBPTAmount = bound(exactBPTAmount, minAmount, _calculateMaxBPTAmountForSingleTokenOperations());
        _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(exactBPTAmount);
    }

    function _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(uint256 exactBPTAmount) private {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [0, maxAdditionalAmountsIn[1]].toMemoryArray(),
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

    // #endregion

    // #region testAddLiquiditySingleTokenExactOutAndRemoveExactOut
    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut_Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _manualSetUp(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        uint256 maxAmount = _calculateMaxBPTAmountForSingleTokenOperations();
        exactBPTAmount = bound(exactBPTAmount, maxAmount / 100, maxAmount);
        _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(exactBPTAmount);
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut_FuzzBPTAmount(uint256 exactBPTAmount) public {
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        uint256 maxAmount = _calculateMaxBPTAmountForSingleTokenOperations();
        exactBPTAmount = bound(exactBPTAmount, maxAmount / 100, maxAmount);
        _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(exactBPTAmount);
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut_FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(minAmount);
    }

    function _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(uint256 exactBPTAmount) private {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this),
                maxAmountsIn: [0, maxAdditionalAmountsIn[1]].toMemoryArray(),
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
    // #endregion

    // #region testSwap
    function testSwap_Fuzz(uint256 swapAmount, uint256 swapFee, uint256[2] memory balancesRaw) public {
        _manualSetUp(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        _testSwap(_boundSwapAmount(swapAmount));
    }

    function testSwap_FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testSwap(minAmount);
    }

    function testSwap_FuzzSwapAmount(uint256 swapAmount) public {
        _manualSetUp([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        _testSwap(_boundSwapAmount(swapAmount));
    }

    function _boundSwapAmount(uint256 swapAmount) private view returns (uint256) {
        return
            bound(
                swapAmount,
                Math.min(initBalances[0], initBalances[1]) / 10,
                Math.min(initBalances[0], initBalances[1]) / 5
            );
    }

    function _testSwap(uint256 swapAmount) private {
        vault.forceUnlock();

        console.log("swapAmount %d", swapAmount);

        (, uint256 amountIn, uint256 amountOut) = vault.swap(
            VaultSwapParams({
                pool: pool,
                kind: SwapKind.EXACT_IN,
                tokenIn: tokens[0],
                tokenOut: tokens[1],
                amountGivenRaw: swapAmount,
                limitRaw: 0,
                userData: bytes("")
            })
        );
        console.log("amountIn %d", amountIn);
        console.log("amountOut %d", amountOut);
        assertEq(amountIn, swapAmount, "amountIn should be equal to swapAmount");

        (, uint256 amountInReturn, uint256 amountOutReturn) = vault.swap(
            VaultSwapParams({
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
    // #endregion

    //#region Internal functions
    function _boundBalances(uint256[2] memory balancesRaw) private pure returns (uint256[] memory balances) {
        balances = new uint256[](2);
        balances[0] = bound(balancesRaw[0], 1e6 * 1e18, 1e12 * 1e18);
        balances[1] = bound(balancesRaw[1], balances[0] / 1000, 1e12 * 1e18);
    }

    function _boundSwapFee(uint256 swapFee) private view returns (uint256) {
        return bound(swapFee, minSwapFee, maxSwapFee);
    }

    function _calculateMaxBPTAmountForSingleTokenOperations() private view returns (uint256) {
        return ((initBPTAmount * (1e18 - minInvariantRatio)) / 1e18);
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
    //#endregion
}
