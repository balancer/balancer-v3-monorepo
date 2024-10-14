// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

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
    int256 internal bptProfit = 0;

    constructor() BaseMedusaTest() {
        initialRate = getBptRate();
    }

    /*******************************************************************************
                                    Optimizations
    *******************************************************************************/

    function optimize_rateDecrease() public view returns (int256) {
        return rateDecrease;
    }

    function optimize_bptProfit() public view returns (int256) {
        return int256(bptProfit);
    }

    /*******************************************************************************
                          Symmetrical Add/Remove Liquidity
    *******************************************************************************/

    function computeAddAndRemoveLiquiditySingleToken(
        uint256 tokenIndex,
        uint256 exactBptAmountOut,
        uint256 swapFeePercentage
    ) public {
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

        tokenIndex = boundTokenIndex(tokenIndex);
        exactBptAmountOut = boundBptMint(exactBptAmountOut);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        // deposit tokenAmt to mint exactly bptMintAmt
        medusa.prank(lp);
        uint256 tokenAmountIn = router.addLiquiditySingleTokenExactOut(
            address(pool),
            tokens[tokenIndex],
            type(uint128).max,
            exactBptAmountOut,
            false,
            bytes("")
        );

        // withdraw exactly tokenAmountIn to burn bptAmountIn
        medusa.prank(lp);
        uint256 bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            type(uint128).max,
            tokens[tokenIndex],
            tokenAmountIn,
            false,
            bytes("")
        );

        emit Debug("BPT minted while adding liquidity:", exactBptAmountOut);
        emit Debug("BPT burned while removing the same liquidity:", bptAmountIn);
        bptProfit += int256(exactBptAmountOut) - int256(bptAmountIn);
    }

    function computeRemoveAndAddLiquiditySingleToken(
        uint256 tokenIndex,
        uint256 tokenAmountOut,
        uint256 swapFeePercentage
    ) public {
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

        tokenIndex = boundTokenIndex(tokenIndex);
        tokenAmountOut = boundTokenAmountOut(tokenAmountOut, tokenIndex);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        // withdraw exactly tokenAmountOut to burn bptBurnAmt
        medusa.prank(lp);
        uint256 bptAmountIn = router.removeLiquiditySingleTokenExactOut(
            address(pool),
            type(uint128).max,
            tokens[tokenIndex],
            tokenAmountOut,
            false,
            bytes("")
        );

        // deposit exactly tokenAmountOut to mint bptMintAmt
        uint256[] memory exactAmountsIn = new uint256[](getBalancesLength());
        exactAmountsIn[tokenIndex] = tokenAmountOut;

        medusa.prank(lp);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));

        emit Debug("BPT burned while removing liquidity:", bptAmountIn);
        emit Debug("BPT minted while adding the same liquidity:", bptAmountOut);
        bptProfit += int256(bptAmountOut) - int256(bptAmountIn);
    }

    function computeAddAndRemoveLiquidityMultiToken(uint256 exactBptAmountOut, uint256 swapFeePercentage) public {
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        exactBptAmountOut = boundBptMint(exactBptAmountOut);

        uint256[] memory maxAmountsIn = getMaxAmountsIn();

        // mint exactly bptAmountOut to deposit tokenAmountIn
        medusa.prank(lp);
        uint256[] memory tokenAmountsIn = router.addLiquidityProportional(
            address(pool),
            maxAmountsIn,
            exactBptAmountOut,
            false,
            bytes("")
        );

        // Withdraw exactly tokenAmountsIn to burn bptAmountIn. The function `removeLiquidityUnbalanced` does not
        // exist, so we need to go one token at a time to accomplish this.
        uint256 bptAmountIn = 0;
        for (uint256 i = 0; i < tokenAmountsIn.length; i++) {
            medusa.prank(lp);
            bptAmountIn += router.removeLiquiditySingleTokenExactOut(
                address(pool),
                type(uint128).max,
                tokens[i],
                tokenAmountsIn[i],
                false,
                bytes("")
            );
        }

        emit Debug("BPT minted while adding liquidity:", exactBptAmountOut);
        emit Debug("BPT burned while removing same liquidity:", bptAmountIn);
        bptProfit += int256(exactBptAmountOut) - int256(bptAmountIn);
    }

    function computeRemoveAndAddLiquidityMultiToken(uint256 exactBptAmountIn, uint256 swapFeePercentage) public {
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

        exactBptAmountIn = boundBptBurn(exactBptAmountIn);

        uint256[] memory minAmountsOut = getMinAmountsOut();

        // Burn exactly exactBptAmountIn to withdraw tokenAmountsOut.
        medusa.prank(lp);
        uint256[] memory tokenAmountsOut = router.removeLiquidityProportional(
            address(pool),
            exactBptAmountIn,
            minAmountsOut,
            false,
            bytes("")
        );

        // Deposit exactly tokenAmountsOut to mint bptAmountOut.
        medusa.prank(lp);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), tokenAmountsOut, 0, false, bytes(""));

        emit Debug("BPT burned while removing liquidity:", exactBptAmountIn);
        emit Debug("BPT minted while adding the same liquidity:", bptAmountOut);
        bptProfit += int256(bptAmountOut) - int256(exactBptAmountIn);
    }

    function property_no_bpt_profit() public returns (bool) {
        return assertBptProfit(pool);
    }

    /*******************************************************************************
                          Simple Add/Remove operations
    *******************************************************************************/

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
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

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
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

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
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

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
        // Fee % between 0% and 100%
        swapFeePercentage = bound(swapFeePercentage, 0, 1e18);
        vault.manualSetStaticSwapFeePercentage(address(pool), swapFeePercentage);

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

    /*******************************************************************************
                  Helpers (private functions, so they're not fuzzed)
    *******************************************************************************/

    function assertBptProfit(IBasePool pool) internal returns (bool) {
        return bptProfit <= 0;
    }

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
