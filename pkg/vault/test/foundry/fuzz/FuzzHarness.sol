// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";

import { VaultMockDeployer } from "../utils/VaultMockDeployer.sol";
import { BasePoolMath } from "../../../contracts/BasePoolMath.sol";

contract FuzzHarness is Test {
    using FixedPoint for uint256;

    event Debug(string, uint256);

    // If this flag is false, assertion tests will never fail! But optimizations will work.
    // Changing to false will disable optimizations but allow the assertion tests to run
    bool private constant ASSERT_MODE = false;

    uint256 private constant _MAX_BALANCE = 2 ** (128) - 1; // from PackedTokenBalance.sol
    uint256 private constant _MIN_WEIGHT = 1e16; // 1% (from WeightedPool.sol)
    uint256 private constant _MINIMUM_TRADE_AMOUNT = 1e6;
    uint256 private constant _POOL_MINIMUM_TOTAL_SUPPLY = 1e6;

    IVaultMock private vault;
    IBasePool private stablePool;
    IBasePool private weightedPool;

    // State management
    uint256[] weightedBalanceLive;
    uint256[] stableBalanceLive;
    uint256 weightedBPTSupply;
    uint256 stableBPTSupply;

    // State vars for optimization mode
    uint256 rateDecrease = 0;
    uint256 bptProfit = 0;

    constructor() {
        if (address(vault) == address(0)) {
            uint256 vaultMockMinTradeAmount = 0;
            uint256 vaultMockMinWrapAmount = 0;
            vault = IVaultMock(address(VaultMockDeployer.deploy(vaultMockMinTradeAmount, vaultMockMinWrapAmount)));
        }
        uint256[] memory initialBalances = new uint256[](3);
        initialBalances[0] = 10e18;
        initialBalances[1] = 20e18;
        initialBalances[2] = 30e18;
        createNewWeightedPool(33e16, 33e16, initialBalances);
        createNewStablePool(1000, initialBalances);
    }

    ////////////////////////////////////////
    // Pool Creation

    function createNewWeightedPool(uint256 weight1, uint256 weight2, uint256[] memory initialBalances) private {
        uint256[] memory weights = new uint256[](3);
        weights[0] = bound(weight1, _MIN_WEIGHT, 98e16); // any weight between min & 100%-2(min)
        uint256 remainingWeight = 99e16 - weights[0]; // weights 0 + 1 must <= 100%-min so there's >=1% left for weight 2
        weights[1] = bound(weight2, _MIN_WEIGHT, remainingWeight);
        remainingWeight = 100e16 - (weights[0] + weights[1]);
        weights[2] = remainingWeight;
        WeightedPool.NewPoolParams memory params = WeightedPool.NewPoolParams({
            name: "My Custom Pool",
            symbol: "MCP",
            numTokens: 3,
            normalizedWeights: weights,
            version: "1.0.0"
        });
        weightedPool = IBasePool(new WeightedPool(params, vault));
        // Initialize liquidity for this new weighted pool
        initialBalances = boundBalanceLength(initialBalances, false);
        for (uint256 i; i < initialBalances.length; i++) {
            if (initialBalances[i] < 1 ether) initialBalances[i] += 1 ether;
            weightedBalanceLive.push(initialBalances[0]);
            initialBalances[i] = initialBalances[0];
        }
        weightedBPTSupply += mockInitialize(weightedPool, initialBalances);
    }

    function createNewStablePool(uint256 amplificationParameter, uint256[] memory initialBalances) private {
        StablePool.NewPoolParams memory params = StablePool.NewPoolParams({
            name: "My Custom Pool",
            symbol: "MCP",
            amplificationParameter: bound(amplificationParameter, 1, 5000),
            version: "1.0.0"
        });
        stablePool = IBasePool(new StablePool(params, vault));
        // Initialize liquidity for this new stable pool
        initialBalances = boundBalanceLength(initialBalances, true);
        for (uint256 i; i < initialBalances.length; i++) {
            if (initialBalances[i] < 1 ether) initialBalances[i] += 1 ether;
            stableBalanceLive.push(initialBalances[i]);
        }
        stableBPTSupply += mockInitialize(stablePool, initialBalances);
    }

    ////////////////////////////////////////
    // Optimizations

    function optimize_rateDecrease() public view returns (int256) {
        return int256(rateDecrease);
    }

    function optimize_bptProfit() public view returns (int256) {
        return int256(bptProfit);
    }

    ////////////////////////////////////////
    // Symmetrical Add/Remove Liquidity

    function computeAddAndRemoveLiquiditySingleToken(
        uint256 tokenIndex,
        uint256 bptMintAmt,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public {
        tokenIndex = boundTokenIndex(useStablePool, tokenIndex);
        bptMintAmt = boundBptMint(useStablePool, bptMintAmt);

        // deposit tokenAmt to mint exactly bptMintAmt
        uint256 tokenAmt = computeAddLiquiditySingleTokenExactOut(
            tokenIndex, bptMintAmt, swapFeePercentage, useStablePool
        );

        // withdraw exactly tokenAmt to burn bptBurnAmt
        uint256 bptBurnAmt = computeRemoveLiquiditySingleTokenExactIn(
            tokenIndex, tokenAmt, swapFeePercentage, useStablePool
        );

        emit Debug("BPT minted while adding liq:", bptMintAmt);
        emit Debug("BPT burned while removing the same liq:", bptBurnAmt);
        bptProfit = bptMintAmt - bptBurnAmt;
        if (ASSERT_MODE) {
            assert(bptProfit <= 0);
        }
    }

    function computeRemoveAndAddLiquiditySingleToken(
        uint256 tokenIndex,
        uint256 tokenAmt,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public {
        tokenIndex = boundTokenIndex(useStablePool, tokenIndex);
        tokenAmt = boundTokenWithdraw(useStablePool, tokenAmt, tokenIndex);

        // withdraw exactly tokenAmt to burn bptBurnAmt
        uint256 bptBurnAmt = computeRemoveLiquiditySingleTokenExactOut(
            tokenIndex, tokenAmt, swapFeePercentage, useStablePool
        );

        // deposit exactly tokenAmt to mint bptMintAmt
        uint256[] memory exactAmounts = new uint256[](getBalancesLength(useStablePool));
        exactAmounts[tokenIndex] = tokenAmt;
        uint256 bptMintAmt = computeAddLiquidityUnbalanced(
            exactAmounts, swapFeePercentage, useStablePool
        );

        emit Debug("BPT burned while removing liq:", bptBurnAmt);
        emit Debug("BPT minted while adding the same liq:", bptMintAmt);
        bptProfit = bptMintAmt - bptBurnAmt;
        if (ASSERT_MODE) {
            assert(bptProfit <= 0);
        }
    }

    function computeAddAndRemoveAddLiquidityMultiToken(
        uint256 bptMintAmt,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public {
        bptMintAmt = boundBptMint(useStablePool, bptMintAmt);

        // mint exactly bptMintAmt to deposit tokenAmts
        uint256[] memory tokenAmts = computeProportionalAmountsIn(
            bptMintAmt, useStablePool
        );

        // withdraw exactly tokenAmts to burn bptBurnAmt
        // No computeRemoveLiquidityUnbalanced fn available, need to go one at a time to accomplish this
        uint256 bptBurnAmt = 0;
        for (uint256 i = 0; i < tokenAmts.length; i++) {
            bptBurnAmt += computeRemoveLiquiditySingleTokenExactOut(
                i, tokenAmts[i], swapFeePercentage, useStablePool
            );
        }

        emit Debug("BPT minted while adding liquidity:", bptMintAmt);
        emit Debug("BPT burned while removing same liquidity:", bptBurnAmt);
        bptProfit = bptMintAmt - bptBurnAmt;
        if (ASSERT_MODE) {
            assert(bptProfit <= 0);
        }
    }

    function computeRemoveAndAddLiquidityMultiToken(
        uint256 bptBurnAmt,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public {
        bptBurnAmt = boundBptBurn(useStablePool, bptBurnAmt);

        // burn exactly bptBurnAmt to withdraw tokenAmts
        uint256[] memory tokenAmts = computeProportionalAmountsOut(bptBurnAmt, useStablePool);

        // deposit exactly tokenAmts to mint bptMintAmt
        uint256 bptMintAmt = computeAddLiquidityUnbalanced(tokenAmts, swapFeePercentage, useStablePool);

        emit Debug("BPT burned while removing liquidity:", bptBurnAmt);
        emit Debug("BPT minted while adding the same liquidity:", bptMintAmt);
        bptProfit = bptMintAmt - bptBurnAmt;
        if (ASSERT_MODE) {
            assert(bptProfit <= 0);
        }
    }

    ////////////////////////////////////////
    // Rate Invariants

    function computeProportionalAmountsIn(
        uint256 bptAmountOut,
        bool useStablePool
    ) public returns(uint256[] memory amountsIn) {
        assumeValidTradeAmount(bptAmountOut);
        bptAmountOut = boundBptMint(useStablePool, bptAmountOut);
        (uint256[] memory balances, uint256 bptTotalSupply) = loadState(useStablePool);
        uint256 rateBefore = getBptRate(getPool(useStablePool), balances, bptTotalSupply);

        amountsIn = BasePoolMath.computeProportionalAmountsIn(balances, bptTotalSupply, bptAmountOut);

        uint256[] memory balancesAfter = sumBalances(balances, amountsIn);
        uint256 rateAfter = getBptRate(
            getPool(useStablePool),
            balancesAfter,
            bptTotalSupply + bptAmountOut
        );
        updateState(useStablePool, balancesAfter, 0, bptAmountOut);
        rateDecrease = rateBefore - rateAfter;
        if (ASSERT_MODE) {
            assert(rateDecrease <= 0);
        }
    }

    function computeProportionalAmountsOut(
        uint256 bptAmountIn,
        bool useStablePool
    ) public returns(uint256[] memory amountsOut) {
        assumeValidTradeAmount(bptAmountIn);
        bptAmountIn = boundBptBurn(useStablePool, bptAmountIn);
        (uint256[] memory balances, uint256 bptTotalSupply) = loadState(useStablePool);
        uint256 rateBefore = getBptRate(getPool(useStablePool), balances, bptTotalSupply);

        amountsOut = BasePoolMath.computeProportionalAmountsOut(balances, bptTotalSupply, bptAmountIn);

        uint256[] memory balancesAfter = subBalances(balances, amountsOut);
        uint256 rateAfter = getBptRate(
            getPool(useStablePool),
            balancesAfter,
            bptTotalSupply - bptAmountIn
        );
        updateState(useStablePool, balancesAfter, bptAmountIn, 0);
        rateDecrease = rateBefore - rateAfter;
        if (ASSERT_MODE) {
            assert(rateDecrease <= 0);
        }
    }

    function computeAddLiquidityUnbalanced(
        uint256[] memory exactAmounts,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public returns(uint256 bptAmountOut) {
        exactAmounts = boundBalanceLength(exactAmounts, useStablePool);
        (uint256[] memory balances, uint256 bptTotalSupply) = loadState(useStablePool);
        for (uint256 i = 0; i < exactAmounts.length; i++) {
            exactAmounts[i] = boundTokenDeposit(useStablePool, exactAmounts[i], i);
        }
        IBasePool pool = getPool(useStablePool);
        uint256 rateBefore = getBptRate(pool, balances, bptTotalSupply);

        (uint256 amountOut,) = BasePoolMath.computeAddLiquidityUnbalanced(
            balances,
            exactAmounts,
            bptTotalSupply,
            swapFeePercentage,
            pool
        );

        bptAmountOut = amountOut;
        uint256[] memory balancesAfter = sumBalances(balances, exactAmounts);
        uint256 rateAfter = getBptRate(pool, balancesAfter, bptTotalSupply + amountOut);
        updateState(useStablePool, balancesAfter, 0, amountOut);
        rateDecrease = rateBefore - rateAfter;
        if (ASSERT_MODE) {
            assert(rateDecrease <= 0);
        }
    }

    function computeAddLiquiditySingleTokenExactOut(
        uint256 tokenInIndex,
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public returns (uint256 tokenAmountIn) {
        assumeValidTradeAmount(exactBptAmountOut);
        tokenInIndex = boundTokenIndex(useStablePool, tokenInIndex);
        exactBptAmountOut = boundBptMint(useStablePool, exactBptAmountOut);
        (uint256[] memory balances, uint256 bptTotalSupply) = loadState(useStablePool);
        boundBalanceLength(balances, useStablePool);
        uint256 rateBefore = getBptRate(getPool(useStablePool), balances, bptTotalSupply);

        (uint256 amountInMinusFee, uint256[] memory fees) = BasePoolMath.computeAddLiquiditySingleTokenExactOut(
            balances,
            tokenInIndex,
            exactBptAmountOut,
            bptTotalSupply,
            swapFeePercentage,
            getPool(useStablePool)
        );

        tokenAmountIn = amountInMinusFee;
        balances[tokenInIndex] += (amountInMinusFee + fees[tokenInIndex]);
        uint256 rateAfter = getBptRate(getPool(useStablePool), balances, bptTotalSupply + exactBptAmountOut);
        updateState(useStablePool, balances, 0, exactBptAmountOut);
        rateDecrease = rateBefore - rateAfter;
        if (ASSERT_MODE) {
            assert(rateDecrease <= 0);
        }
    }

    function computeRemoveLiquiditySingleTokenExactOut(
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public returns (uint256 bptAmountIn) {
        assumeValidTradeAmount(exactAmountOut);
        tokenOutIndex = boundTokenIndex(useStablePool, tokenOutIndex);
        exactAmountOut = boundTokenWithdraw(useStablePool, exactAmountOut, tokenOutIndex);
        (uint256[] memory balances, uint256 bptTotalSupply) = loadState(useStablePool);
        uint256 rateBefore = getBptRate(getPool(useStablePool), balances, bptTotalSupply);

        (uint256 _bptAmountIn, uint256[] memory fees) = BasePoolMath.computeRemoveLiquiditySingleTokenExactOut(
            balances,
            tokenOutIndex,
            exactAmountOut,
            bptTotalSupply,
            swapFeePercentage,
            getPool(useStablePool)
        );
        bptAmountIn = _bptAmountIn;

        balances[tokenOutIndex] -= (exactAmountOut + fees[tokenOutIndex]);
        uint256 rateAfter = getBptRate(getPool(useStablePool), balances, bptTotalSupply - bptAmountIn);
        updateState(useStablePool, balances, bptAmountIn, 0);
        rateDecrease = rateBefore - rateAfter;
        if (ASSERT_MODE) {
            assert(rateDecrease <= 0);
        }
    }

    function computeRemoveLiquiditySingleTokenExactIn(
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage,
        bool useStablePool
    ) public returns (uint256 bptAmountOut) {
        assumeValidTradeAmount(exactBptAmountIn);
        tokenOutIndex = boundTokenIndex(useStablePool, tokenOutIndex);
        exactBptAmountIn = boundBptBurn(useStablePool, exactBptAmountIn);
        (uint256[] memory balances, uint256 bptTotalSupply) = loadState(useStablePool);
        uint256 rateBefore = getBptRate(getPool(useStablePool), balances, bptTotalSupply);

        (uint256 amountOutMinusFee,) = BasePoolMath.computeRemoveLiquiditySingleTokenExactIn(
            balances,
            tokenOutIndex,
            exactBptAmountIn,
            bptTotalSupply,
            swapFeePercentage,
            getPool(useStablePool)
        );

        bptAmountOut = amountOutMinusFee;
        balances[tokenOutIndex] -= amountOutMinusFee; // fees already accounted for
        uint256 rateAfter = getBptRate(getPool(useStablePool), balances, bptTotalSupply - exactBptAmountIn);
        updateState(useStablePool, balances, exactBptAmountIn, 0);
        rateDecrease = rateBefore - rateAfter;
        if (ASSERT_MODE) {
            assert(rateDecrease <= 0);
        }
    }

    ////////////////////////////////////////
    // Helpers

    function mockInitialize(IBasePool pool, uint256[] memory balances) private view returns (uint256) {
        uint256 invariant = pool.computeInvariant(balances, Rounding.ROUND_DOWN);
        if (invariant < 1e6) revert();
        return invariant;
    }

    function loadState(bool useStablePool) private returns (uint256[] memory balances, uint256 bptTotalSupply) {
        balances = useStablePool ? stableBalanceLive : weightedBalanceLive;
        bptTotalSupply = useStablePool ? stableBPTSupply : weightedBPTSupply;
    }

    function updateState(
        bool useStablePool,
        uint256[] memory balances,
        uint256 bptAmountIn,
        uint256 bptAmountOut
    ) private {
        if (useStablePool) {
            stableBalanceLive = balances;
            stableBPTSupply -= bptAmountIn;
            stableBPTSupply += bptAmountOut;
            require(stableBPTSupply >= _POOL_MINIMUM_TOTAL_SUPPLY);
        } else {
            weightedBalanceLive = balances;
            weightedBPTSupply -= bptAmountIn;
            weightedBPTSupply += bptAmountOut;
            require(weightedBPTSupply >= _POOL_MINIMUM_TOTAL_SUPPLY);
        }
    }

    function getBptRate(
        IBasePool pool,
        uint256[] memory balances,
        uint256 bptTotalSupply
    ) private returns (uint256) {
        uint256 invariant = pool.computeInvariant(balances, Rounding.ROUND_DOWN);
        return invariant.divDown(bptTotalSupply);
    }

    function getPool(bool useStablePool) private view returns (IBasePool) {
        return useStablePool ? stablePool : weightedPool;
    }

    function getBalancesLength(bool useStablePool) private view returns(uint256 length) {
        length = useStablePool ? stableBalanceLive.length : weightedBalanceLive.length;
    }

    function boundTokenIndex(bool useStablePool, uint256 tokenIndex) private view returns(uint256 boundedIndex) {
        uint256 len = getBalancesLength(useStablePool);
        boundedIndex = bound(tokenIndex, 0, len - 1);
    }

    function boundTokenDeposit(bool useStablePool, uint256 tokenAmt, uint256 tokenIndex) private view returns(uint256 boundedAmt) {
        uint256[] memory balances = useStablePool ? stableBalanceLive : weightedBalanceLive;
        boundedAmt = bound(tokenAmt, 0, _MAX_BALANCE - balances[tokenIndex]);
    }

    function boundTokenWithdraw(bool useStablePool, uint256 tokenAmt, uint256 tokenIndex) private view returns(uint256 boundedAmt) {
        uint256[] memory balances = useStablePool ? stableBalanceLive : weightedBalanceLive;
        boundedAmt = bound(tokenAmt, 0, balances[tokenIndex]);
    }

    function boundBptMint(bool useStablePool, uint256 bptAmt) private view returns(uint256 boundedAmt) {
        uint256 totalSupply = useStablePool ? stableBPTSupply : weightedBPTSupply;
        boundedAmt = bound(bptAmt, 0, _MAX_BALANCE - totalSupply);
    }

    function boundBptBurn(bool useStablePool, uint256 bptAmt) private view returns(uint256 boundedAmt) {
        uint256 totalSupply = useStablePool ? stableBPTSupply : weightedBPTSupply;
        boundedAmt = bound(bptAmt, 0, totalSupply);
    }

    function boundBalanceLength(uint256[] memory balances, bool isStablePool) private pure returns (uint256[] memory) {
        if (!isStablePool) {
            if (balances.length < 3) revert();
            assembly {
                mstore(balances, 3)
            }
            return balances;
        } else {
            if (balances.length < 2) revert();
            uint256 numTokens = bound(balances.length, 2, 8);
            assembly {
                mstore(balances, numTokens)
            }
            return balances;
        }
    }

    function sumBalances(uint256[] memory balances, uint256[] memory amounts) private pure returns (uint256[] memory) {
        require(amounts.length == balances.length);
        uint256[] memory newBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            newBalances[i] = balances[i] + amounts[i];
        }
        return newBalances;
    }

    function subBalances(uint256[] memory balances, uint256[] memory amounts) private pure returns (uint256[] memory) {
        require(amounts.length == balances.length);
        uint256[] memory newBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < balances.length; i++) {
            newBalances[i] = balances[i] - amounts[i];
        }
        return newBalances;
    }

    function assumeValidBalanceLength(uint256[] memory balances) private pure {
        if (balances.length < 2 || balances.length > 8) revert();
    }

    function assumeValidTradeAmount(uint256 tradeAmount) private pure {
        if (tradeAmount != 0 && tradeAmount < _MINIMUM_TRADE_AMOUNT) {
            revert();
        }
    }
}
