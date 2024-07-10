import { Decimal } from 'decimal.js';

import { bn, decimal, fromFp, toFp } from '../numbers';

export function computeInvariantMock(fpBalances: bigint[]): bigint {
  let invariant = decimal(0);

  for (let i = 0; i < fpBalances.length; i++) {
    invariant = invariant.add(fromFp(fpBalances[i]));
  }

  return bn(toFp(invariant));
}

export function computeProportionalAmountsIn(
  fpBalances: bigint[],
  fpBptTotalSupply: bigint,
  fpBptAmountOut: bigint
): bigint[] {
  const bptRatio = fromFp(fpBptAmountOut).div(fromFp(fpBptTotalSupply));
  return fpBalances.map((balance) => bn(toFp(fromFp(balance).mul(bptRatio))));
}

export function computeProportionalAmountsOut(
  fpBalances: bigint[],
  fpBptTotalSupply: bigint,
  fpBptAmountIn: bigint
): bigint[] {
  const bptRatio = fromFp(fpBptAmountIn).div(fromFp(fpBptTotalSupply));
  return fpBalances.map((balance) => bn(toFp(fromFp(balance).mul(bptRatio))));
}

export function computeAddLiquidityUnbalanced(
  fpCurrentBalances: bigint[],
  fpExactAmounts: bigint[],
  fpTotalSupply: bigint,
  fpSwapFeePercentage: bigint,
  computeInvariant: (balances: bigint[]) => bigint
): { bptAmountOut: bigint; swapFeeAmounts: bigint[] } {
  const numTokens = fpCurrentBalances.length;
  const newBalances = [];
  const swapFeeAmountsDecimals = [];

  for (let i = 0; i < numTokens; ++i) {
    newBalances[i] = fromFp(fpCurrentBalances[i]).add(fromFp(fpExactAmounts[i]));
  }

  const currentInvariant = fromFp(computeInvariant(fpCurrentBalances));
  const newInvariant = fromFp(computeInvariant(newBalances.map((balance) => bn(toFp(balance)))));
  const invariantRatio = newInvariant.div(currentInvariant);

  for (let i = 0; i < numTokens; ++i) {
    if (newBalances[i].gt(invariantRatio.mul(fromFp(fpCurrentBalances[i])))) {
      const taxableAmount = newBalances[i].sub(invariantRatio.mul(fromFp(fpCurrentBalances[i])));
      swapFeeAmountsDecimals[i] = taxableAmount.mul(fromFp(fpSwapFeePercentage));
      newBalances[i] = newBalances[i].sub(swapFeeAmountsDecimals[i]);
    } else {
      swapFeeAmountsDecimals[i] = decimal(0);
    }
  }

  const invariantWithFeesApplied = fromFp(computeInvariant(newBalances.map((balance) => bn(toFp(balance)))));
  const bptAmountOut = fromFp(fpTotalSupply).mul(invariantWithFeesApplied.sub(currentInvariant)).div(currentInvariant);

  return {
    bptAmountOut: bn(toFp(bptAmountOut)),
    swapFeeAmounts: swapFeeAmountsDecimals.map((amount) => bn(toFp(amount))),
  };
}

export function computeAddLiquiditySingleTokenExactOut(
  fpCurrentBalances: bigint[],
  tokenInIndex: number,
  fpExactBptAmountOut: bigint,
  fpTotalSupply: bigint,
  fpSwapFeePercentage: bigint,
  computeBalance: (balances: bigint[], index: number, ratio: Decimal) => Decimal
): { amountInWithFee: bigint; swapFeeAmounts: bigint[] } {
  const newSupply = fromFp(fpTotalSupply).add(fromFp(fpExactBptAmountOut));
  const newBalance = fromFp(
    computeBalance(fpCurrentBalances, tokenInIndex, toFp(newSupply.div(fromFp(fpTotalSupply))))
  );

  const amountIn = newBalance.sub(fromFp(fpCurrentBalances[tokenInIndex]));

  const nonTaxableBalance = newSupply.mul(fromFp(fpCurrentBalances[tokenInIndex])).div(fromFp(fpTotalSupply));
  const taxableAmount = newBalance.sub(nonTaxableBalance);

  const fee = taxableAmount.div(decimal(0).sub(fromFp(fpSwapFeePercentage))).sub(taxableAmount);

  const swapFeeAmounts = Array(fpCurrentBalances.length).fill(bn(toFp(decimal(0))));
  swapFeeAmounts[tokenInIndex] = bn(toFp(fee));

  const amountInWithFee = amountIn.add(fee);

  return {
    amountInWithFee: bn(toFp(amountInWithFee)),
    swapFeeAmounts: swapFeeAmounts,
  };
}

