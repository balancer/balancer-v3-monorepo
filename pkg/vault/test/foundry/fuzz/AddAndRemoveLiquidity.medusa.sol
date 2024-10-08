// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";

import { BasePoolMath } from "../../../contracts/BasePoolMath.sol";
import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";

import "../utils/BaseMedusaTest.sol";

contract AddAndRemoveLiquidityMedusaTest is BaseMedusaTest {
    using FixedPoint for uint256;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 private constant _MAX_BALANCE = 2 ** (128) - 1; // from PackedTokenBalance.sol
    uint256 private constant _MINIMUM_TRADE_AMOUNT = 1e6;
    uint256 private constant _POOL_MINIMUM_TOTAL_SUPPLY = 1e6;

    uint256 internal maxRateTolerance = 0;

    uint256 internal initialRate;

    // State var for optimization mode
    int256 internal rateDecrease = 0;

    constructor() BaseMedusaTest() {
        initialRate = getBptRate();
    }

    ////////////////////////////////////////
    // Optimizations

    function optimize_rateDecrease() public view returns (int256) {
        return rateDecrease;
    }

    //    function optimize_bptProfit() public view returns (int256) {
    //        return int256(bptProfit);
    //    }

    ////////////////////////////////////////
    // Symmetrical Add/Remove Liquidity

    //    function computeAddAndRemoveLiquiditySingleToken(
    //        uint256 tokenIndex,
    //        uint256 bptMintAmt,
    //        uint256 swapFeePercentage
    //    ) public {
    //        tokenIndex = boundTokenIndex(tokenIndex);
    //        bptMintAmt = boundBptMint(bptMintAmt);
    //
    //        // deposit tokenAmt to mint exactly bptMintAmt
    //        uint256 tokenAmt = computeAddLiquiditySingleTokenExactOut(
    //            tokenIndex,
    //            bptMintAmt,
    //            swapFeePercentage
    //        );
    //
    //        // withdraw exactly tokenAmt to burn bptBurnAmt
    //        uint256 bptBurnAmt = computeRemoveLiquiditySingleTokenExactIn(
    //            tokenIndex,
    //            tokenAmt,
    //            swapFeePercentage
    //        );
    //
    //        emit Debug("BPT minted while adding liq:", bptMintAmt);
    //        emit Debug("BPT burned while removing the same liq:", bptBurnAmt);
    //        bptProfit = bptMintAmt - bptBurnAmt;
    //        if (ASSERT_MODE) {
    //            assert(bptProfit <= 0);
    //        }
    //    }

    //    function computeRemoveAndAddLiquiditySingleToken(
    //        uint256 tokenIndex,
    //        uint256 tokenAmt,
    //        uint256 swapFeePercentage
    //    ) public {
    //        tokenIndex = boundTokenIndex(tokenIndex);
    //        tokenAmt = boundTokenWithdraw(tokenAmt, tokenIndex);
    //
    //        // withdraw exactly tokenAmt to burn bptBurnAmt
    //        uint256 bptBurnAmt = computeRemoveLiquiditySingleTokenExactOut(
    //            tokenIndex,
    //            tokenAmt,
    //            swapFeePercentage
    //        );
    //
    //        // deposit exactly tokenAmt to mint bptMintAmt
    //        uint256[] memory exactAmounts = new uint256[](getBalancesLength());
    //        exactAmounts[tokenIndex] = tokenAmt;
    //        uint256 bptMintAmt = computeAddLiquidityUnbalanced(exactAmounts, swapFeePercentage);
    //
    //        emit Debug("BPT burned while removing liq:", bptBurnAmt);
    //        emit Debug("BPT minted while adding the same liq:", bptMintAmt);
    //        bptProfit = bptMintAmt - bptBurnAmt;
    //        if (ASSERT_MODE) {
    //            assert(bptProfit <= 0);
    //        }
    //    }
    //
    //    function computeAddAndRemoveAddLiquidityMultiToken(
    //        uint256 bptMintAmt,
    //        uint256 swapFeePercentage
    //    ) public {
    //        bptMintAmt = boundBptMint(bptMintAmt);
    //
    //        // mint exactly bptMintAmt to deposit tokenAmts
    //        uint256[] memory tokenAmts = computeProportionalAmountsIn(bptMintAmt);
    //
    //        // withdraw exactly tokenAmts to burn bptBurnAmt
    //        // No computeRemoveLiquidityUnbalanced fn available, need to go one at a time to accomplish this
    //        uint256 bptBurnAmt = 0;
    //        for (uint256 i = 0; i < tokenAmts.length; i++) {
    //            bptBurnAmt += computeRemoveLiquiditySingleTokenExactOut(i, tokenAmts[i], swapFeePercentage);
    //        }
    //
    //        emit Debug("BPT minted while adding liquidity:", bptMintAmt);
    //        emit Debug("BPT burned while removing same liquidity:", bptBurnAmt);
    //        bptProfit = bptMintAmt - bptBurnAmt;
    //        if (ASSERT_MODE) {
    //            assert(bptProfit <= 0);
    //        }
    //    }
    //
    //    function computeRemoveAndAddLiquidityMultiToken(
    //        uint256 bptBurnAmt,
    //        uint256 swapFeePercentage
    //    ) public {
    //        bptBurnAmt = boundBptBurn(bptBurnAmt);
    //
    //        // burn exactly bptBurnAmt to withdraw tokenAmts
    //        uint256[] memory tokenAmts = computeProportionalAmountsOut(bptBurnAmt);
    //
    //        // deposit exactly tokenAmts to mint bptMintAmt
    //        uint256 bptMintAmt = computeAddLiquidityUnbalanced(tokenAmts, swapFeePercentage);
    //
    //        emit Debug("BPT burned while removing liquidity:", bptBurnAmt);
    //        emit Debug("BPT minted while adding the same liquidity:", bptMintAmt);
    //        bptProfit = bptMintAmt - bptBurnAmt;
    //        if (ASSERT_MODE) {
    //            assert(bptProfit <= 0);
    //        }
    //    }
    //
    ////////////////////////////////////////
    // Rate Invariants

    function computeProportionalAmountsIn(uint256 bptAmountOut) public returns (uint256[] memory amountsIn) {
        assumeValidTradeAmount(bptAmountOut);
        bptAmountOut = boundBptMint(bptAmountOut);

        uint256[] memory maxAmountsIn = getMaxAmountsIn();
        medusa.prank(lp);
        amountsIn = router.addLiquidityProportional(address(pool), maxAmountsIn, bptAmountOut, false, bytes(""));

        updateRateDecrease();
    }

    function computeProportionalAmountsOut(uint256 bptAmountIn) public returns (uint256[] memory amountsOut) {
        assumeValidTradeAmount(bptAmountIn);
        bptAmountIn = boundBptBurn(bptAmountIn);

        uint256[] memory minAmountsOut = getMinAmountsOut();
        medusa.prank(lp);
        amountsOut = router.removeLiquidityProportional(address(pool), bptAmountIn, minAmountsOut, false, bytes(""));

        updateRateDecrease();
    }

    function computeAddLiquidityUnbalanced(
        uint256[] memory exactAmountsIn,
        uint256 swapFeePercentage
    ) public returns (uint256 bptAmountOut) {
        exactAmountsIn = boundBalanceLength(exactAmountsIn);
        for (uint256 i = 0; i < exactAmountsIn.length; i++) {
            exactAmountsIn[i] = boundTokenDeposit(exactAmountsIn[i], i);
        }

        medusa.prank(lp);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));

        updateRateDecrease();
    }

    function computeAddLiquiditySingleTokenExactOut(
        uint256 tokenInIndex,
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage
    ) public returns (uint256 amountIn) {
        assumeValidTradeAmount(exactBptAmountOut);
        tokenInIndex = boundTokenIndex(tokenInIndex);
        exactBptAmountOut = boundBptMint(exactBptAmountOut);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(lp);
        amountIn = router.addLiquiditySingleTokenExactOut(
            address(pool),
            tokens[tokenInIndex],
            type(uint128).max,
            exactBptAmountOut,
            false,
            bytes("")
        );

        updateRateDecrease();
    }

    function computeRemoveLiquiditySingleTokenExactOut(
        uint256 tokenOutIndex,
        uint256 exactAmountOut,
        uint256 swapFeePercentage
    ) public returns (uint256 bptAmountIn) {
        assumeValidTradeAmount(exactAmountOut);
        tokenOutIndex = boundTokenIndex(tokenOutIndex);
        exactAmountOut = boundTokenAmountOut(exactAmountOut, tokenOutIndex);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(lp);
        bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            type(uint128).max,
            tokens[tokenOutIndex],
            exactAmountOut,
            false,
            bytes("")
        );

        updateRateDecrease();
    }

    function computeRemoveLiquiditySingleTokenExactIn(
        uint256 tokenOutIndex,
        uint256 exactBptAmountIn,
        uint256 swapFeePercentage
    ) public returns (uint256 amountOut) {
        assumeValidTradeAmount(exactBptAmountIn);
        tokenOutIndex = boundTokenIndex(tokenOutIndex);
        exactBptAmountIn = boundBptBurn(exactBptAmountIn);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(lp);
        amountOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            exactBptAmountIn,
            tokens[tokenOutIndex],
            0,
            false,
            bytes("")
        );

        updateRateDecrease();
    }

    function property_rate_never_decreases() public returns (bool) {
        return assertRate(pool);
    }

    ////////////////////////////////////////
    // Helpers (private functions, so they're not fuzzed)

    function assertRate(IBasePool pool) internal returns (bool) {
        updateRateDecrease();
        return rateDecrease <= int256(maxRateTolerance);
    }

    function updateRateDecrease() internal {
        uint256 rateAfter = getBptRate();
        rateDecrease = int256(initialRate) - int256(rateAfter);

        emit Debug("initial rate", initialRate);
        emit Debug("rate after", rateAfter);
    }

    function getBptRate() internal returns (uint256) {
        (, , , uint256[] memory lastBalancesLiveScaled18) = vault.getPoolTokenInfo(address(pool));
        uint256 bptTotalSupply = BalancerPoolToken(address(pool)).totalSupply();

        uint256 invariant = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_DOWN);
        return invariant.divDown(bptTotalSupply);
    }

    function getBalancesLength() internal view returns (uint256 length) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        length = balancesRaw.length;
    }

    function boundTokenIndex(uint256 tokenIndex) internal view returns (uint256 boundedIndex) {
        uint256 len = getBalancesLength();
        boundedIndex = bound(tokenIndex, 0, len - 1);
    }

    function boundTokenDeposit(
        uint256 tokenAmountIn,
        uint256 tokenIndex
    ) internal view returns (uint256 boundedAmountIn) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        boundedAmountIn = bound(tokenAmountIn, 0, _MAX_BALANCE - balancesRaw[tokenIndex]);
    }

    function boundTokenAmountOut(
        uint256 tokenAmountOut,
        uint256 tokenIndex
    ) internal view returns (uint256 boundedAmountOut) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        boundedAmountOut = bound(tokenAmountOut, 0, balancesRaw[tokenIndex]);
    }

    function boundBptMint(uint256 bptAmount) internal view returns (uint256 boundedAmt) {
        uint256 totalSupply = BalancerPoolToken(address(pool)).totalSupply();
        boundedAmt = bound(bptAmount, 0, _MAX_BALANCE - totalSupply);
    }

    function boundBptBurn(uint256 bptAmt) internal view returns (uint256 boundedAmt) {
        uint256 totalSupply = BalancerPoolToken(address(pool)).totalSupply();
        boundedAmt = bound(bptAmt, 0, totalSupply);
    }

    function boundBalanceLength(uint256[] memory balances) internal view returns (uint256[] memory) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));
        uint256 length = tokens.length;
        assembly {
            mstore(balances, length)
        }
        return balances;
    }

    function assumeValidTradeAmount(uint256 tradeAmount) internal pure {
        if (tradeAmount != 0 && tradeAmount < _MINIMUM_TRADE_AMOUNT) {
            revert();
        }
    }

    function getMinAmountsOut() internal view returns (uint256[] memory minAmountsOut) {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        minAmountsOut = new uint256[](balances.length);

        for (uint256 i = 0; i < balances.length; i++) {
            minAmountsOut[i] = 0;
        }
    }

    function getMaxAmountsIn() internal view returns (uint256[] memory maxAmountsIn) {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(address(pool));

        maxAmountsIn = new uint256[](balances.length);

        for (uint256 i = 0; i < balances.length; i++) {
            maxAmountsIn[i] = type(uint128).max;
        }
    }
}
