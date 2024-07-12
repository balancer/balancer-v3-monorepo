import { Decimal } from 'decimal.js';

import { bn, decimal, fromFp, toFp } from '../numbers';

export function computeInvariantMock(fpBalances: bigint[]): bigint {
  // inv = x + y
  let invariant = decimal(0);

  for (let i = 0; i < fpBalances.length; i++) {
    invariant = invariant.add(fromFp(fpBalances[i]));
  }

  return bn(toFp(invariant));
}

export function computeBalanceMock(fpBalances: bigint[], tokenInIndex: number, invariantRatio: bigint): bigint {
  // inv = x + y
  const invariant = fromFp(computeInvariantMock(fpBalances));
  return bn(
    toFp(
      fromFp(fpBalances[tokenInIndex])
        .add(invariant.mul(fromFp(invariantRatio)))
        .sub(invariant)
    )
  );
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
  fpSwapFeePercentage: bigint
): { bptAmountOut: bigint; swapFeeAmounts: bigint[] } {
  const numTokens = fpCurrentBalances.length;
  const newBalances = [];
  const swapFeeAmountsDecimals = [];

  for (let i = 0; i < numTokens; ++i) {
    newBalances[i] = fromFp(fpCurrentBalances[i]).add(fromFp(fpExactAmounts[i]));
  }

  const currentInvariant = fromFp(computeInvariantMock(fpCurrentBalances));
  const newInvariant = fromFp(computeInvariantMock(newBalances.map((balance) => bn(toFp(balance)))));
  const invariantRatio = newInvariant.div(currentInvariant);

  for (let i = 0; i < numTokens; ++i) {
    const currentBalance = fromFp(fpCurrentBalances[i]);

    if (newBalances[i].gt(invariantRatio.mul(currentBalance))) {
      const taxableAmount = newBalances[i].sub(invariantRatio.mul(currentBalance));
      swapFeeAmountsDecimals[i] = taxableAmount.mul(fromFp(fpSwapFeePercentage));
      newBalances[i] = newBalances[i].sub(swapFeeAmountsDecimals[i]);
    } else {
      swapFeeAmountsDecimals[i] = decimal(0);
    }
  }

  const invariantWithFeesApplied = fromFp(computeInvariantMock(newBalances.map((balance) => bn(toFp(balance)))));
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
  fpSwapFeePercentage: bigint
): { amountInWithFee: bigint; swapFeeAmounts: bigint[] } {
  const totalSupply = fromFp(fpTotalSupply);
  const newSupply = fromFp(fpExactBptAmountOut).add(totalSupply);
  const currentBalanceTokenIn = fromFp(fpCurrentBalances[tokenInIndex]);

  const newBalance = fromFp(computeBalanceMock(fpCurrentBalances, tokenInIndex, bn(toFp(newSupply.div(totalSupply)))));

  const amountIn = newBalance.sub(currentBalanceTokenIn);

  const nonTaxableBalance = newSupply.mul(currentBalanceTokenIn).div(totalSupply);
  const taxableAmount = newBalance.sub(nonTaxableBalance);

  const fee = taxableAmount.div(decimal(1).sub(fromFp(fpSwapFeePercentage))).sub(taxableAmount);

  const swapFeeAmounts = Array(fpCurrentBalances.length).fill(decimal(0));
  swapFeeAmounts[tokenInIndex] = fee;

  const amountInWithFee = amountIn.add(fee);

  return {
    amountInWithFee: bn(toFp(amountInWithFee)),
    swapFeeAmounts: swapFeeAmounts.map((amount) => bn(toFp(amount))),
  };
}

export function computeRemoveLiquiditySingleTokenExactOut(
  fpCurrentBalances: bigint[],
  tokenOutIndex: number,
  fpExactAmountOut: bigint,
  fpTotalSupply: bigint,
  fpSwapFeePercentage: bigint
): { bptAmountIn: bigint; swapFeeAmounts: bigint[] } {
  const newBalances = fpCurrentBalances.map((balance) => fromFp(balance));
  newBalances[tokenOutIndex] = newBalances[tokenOutIndex].sub(fromFp(fpExactAmountOut));

  const currentInvariant = fromFp(computeInvariantMock(fpCurrentBalances));
  const newInvariant = fromFp(computeInvariantMock(newBalances.map((balance) => bn(toFp(balance)))));
  const invariantRatio = newInvariant.div(currentInvariant);

  const taxableAmount = invariantRatio.mul(fromFp(fpCurrentBalances[tokenOutIndex])).sub(newBalances[tokenOutIndex]);
  const fee = taxableAmount.div(decimal(1).sub(fromFp(fpSwapFeePercentage))).sub(taxableAmount);

  newBalances[tokenOutIndex] = newBalances[tokenOutIndex].sub(fee);

  const invariantWithFeesApplied = fromFp(computeInvariantMock(newBalances.map((balance) => bn(toFp(balance)))));

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
  fpSwapFeePercentage: bigint
): { amountOutWithFee: bigint; swapFeeAmounts: bigint[] } {
  const totalSupply = fromFp(fpTotalSupply);
  const newSupply = totalSupply.sub(fromFp(fpExactBptAmountIn));
  const newBalance = fromFp(computeBalanceMock(fpCurrentBalances, tokenOutIndex, bn(toFp(newSupply.div(totalSupply)))));

  const amountOut = fromFp(fpCurrentBalances[tokenOutIndex]).sub(newBalance);

  const newBalanceBeforeTax = newSupply.mul(fromFp(fpCurrentBalances[tokenOutIndex])).div(totalSupply);
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
