// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";

import "../utils/BaseMedusaTest.sol";

contract AddAndRemoveLiquidityMedusaTest is BaseMedusaTest {
    using FixedPoint for uint256;

    // PackedTokenBalance.sol defines a max of 128 bits to store the balance of the pool.
    uint256 private constant _MAX_BALANCE = type(uint128).max;
    uint256 private constant _MINIMUM_TRADE_AMOUNT = 1e6;
    uint256 private constant _POOL_MINIMUM_TOTAL_SUPPLY = 1e6;

    uint256 internal maxRateTolerance = 0;

    uint256 internal initialRate;

    // State var for optimization mode
    int256 internal rateDecrease = 0;
    int256 internal bptProfit = 0;

    constructor() BaseMedusaTest() {
        initialRate = vault.getBptRate(address(pool));
        // Set swap fee percentage to 0, which is the worst scenario since there's no LP fees. Circumvent minimum swap
        // fees, for testing purposes.
        vault.manualUnsafeSetStaticSwapFeePercentage(address(pool), 0);
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

    function computeAddAndRemoveLiquiditySingleToken(uint256 tokenIndex, uint256 exactBptAmountOut) public {
        tokenIndex = boundTokenIndex(tokenIndex);
        exactBptAmountOut = boundBptMint(exactBptAmountOut);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        // deposit tokenAmountIn to mint exactly exactBptAmountOut
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

    function computeRemoveAndAddLiquiditySingleToken(uint256 tokenIndex, uint256 tokenAmountOut) public {
        tokenIndex = boundTokenIndex(tokenIndex);
        tokenAmountOut = boundTokenAmountOut(tokenAmountOut, tokenIndex);

        if (tokenAmountOut == 0) return;

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

        // deposit exactly tokenAmountOut to mint bptAmountOut.
        uint256[] memory exactAmountsIn = new uint256[](vault.getPoolTokens(address(pool)).length);
        exactAmountsIn[tokenIndex] = tokenAmountOut;

        medusa.prank(lp);
        uint256 bptAmountOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));

        emit Debug("BPT burned while removing liquidity:", bptAmountIn);
        emit Debug("BPT minted while adding the same liquidity:", bptAmountOut);
        bptProfit += int256(bptAmountOut) - int256(bptAmountIn);
    }

    function computeAddAndRemoveLiquidityMultiToken(uint256 exactBptAmountOut) public {
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

    function computeRemoveAndAddLiquidityMultiToken(uint256 exactBptAmountIn) public {
        exactBptAmountIn = boundBptBurn(exactBptAmountIn);

        if (exactBptAmountIn == 0) return;

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

    function property_no_bpt_profit() public view returns (bool) {
        return assertBptProfit();
    }

    /*******************************************************************************
                          Simple Add/Remove operations
    *******************************************************************************/

    function computeProportionalAmountsIn(uint256 bptAmountOut) public returns (uint256[] memory amountsIn) {
        bptAmountOut = boundBptMint(bptAmountOut);

        uint256[] memory maxAmountsIn = getMaxAmountsIn();
        medusa.prank(lp);
        amountsIn = router.addLiquidityProportional(address(pool), maxAmountsIn, bptAmountOut, false, bytes(""));

        updateRateDecrease();
    }

    function computeProportionalAmountsOut(uint256 bptAmountIn) public returns (uint256[] memory amountsOut) {
        bptAmountIn = boundBptBurn(bptAmountIn);

        if (bptAmountIn == 0) return getMinAmountsOut();

        uint256[] memory minAmountsOut = getMinAmountsOut();
        medusa.prank(lp);
        amountsOut = router.removeLiquidityProportional(address(pool), bptAmountIn, minAmountsOut, false, bytes(""));

        updateRateDecrease();
    }

    function computeAddLiquidityUnbalanced(uint256[] memory exactAmountsIn) public returns (uint256 bptAmountOut) {
        exactAmountsIn = boundBalanceLength(exactAmountsIn);
        bool anyNonZero = false;
        for (uint256 i = 0; i < exactAmountsIn.length; i++) {
            exactAmountsIn[i] = boundTokenDeposit(exactAmountsIn[i], i);
            if (exactAmountsIn[i] != 0) anyNonZero = true;
        }
        // All-zero input just reverts; skip to avoid wasting a fuzz cycle.
        if (!anyNonZero) return 0;

        medusa.prank(lp);
        bptAmountOut = router.addLiquidityUnbalanced(address(pool), exactAmountsIn, 0, false, bytes(""));

        updateRateDecrease();
    }

    function computeAddLiquiditySingleTokenExactOut(
        uint256 tokenInIndex,
        uint256 exactBptAmountOut
    ) public returns (uint256 amountIn) {
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
        uint256 exactAmountOut
    ) public returns (uint256 bptAmountIn) {
        tokenOutIndex = boundTokenIndex(tokenOutIndex);
        exactAmountOut = boundTokenAmountOut(exactAmountOut, tokenOutIndex);

        if (exactAmountOut == 0) return 0;

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
        uint256 exactBptAmountIn
    ) public returns (uint256 amountOut) {
        tokenOutIndex = boundTokenIndex(tokenOutIndex);

        // Use a tighter cap than boundBptBurn for single-token exits, which can drive the
        // pool into extreme imbalance if too much BPT is burned at once.
        uint256 totalSupply = BalancerPoolToken(address(pool)).totalSupply();
        uint256 lpBalance = BalancerPoolToken(address(pool)).balanceOf(lp);
        uint256 maxBurn = totalSupply / 100; // 1% of supply max for single-token exit
        if (maxBurn > lpBalance) maxBurn = lpBalance;
        if (maxBurn < _MINIMUM_TRADE_AMOUNT) return 0;
        exactBptAmountIn = bound(exactBptAmountIn, _MINIMUM_TRADE_AMOUNT, maxBurn);

        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));

        medusa.prank(lp);
        amountOut = router.removeLiquiditySingleTokenExactIn(
            address(pool),
            exactBptAmountIn,
            tokens[tokenOutIndex],
            1,
            false,
            bytes("")
        );

        updateRateDecrease();
    }

    function property_rate_never_decreases() public returns (bool) {
        return assertRate();
    }

    /*******************************************************************************
                  Helpers (private functions, so they're not fuzzed)
    *******************************************************************************/

    function assertBptProfit() internal view returns (bool) {
        return bptProfit <= 0;
    }

    function assertRate() internal returns (bool) {
        updateRateDecrease();
        return rateDecrease <= int256(0);
    }

    function updateRateDecrease() internal {
        uint256 rateAfter = vault.getBptRate(address(pool));
        rateDecrease = int256(initialRate) - int256(rateAfter);

        emit Debug("initial rate", initialRate);
        emit Debug("rate after", rateAfter);
    }

    function boundTokenIndex(uint256 tokenIndex) internal view returns (uint256 boundedIndex) {
        uint256 len = vault.getPoolTokens(address(pool)).length;
        boundedIndex = bound(tokenIndex, 0, len - 1);
    }

    // For unbalanced adds: each token is either 0 or >= _MINIMUM_TRADE_AMOUNT.
    // Snap the (0, _MINIMUM_TRADE_AMOUNT) dead zone to the nearest valid value.
    function boundTokenDeposit(
        uint256 tokenAmountIn,
        uint256 tokenIndex
    ) internal view returns (uint256 boundedAmountIn) {
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        uint256 poolHeadroom = _MAX_BALANCE - balancesRaw[tokenIndex];
        
        uint256 lpBalance = tokens[tokenIndex].balanceOf(lp);
        uint256 maxDeposit = poolHeadroom < lpBalance ? poolHeadroom : lpBalance;

        if (maxDeposit < _MINIMUM_TRADE_AMOUNT) return 0;

        boundedAmountIn = bound(tokenAmountIn, 0, maxDeposit);
        if (boundedAmountIn != 0 && boundedAmountIn < _MINIMUM_TRADE_AMOUNT) {
            boundedAmountIn = _MINIMUM_TRADE_AMOUNT;
        }
    }

    function boundTokenAmountOut(
        uint256 tokenAmountOut,
        uint256 tokenIndex
    ) internal view returns (uint256 boundedAmountOut) {
        (, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));
        
        if (balancesRaw[tokenIndex] < _MINIMUM_TRADE_AMOUNT) return 0;

        boundedAmountOut = bound(tokenAmountOut, _MINIMUM_TRADE_AMOUNT, balancesRaw[tokenIndex]);
    }

    function boundBptMint(uint256 bptAmount) internal view returns (uint256 boundedAmt) {
        uint256 totalSupply = BalancerPoolToken(address(pool)).totalSupply();
        (IERC20[] memory tokens, , uint256[] memory balancesRaw, ) = vault.getPoolTokenInfo(address(pool));

        uint256 maxAffordable = _MAX_BALANCE - totalSupply;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (balancesRaw[i] == 0) continue;
            // Rough estimate: BPT affordable given LP's token balance
            // Discounted to accommodate single token operations (which have fees and price impact, so the
            // proportional estimate is less accurate).
            uint256 lpAffordable = (tokens[i].balanceOf(lp) * totalSupply) / balancesRaw[i] / 4;
            if (lpAffordable < maxAffordable) maxAffordable = lpAffordable;
        }

        if (maxAffordable < _MINIMUM_TRADE_AMOUNT) return _MINIMUM_TRADE_AMOUNT;
        boundedAmt = bound(bptAmount, _MINIMUM_TRADE_AMOUNT, maxAffordable);
    }

    function boundBptBurn(uint256 bptAmt) internal view returns (uint256 boundedAmt) {
        uint256 totalSupply = BalancerPoolToken(address(pool)).totalSupply();
        uint256 lpBalance = BalancerPoolToken(address(pool)).balanceOf(lp);
        uint256 maxBurn = totalSupply - _POOL_MINIMUM_TOTAL_SUPPLY;

        if (maxBurn > lpBalance) maxBurn = lpBalance;
        if (maxBurn < _MINIMUM_TRADE_AMOUNT) return 0;

        boundedAmt = bound(bptAmt, _MINIMUM_TRADE_AMOUNT, maxBurn);
    }

    function boundBalanceLength(uint256[] memory balances) internal view returns (uint256[] memory) {
        (IERC20[] memory tokens, , , ) = vault.getPoolTokenInfo(address(pool));
        uint256 length = tokens.length;
        assembly {
            mstore(balances, length)
        }
        return balances;
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
