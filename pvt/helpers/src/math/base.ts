import Decimal from 'decimal.js';
import { decimal } from '../numbers';

export function computeInvariantMock(balances: Decimal[]): Decimal {
  let invariant = decimal(1);
  for (let i = 0; i < balances.length; i++) {
    invariant = invariant.mul(balances[i]);
  }

  return invariant.sqrt();
}

export function computeBalanceMock(balances: Decimal[], tokenInIndex: number, invariantRatio: Decimal): Decimal {
  const otherTokenIndex = tokenInIndex == 0 ? 1 : 0;
  const newInvariant = computeInvariantMock(balances).mul(invariantRatio);

  return newInvariant.mul(newInvariant).div(balances[otherTokenIndex]);
}

export function computeProportionalAmountsIn(
  balances: Decimal[],
  bptTotalSupply: Decimal,
  bptAmountOut: Decimal
): Decimal[] {
  const bptRatio = bptAmountOut.div(bptTotalSupply);
  return balances.map((balance) => balance.mul(bptRatio));
}

export function computeProportionalAmountsOut(
  balances: Decimal[],
  bptTotalSupply: Decimal,
  bptAmountIn: Decimal
): Decimal[] {
  const bptRatio = bptAmountIn.div(bptTotalSupply);
  return balances.map((balance) => balance.mul(bptRatio));
}

export function computeAddLiquidityUnbalanced(
  currentBalances: Decimal[],
  exactAmounts: Decimal[],
  totalSupply: Decimal,
  swapFeePercentage: Decimal
): { bptAmountOut: Decimal; swapFeeAmounts: Decimal[] } {
  const numTokens = currentBalances.length;
  const newBalances = [];
  const swapFeeAmountsDecimals = [];

  for (let i = 0; i < numTokens; ++i) {
    newBalances[i] = currentBalances[i].add(exactAmounts[i]);
  }

  const currentInvariant = computeInvariantMock(currentBalances);
  const newInvariant = computeInvariantMock(newBalances);
  const invariantRatio = newInvariant.div(currentInvariant);

  for (let i = 0; i < numTokens; ++i) {
    const currentBalance = currentBalances[i];

    if (newBalances[i].gt(invariantRatio.mul(currentBalance))) {
      const taxableAmount = newBalances[i].sub(invariantRatio.mul(currentBalance));
      swapFeeAmountsDecimals[i] = taxableAmount.mul(swapFeePercentage);
      newBalances[i] = newBalances[i].sub(swapFeeAmountsDecimals[i]);
    } else {
      swapFeeAmountsDecimals[i] = decimal(0);
    }
  }

  const invariantWithFeesApplied = computeInvariantMock(newBalances);
  const bptAmountOut = totalSupply.mul(invariantWithFeesApplied.sub(currentInvariant)).div(currentInvariant);

  return {
    bptAmountOut: bptAmountOut,
    swapFeeAmounts: swapFeeAmountsDecimals,
  };
}

export function computeAddLiquiditySingleTokenExactOut(
  currentBalances: Decimal[],
  tokenInIndex: number,
  exactBptAmountOut: Decimal,
  totalSupply: Decimal,
  swapFeePercentage: Decimal
): { amountInWithFee: Decimal; swapFeeAmounts: Decimal[] } {
  const newSupply = exactBptAmountOut.add(totalSupply);
  const currentBalanceTokenIn = currentBalances[tokenInIndex];

  const newBalance = computeBalanceMock(currentBalances, tokenInIndex, newSupply.div(totalSupply));

  const amountIn = newBalance.sub(currentBalanceTokenIn);

  const nonTaxableBalance = newSupply.mul(currentBalanceTokenIn).div(totalSupply);
  const taxableAmount = newBalance.sub(nonTaxableBalance);

  const fee = taxableAmount.div(decimal(1).sub(swapFeePercentage)).sub(taxableAmount);

  const swapFeeAmounts = Array(currentBalances.length).fill(decimal(0));
  swapFeeAmounts[tokenInIndex] = fee;

  const amountInWithFee = amountIn.add(fee);

  return {
    amountInWithFee: amountInWithFee,
    swapFeeAmounts: swapFeeAmounts,
  };
}

export function computeRemoveLiquiditySingleTokenExactOut(
  currentBalances: Decimal[],
  tokenOutIndex: number,
  exactAmountOut: Decimal,
  totalSupply: Decimal,
  swapFeePercentage: Decimal
): { bptAmountIn: Decimal; swapFeeAmounts: Decimal[] } {
  const newBalances = currentBalances.map((balance) => balance);
  newBalances[tokenOutIndex] = newBalances[tokenOutIndex].sub(exactAmountOut);

  const currentInvariant = computeInvariantMock(currentBalances);
  const newInvariant = computeInvariantMock(newBalances);
  const invariantRatio = newInvariant.div(currentInvariant);

  const taxableAmount = invariantRatio.mul(currentBalances[tokenOutIndex]).sub(newBalances[tokenOutIndex]);
  const fee = taxableAmount.div(decimal(1).sub(swapFeePercentage)).sub(taxableAmount);

  newBalances[tokenOutIndex] = newBalances[tokenOutIndex].sub(fee);

  const invariantWithFeesApplied = computeInvariantMock(newBalances);

  const swapFeeAmounts = Array(currentBalances.length).fill(decimal(0));
  swapFeeAmounts[tokenOutIndex] = fee;

  const bptAmountIn = totalSupply.mul(currentInvariant.sub(invariantWithFeesApplied)).div(currentInvariant);

  return { bptAmountIn: bptAmountIn, swapFeeAmounts: swapFeeAmounts };
}

export function computeRemoveLiquiditySingleTokenExactIn(
  currentBalances: Decimal[],
  tokenOutIndex: number,
  exactBptAmountIn: Decimal,
  totalSupply: Decimal,
  swapFeePercentage: Decimal
): { amountOutWithFee: Decimal; swapFeeAmounts: Decimal[] } {
  const newSupply = totalSupply.sub(exactBptAmountIn);
  const newBalance = computeBalanceMock(currentBalances, tokenOutIndex, newSupply.div(totalSupply));

  const amountOut = currentBalances[tokenOutIndex].sub(newBalance);

  const newBalanceBeforeTax = newSupply.mul(currentBalances[tokenOutIndex]).div(totalSupply);
  const taxableAmount = newBalanceBeforeTax.sub(newBalance);

  const fee = taxableAmount.mul(swapFeePercentage);

  const swapFeeAmounts = Array(currentBalances.length).fill(decimal(0));
  swapFeeAmounts[tokenOutIndex] = fee;

  const amountOutWithFee = amountOut.sub(fee);

  return {
    amountOutWithFee: amountOutWithFee,
    swapFeeAmounts: swapFeeAmounts,
  };
}
