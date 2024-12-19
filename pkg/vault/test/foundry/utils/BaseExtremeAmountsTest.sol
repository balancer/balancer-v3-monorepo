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

    uint256 constant HUGE_INIT_AMOUNT = 1e8 * 1e18;
    uint256 constant MIN_AMOUNT = 1e3 * 1e18;
    uint256 constant MIN_BALANCE = 1e6 * 1e18;
    uint256 constant MAX_BALANCE = 1e12 * 1e18;

    uint256 internal minSwapFee;
    uint256 internal maxSwapFee;

    uint256 internal minInvariantRatio;
    uint256 internal maxInvariantRatio;

    uint256 internal initBPTAmount;
    uint256 internal maxBPTAmount;
    uint256 internal maxAdditionalBPTAmount;

    uint256[] maxAdditionalAmountsIn;
    uint256[] initBalances;

    // Test setup
    function setUp() public virtual override(BaseTest, BaseVaultTest) {
        BaseVaultTest.setUp();
    }

    function initPool() internal override {
        vm.startPrank(lp);
        _initPool(pool, initBalances, 0);
        vm.stopPrank();
    }

    function _setUpVariables(uint256[] memory balances, uint256 swapFee) internal {
        require(balances.length == 2, "Balances array should have length 2");
        initBalances = balances;

        usdc.mint(lp, MAX_UINT128);
        dai.mint(lp, MAX_UINT128);

        initPool();
        minSwapFee = IBasePool(pool()).getMinimumSwapFeePercentage();
        maxSwapFee = IBasePool(pool()).getMaximumSwapFeePercentage();

        initBPTAmount = IBasePool(pool()).computeInvariant(balances, Rounding.ROUND_DOWN);
        maxBPTAmount = _initMaxBPTAmount();
        maxAdditionalBPTAmount = maxBPTAmount - initBPTAmount;

        maxAdditionalAmountsIn.push(MAX_UINT128 - balances[0]);
        maxAdditionalAmountsIn.push(MAX_UINT128 - balances[1]);

        minInvariantRatio = IBasePool(pool()).getMinimumInvariantRatio();
        maxInvariantRatio = IBasePool(pool()).getMaximumInvariantRatio();

        vault.manualSetAggregateSwapFeePercentage(pool, swapFee);
    }

    function _initMaxBPTAmount() internal virtual returns (uint256) {
        return IBasePool(pool()).computeInvariant([MAX_BALANCE, MAX_BALANCE].toMemoryArray(), Rounding.ROUND_DOWN);
    }

    modifier checkInvariant() {
        (, , uint256[] memory poolBalancesBefore, ) = vault.getPoolTokenInfo(pool);
        uint256 invariantBefore = IBasePool(pool()).computeInvariant(poolBalancesBefore, Rounding.ROUND_UP);
        _;

        (, , uint256[] memory poolBalancesAfter, ) = vault.getPoolTokenInfo(pool);
        uint256 invariantAfter = IBasePool(pool()).computeInvariant(poolBalancesAfter, Rounding.ROUND_UP);

        assertGe(invariantAfter, invariantBefore, "InvariantAfter should be greater or equal to invariantBefore");
    }

    // testAddAndRemoveLiquidityProportional
    function testAddAndRemoveLiquidityProportional__Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _setUpVariables(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        _testAddAndRemoveLiquidityProportional(_boundExactBPTAmount(exactBPTAmount));
    }

    function testAddAndRemoveLiquidityProportionalMaxBPTAmount__FuzzSwapFee(uint256 swapFee) public {
        _setUpVariables([poolInitAmount(), poolInitAmount()].toMemoryArray(), _boundSwapFee(swapFee));

        _testAddAndRemoveLiquidityProportional(_calculateMaxBPTAmountForProportionalOperations());
    }

    function testAddAndRemoveLiquidityProportional__FuzzBPTAmount(uint256 exactBPTAmount) public {
        _setUpVariables([poolInitAmount(), poolInitAmount()].toMemoryArray(), maxSwapFee / 2);

        _testAddAndRemoveLiquidityProportional(_boundExactBPTAmount(exactBPTAmount));
    }

    // this function compute max possible BPT amount for proportional operations based on the current pool state
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

    function _boundExactBPTAmount(uint256 exactBPTAmount) private view returns (uint256) {
        return bound(exactBPTAmount, MIN_AMOUNT, _calculateMaxBPTAmountForProportionalOperations());
    }

    function _testAddAndRemoveLiquidityProportional(uint256 exactBPTAmount) private checkInvariant {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool(),
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
                pool: pool(),
                from: address(this),
                maxBptAmountIn: exactBPTAmount,
                minAmountsOut: [0, uint256(0)].toMemoryArray(),
                kind: RemoveLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );
        // User has no BPT after the operations
        assertEq(bptAmountIn, bptAmountOut, "bptAmountIn should be equal to bptAmountOut");

        // For every token, user is at a loss or even; no value is extracted from the pool.
        assertLe(amountsOut[0], amountsIn[0], "amountsOut[0] should be less or equal to amountsIn[0]");
        assertLe(amountsOut[1], amountsIn[1], "amountsOut[1] should be less or equal to amountsIn[1]");
    }

    // testAddUnbalancedAndRemoveLiquidityProportional
    function testAddUnbalancedAndRemoveLiquidityProportional__Fuzz(
        uint256[2] memory amountsIn,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _setUpVariables(_boundBalances(balancesRaw), _boundSwapFee(swapFee));
        _testAddUnbalancedAndRemoveLiquidityProportional(_calculateExactAmountsIn(amountsIn));
    }

    function testAddUnbalancedAndRemoveLiquidityProportional__FuzzAmountsIn(uint256[2] memory amountsIn) public {
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);
        _testAddUnbalancedAndRemoveLiquidityProportional(_calculateExactAmountsIn(amountsIn));
    }

    function testAddUnbalancedAndRemoveLiquidityProportional__FuzzSwapFee(uint256 swapFee) public {
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), _boundSwapFee(swapFee));

        uint256[] memory exactAmountsIn = new uint256[](2);
        exactAmountsIn[0] = MIN_AMOUNT;
        exactAmountsIn[1] = MIN_AMOUNT;

        _testAddUnbalancedAndRemoveLiquidityProportional(exactAmountsIn);
    }

    function _calculateExactAmountsIn(uint256[2] memory amountsIn) private view returns (uint256[] memory) {
        uint256[] memory exactAmountsIn = new uint256[](2);
        uint256[] memory maxAmountsIn = _calculateMaxAmountIn();
        exactAmountsIn[0] = bound(amountsIn[0], initBalances[0], maxAmountsIn[0]);
        exactAmountsIn[1] = bound(amountsIn[1], initBalances[1], maxAmountsIn[1]);

        return exactAmountsIn;
    }

    function _calculateMaxAmountIn() private view returns (uint256[] memory) {
        uint256[] memory maxAmountsIn = new uint256[](2);
        for (uint256 i = 0; i < maxAmountsIn.length; i++) {
            uint256 limit = initBalances[i] * 100;

            // we need unchecked here because the operation result can be greater than MAX_UINT258
            unchecked {
                maxAmountsIn[i] = ((initBalances[i] * maxInvariantRatio) / 1e18);
            }

            // if maxAmountsIn[i] < initBalances[i], it means that we had an overflow on previous step
            // if maxAmountsIn[i] > limit, we don't need to add more tokens because x100 is enough
            if (maxAmountsIn[i] > limit || maxAmountsIn[i] < initBalances[i]) {
                maxAmountsIn[i] = limit;
            }

            maxAmountsIn[i] = maxAmountsIn[i] - initBalances[i];
        }

        return maxAmountsIn;
    }

    function _testAddUnbalancedAndRemoveLiquidityProportional(uint256[] memory exactAmountsIn) private checkInvariant {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool(),
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
                pool: pool(),
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

    // testAddProportionalAndRemoveLiquidityExactIn
    function testAddProportionalAndRemoveLiquidityExactIn__Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _setUpVariables(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        _testAddProportionalAndRemoveLiquidityExactIn(_boundExactBPTAmountForSingleTokenOperations(exactBPTAmount));
    }

    function testAddProportionalAndRemoveLiquidityExactIn__FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testAddProportionalAndRemoveLiquidityExactIn(MIN_AMOUNT);
    }

    function testAddProportionalAndRemoveLiquidityExactIn__FuzzBPTAmount(uint256 exactBPTAmount) public {
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        _testAddProportionalAndRemoveLiquidityExactIn(_boundExactBPTAmountForSingleTokenOperations(exactBPTAmount));
    }

    function _boundExactBPTAmountForSingleTokenOperations(uint256 exactBPTAmount) private view returns (uint256) {
        return bound(exactBPTAmount, MIN_AMOUNT, _calculateMaxBPTAmountForSingleTokenOperations());
    }

    function _testAddProportionalAndRemoveLiquidityExactIn(uint256 exactBPTAmount) private checkInvariant {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool(),
                to: address(this),
                maxAmountsIn: [maxAdditionalAmountsIn[0], maxAdditionalAmountsIn[1]].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.PROPORTIONAL,
                userData: bytes("")
            })
        );
        assertEq(bptAmountOut, exactBPTAmount, "bptAmountOut should be equal to exactBPTAmount");

        uint256 removePerOperation = exactBPTAmount / 2;

        // first single token exact in removal
        (uint256 bptAmountInTokenOne, uint256[] memory amountsOutTokenOne, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool(),
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
                pool: pool(),
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

    // testAddLiquiditySingleTokenExactOutAndRemoveExactIn
    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn__Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _setUpVariables(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(
            _boundExactBPTAmountForSingleTokenOperations(exactBPTAmount)
        );
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn__FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(MIN_AMOUNT);
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactIn__FuzzBPTAmount(uint256 exactBPTAmount) public {
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(
            _boundExactBPTAmountForSingleTokenOperations(exactBPTAmount)
        );
    }

    function _testAddLiquiditySingleTokenExactOutAndRemoveExactIn(uint256 exactBPTAmount) private checkInvariant {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool(),
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
                pool: pool(),
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

    // testAddLiquiditySingleTokenExactOutAndRemoveExactOut
    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut__Fuzz(
        uint256 exactBPTAmount,
        uint256[2] memory balancesRaw,
        uint256 swapFee
    ) public {
        _setUpVariables(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(
            _boundExactBPTAmountForSingleTokenOperations(exactBPTAmount)
        );
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut__FuzzBPTAmount(uint256 exactBPTAmount) public {
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

        _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(
            _boundExactBPTAmountForSingleTokenOperations(exactBPTAmount)
        );
    }

    function testAddLiquiditySingleTokenExactOutAndRemoveExactOut__FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(MIN_AMOUNT);
    }

    function _testAddLiquiditySingleTokenExactOutAndRemoveExactOut(uint256 exactBPTAmount) private checkInvariant {
        vault.forceUnlock();

        (uint256[] memory amountsIn, uint256 bptAmountOut, ) = vault.addLiquidity(
            AddLiquidityParams({
                pool: pool(),
                to: address(this),
                maxAmountsIn: [0, maxAdditionalAmountsIn[1]].toMemoryArray(),
                minBptAmountOut: exactBPTAmount,
                kind: AddLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: bytes("")
            })
        );

        assertEq(bptAmountOut, exactBPTAmount, "bpAmountOut should be equal to exactBPTAmount");

        uint256 snapshot = vm.snapshot();
        vm.prank(address(this), address(0));
        (uint256 queryBPTAmountIn, , ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool(),
                from: address(this),
                maxBptAmountIn: MAX_UINT128,
                minAmountsOut: [0, amountsIn[1]].toMemoryArray(),
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: bytes("")
            })
        );
        vm.revertTo(snapshot);

        if (queryBPTAmountIn > bptAmountOut) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector,
                    address(this),
                    bptAmountOut,
                    queryBPTAmountIn
                )
            );
        }

        (uint256 bptAmountIn, uint256[] memory amountsOut, ) = vault.removeLiquidity(
            RemoveLiquidityParams({
                pool: pool(),
                from: address(this),
                maxBptAmountIn: MAX_UINT128,
                minAmountsOut: [0, amountsIn[1]].toMemoryArray(),
                kind: RemoveLiquidityKind.SINGLE_TOKEN_EXACT_OUT,
                userData: bytes("")
            })
        );

        if (queryBPTAmountIn <= bptAmountOut) {
            assertEq(bptAmountIn, bptAmountOut, "bptAmountIn should be equal to bptAmountOut");
            assertEq(amountsOut[0], amountsIn[0], "amountsOut[0] should be equal to amountsIn[0]");
            assertEq(amountsOut[1], amountsIn[1], "amountsOut[1] should be equal to amountsIn[1]");
        }
    }

    // testSwap
    function testSwap__Fuzz(uint256 swapAmount, uint256 swapFee, uint256[2] memory balancesRaw) public {
        _setUpVariables(_boundBalances(balancesRaw), _boundSwapFee(swapFee));

        _testSwap(_boundSwapAmount(swapAmount));
    }

    function testSwap__FuzzSwapFee(uint256 swapFee) public {
        swapFee = _boundSwapFee(swapFee);
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), swapFee);

        _testSwap(MIN_AMOUNT);
    }

    function testSwap__FuzzSwapAmount(uint256 swapAmount) public {
        _setUpVariables([HUGE_INIT_AMOUNT, HUGE_INIT_AMOUNT].toMemoryArray(), maxSwapFee / 2);

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

    function _testSwap(uint256 swapAmount) private checkInvariant {
        vault.forceUnlock();

        (, uint256 amountIn, uint256 amountOut) = vault.swap(
            VaultSwapParams({
                pool: pool(),
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
            VaultSwapParams({
                pool: pool(),
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

    // Internal functions
    function _boundBalances(uint256[2] memory balancesRaw) internal pure virtual returns (uint256[] memory balances) {
        balances = new uint256[](2);
        balances[0] = bound(balancesRaw[0], MIN_BALANCE, MAX_BALANCE);
        balances[1] = bound(balancesRaw[1], MIN_BALANCE, MAX_BALANCE);
    }

    function _boundSwapFee(uint256 swapFee) private view returns (uint256) {
        return bound(swapFee, minSwapFee, maxSwapFee);
    }

    function _calculateMaxBPTAmountForSingleTokenOperations() private view returns (uint256) {
        return ((initBPTAmount * (1e18 - minInvariantRatio)) / 1e18);
    }
}