export function computeRemoveLiquiditySingleTokenExactOut(
  fpCurrentBalances: bigint[],
  tokenOutIndex: number,
  fpExactAmountOut: bigint,
  fpTotalSupply: bigint,
  fpSwapFeePercentage: bigint,
  computeInvariant: (balances: bigint[]) => bigint
): { bptAmountIn: bigint; swapFeeAmounts: bigint[] } {
  const newBalances = fpCurrentBalances.map((balance) => fromFp(balance));
  newBalances[tokenOutIndex] = newBalances[tokenOutIndex].sub(fromFp(fpExactAmountOut));

  const currentInvariant = fromFp(computeInvariant(fpCurrentBalances));
  const newInvariant = fromFp(computeInvariant(newBalances.map((balance) => bn(toFp(balance)))));
  const invariantRatio = newInvariant.div(currentInvariant);

  const taxableAmount = invariantRatio.mul(fromFp(fpCurrentBalances[tokenOutIndex])).sub(newBalances[tokenOutIndex]);
  const fee = taxableAmount.div(decimal(0).sub(fromFp(fpSwapFeePercentage))).sub(taxableAmount);

  newBalances[tokenOutIndex] = newBalances[tokenOutIndex].sub(fee);

  const invariantWithFeesApplied = fromFp(computeInvariant(newBalances.map((balance) => bn(toFp(balance)))));

  const swapFeeAmounts = Array(fpCurrentBalances.length).fill(decimal(0));
  swapFeeAmounts[tokenOutIndex] = fee;

  const bptAmountIn = fromFp(fpTotalSupply).mul(currentInvariant.sub(invariantWithFeesApplied)).div(currentInvariant);

  return { bptAmountIn: bn(toFp(bptAmountIn)), swapFeeAmounts: swapFeeAmounts.map((amount) => bn(toFp(amount))) };
}

export function computeRemoveLiquiditySingleTokenExactIn(
  fpCurrentBalances: bigint[],
  tokenOutIndex: number,
  fpExactBptAmountIn: bigint,
  fpTotalSupply: bigint,
  fpSwapFeePercentage: bigint,
  computeBalance: (balances: bigint[], index: number, ratio: Decimal) => Decimal
): { amountOutWithFee: bigint; swapFeeAmounts: bigint[] } {
  const newSupply = fromFp(fpTotalSupply).sub(fromFp(fpExactBptAmountIn));
  const newBalance = fromFp(
    computeBalance(fpCurrentBalances, tokenOutIndex, toFp(newSupply.div(fromFp(fpTotalSupply))))
  );

  const amountOut = fromFp(fpCurrentBalances[tokenOutIndex]).sub(newBalance);

  const newBalanceBeforeTax = newSupply.mul(fromFp(fpCurrentBalances[tokenOutIndex])).div(fromFp(fpTotalSupply));
  const taxableAmount = newBalanceBeforeTax.sub(newBalance);

  const fee = taxableAmount.mul(fromFp(fpSwapFeePercentage));

  const swapFeeAmounts = Array(fpCurrentBalances.length).fill(decimal(0));
  swapFeeAmounts[tokenOutIndex] = fee;

  const amountOutWithFee = amountOut.sub(fee);

  return {
    amountOutWithFee: bn(toFp(amountOutWithFee)),
    swapFeeAmounts: swapFeeAmounts.map((amount) => bn(toFp(amount))),
  };
}
