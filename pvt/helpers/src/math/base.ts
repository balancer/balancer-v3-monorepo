import { bn, fp, fpDiv, fpMul, fromFp, toFp } from '../numbers';

export function computeInvariantMock(balances: bigint[]): bigint {
  // inv = x + y
  let invariant = 0n;
  for (let i = 0; i < balances.length; i++) {
    invariant = invariant + balances[i];
  }

  return invariant;
}

export function computeBalanceMock(balances: bigint[], tokenInIndex: number, invariantRatio: bigint): bigint {
  const invariant = computeInvariantMock(balances);
  return balances[tokenInIndex] + fpMul(invariant, invariantRatio) - invariant;
}

export function computeProportionalAmountsIn(
  balances: bigint[],
  bptTotalSupply: bigint,
  bptAmountOut: bigint
): bigint[] {
  return balances.map((balance) => (balance * bptAmountOut) / bptTotalSupply);
}

export function computeProportionalAmountsOut(
  balances: bigint[],
  bptTotalSupply: bigint,
  bptAmountIn: bigint
): bigint[] {
  return balances.map((balance) => (balance * bptAmountIn) / bptTotalSupply);
}

export function computeAddLiquidityUnbalanced(
  currentBalances: bigint[],
  exactAmounts: bigint[],
  totalSupply: bigint,
  swapFeePercentage: bigint
): { bptAmountOut: bigint; swapFeeAmounts: bigint[] } {
  const numTokens = currentBalances.length;
  const newBalances: bigint[] = [];
  const swapFeeAmountsDecimals: bigint[] = [];

  for (let i = 0; i < numTokens; ++i) {
    newBalances[i] = currentBalances[i] + exactAmounts[i];
  }

  const currentInvariant = computeInvariantMock(currentBalances);
  const newInvariant = computeInvariantMock(newBalances);
  const invariantRatio = fpDiv(newInvariant, currentInvariant);

  for (let i = 0; i < numTokens; ++i) {
    const currentBalance = currentBalances[i];

    if (newBalances[i] > fpMul(invariantRatio, currentBalance)) {
      const taxableAmount = newBalances[i] - fpMul(invariantRatio, currentBalance);
      swapFeeAmountsDecimals[i] = fpMul(taxableAmount, swapFeePercentage);
      newBalances[i] = newBalances[i] - swapFeeAmountsDecimals[i];
    } else {
      swapFeeAmountsDecimals[i] = 0n;
    }
  }

  const invariantWithFeesApplied = computeInvariantMock(newBalances);
  const bptAmountOut = (totalSupply * (invariantWithFeesApplied - currentInvariant)) / currentInvariant;

  return {
    bptAmountOut: bptAmountOut,
    swapFeeAmounts: swapFeeAmountsDecimals,
  };
}

export function computeAddLiquiditySingleTokenExactOut(
  currentBalances: bigint[],
  tokenInIndex: number,
  exactBptAmountOut: bigint,
  totalSupply: bigint,
  swapFeePercentage: bigint
): { amountInWithFee: bigint; swapFeeAmounts: bigint[] } {
  const newSupply = exactBptAmountOut + totalSupply;
  const currentBalanceTokenIn = currentBalances[tokenInIndex];

  const newBalance = computeBalanceMock(currentBalances, tokenInIndex, fpDiv(newSupply, totalSupply));

  const amountIn = newBalance - currentBalanceTokenIn;

  const nonTaxableBalance = (newSupply * currentBalanceTokenIn) / totalSupply;
  const taxableAmount = newBalance - nonTaxableBalance;

  const fee = fpDiv(taxableAmount, fp(1) - swapFeePercentage) - taxableAmount;

  const swapFeeAmounts = Array(currentBalances.length).fill(0n);
  swapFeeAmounts[tokenInIndex] = fee;

  const amountInWithFee = amountIn + fee;

  return {
    amountInWithFee: amountInWithFee,
    swapFeeAmounts: swapFeeAmounts,
  };
}

export function computeRemoveLiquiditySingleTokenExactOut(
  currentBalances: bigint[],
  tokenOutIndex: number,
  exactAmountOut: bigint,
  totalSupply: bigint,
  swapFeePercentage: bigint
): { bptAmountIn: bigint; swapFeeAmounts: bigint[] } {
  const newBalances = currentBalances.map((balance) => balance);
  newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - exactAmountOut;

  const currentInvariant = computeInvariantMock(currentBalances);
  const newInvariant = computeInvariantMock(newBalances);
  const invariantRatio = fpDiv(newInvariant, currentInvariant);

  const taxableAmount = fpMul(invariantRatio, currentBalances[tokenOutIndex]) - newBalances[tokenOutIndex];
  const fee = fpDiv(taxableAmount, fp(1) - swapFeePercentage) - taxableAmount;

  newBalances[tokenOutIndex] = newBalances[tokenOutIndex] - fee;

  const invariantWithFeesApplied = computeInvariantMock(newBalances);

  const swapFeeAmounts = Array(currentBalances.length).fill(0n);
  swapFeeAmounts[tokenOutIndex] = fee;

  const bptAmountIn = (totalSupply * (currentInvariant - invariantWithFeesApplied)) / currentInvariant;

  return { bptAmountIn: bptAmountIn, swapFeeAmounts: swapFeeAmounts };
}

export function computeRemoveLiquiditySingleTokenExactIn(
  currentBalances: bigint[],
  tokenOutIndex: number,
  exactBptAmountIn: bigint,
  totalSupply: bigint,
  swapFeePercentage: bigint
): { amountOutWithFee: bigint; swapFeeAmounts: bigint[] } {
  const newSupply = totalSupply - exactBptAmountIn;
  const newBalance = computeBalanceMock(currentBalances, tokenOutIndex, fpDiv(newSupply, totalSupply));

  const amountOut = currentBalances[tokenOutIndex] - newBalance;

  const newBalanceBeforeTax = (newSupply * currentBalances[tokenOutIndex]) / totalSupply;
  const taxableAmount = newBalanceBeforeTax - newBalance;

  const fee = fpMul(taxableAmount, swapFeePercentage);

  const swapFeeAmounts = Array(currentBalances.length).fill(0n);
  swapFeeAmounts[tokenOutIndex] = fee;

  const amountOutWithFee = amountOut - fee;

  return {
    amountOutWithFee: amountOutWithFee,
    swapFeeAmounts: swapFeeAmounts,
  };
}
