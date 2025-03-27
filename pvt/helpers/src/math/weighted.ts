import { Decimal } from 'decimal.js';

import { bn, decimal, fp, fromFp, toFp, FP_ONE, FP_100_PCT } from '../numbers';

export function computeInvariant(fpRawBalances: bigint[], fpRawWeights: bigint[]): bigint {
  const normalizedWeights = fpRawWeights.map(fromFp);
  const balances = fpRawBalances.map(decimal);
  const invariant = balances.reduce((inv, balance, i) => inv.mul(balance.pow(normalizedWeights[i])), decimal(1));
  return bn(invariant);
}

export function computeOutGivenExactIn(
  fpBalanceIn: bigint,
  fpWeightIn: bigint,
  fpBalanceOut: bigint,
  fpWeightOut: bigint,
  fpAmountIn: bigint
): bigint {
  const newBalance = fromFp(fpBalanceIn).add(fromFp(fpAmountIn));
  const base = fromFp(fpBalanceIn).div(newBalance);
  const exponent = fromFp(fpWeightIn).div(fromFp(fpWeightOut));
  const ratio = decimal(1).sub(base.pow(exponent));
  return fp(fromFp(fpBalanceOut).mul(ratio));
}

export function computeInGivenExactOut(
  fpBalanceIn: bigint,
  fpWeightIn: bigint,
  fpBalanceOut: bigint,
  fpWeightOut: bigint,
  fpAmountOut: bigint
): bigint {
  const newBalance = fromFp(fpBalanceOut).sub(fromFp(fpAmountOut));
  const base = fromFp(fpBalanceOut).div(newBalance);
  const exponent = fromFp(fpWeightOut).div(fromFp(fpWeightIn));
  const ratio = base.pow(exponent).sub(1);
  return fp(fromFp(fpBalanceIn).mul(ratio));
}

export function computeBptOutGivenExactTokensIn(
  fpBalances: bigint[],
  fpWeights: bigint[],
  fpAmountsIn: bigint[],
  fpBptTotalSupply: bigint,
  fpSwapFeePercentage: bigint
): bigint {
  const weights = fpWeights.map(fromFp);
  const balances = fpBalances.map(fromFp);
  const amountsIn = fpAmountsIn.map(fromFp);
  const bptTotalSupply = fromFp(fpBptTotalSupply);

  const balanceRatiosWithFee = [];
  let invariantRatioWithFees = decimal(0);
  for (let i = 0; i < balances.length; i++) {
    balanceRatiosWithFee[i] = balances[i].add(amountsIn[i]).div(balances[i]);
    invariantRatioWithFees = invariantRatioWithFees.add(balanceRatiosWithFee[i].mul(weights[i]));
  }

  let invariantRatio = decimal(1);
  for (let i = 0; i < balances.length; i++) {
    let amountInWithoutFee;

    if (balanceRatiosWithFee[i].gt(invariantRatioWithFees)) {
      const nonTaxableAmount = balances[i].mul(invariantRatioWithFees.sub(1));
      const taxableAmount = amountsIn[i].sub(nonTaxableAmount);
      amountInWithoutFee = nonTaxableAmount.add(taxableAmount.mul(decimal(1).sub(fromFp(fpSwapFeePercentage))));
    } else {
      amountInWithoutFee = amountsIn[i];
    }

    const tokenBalanceRatio = balances[i].add(amountInWithoutFee).div(balances[i]);

    invariantRatio = invariantRatio.mul(tokenBalanceRatio.pow(weights[i]));
  }

  const bptOut = bptTotalSupply.mul(invariantRatio.sub(1));
  return fp(bptOut);
}

export function computeBptOutGivenExactTokenIn(
  fpBalance: bigint,
  fpWeight: bigint,
  fpAmountIn: bigint,
  fpBptTotalSupply: bigint,
  fpSwapFeePercentage: bigint
): bigint {
  const balance = fromFp(fpBalance);
  const normalizedWeight = fromFp(fpWeight);
  const amountIn = fromFp(fpAmountIn);
  const bptTotalSupply = fromFp(fpBptTotalSupply);

  let amountInWithoutFee;
  const balanceRatioWithFee = balance.add(amountIn).div(balance);

  const invariantRatioWithFees = balanceRatioWithFee.mul(normalizedWeight).add(complement(normalizedWeight));

  if (balanceRatioWithFee.gt(invariantRatioWithFees)) {
    const nonTaxableAmount = invariantRatioWithFees.gt(1) ? balance.mul(invariantRatioWithFees.sub(1)) : decimal(0);
    const taxableAmount = amountIn.sub(nonTaxableAmount);
    const swapFee = taxableAmount.mul(fromFp(fpSwapFeePercentage));

    amountInWithoutFee = nonTaxableAmount.add(taxableAmount).sub(swapFee);
  } else {
    amountInWithoutFee = amountIn;
    // If a token's amount in is not being charged a swap fee then it might be zero.
    // In this case, it's clear that the sender should receive no BPT.
    if (amountInWithoutFee.floor().toNumber() == 0) {
      return 0;
    }
  }

  const balanceRatio = balance.add(amountInWithoutFee).div(balance);

  const invariantRatio = balanceRatio.pow(normalizedWeight);

  const bptOut = invariantRatio.gt(1) ? bptTotalSupply.mul(invariantRatio.sub(1)) : 0;
  return fp(bptOut);
}

export function computeTokenInGivenExactBptOut(
  fpBalance: bigint,
  fpWeight: bigint,
  fpBptAmountOut: bigint,
  fpBptTotalSupply: bigint,
  fpSwapFeePercentage: bigint
): bigint {
  const bptAmountOut = fromFp(fpBptAmountOut);
  const bptTotalSupply = fromFp(fpBptTotalSupply);
  const weight = fromFp(fpWeight);
  const balance = fromFp(fpBalance);
  const swapFeePercentage = fromFp(fpSwapFeePercentage);

  const invariantRatio = bptTotalSupply.add(bptAmountOut).div(bptTotalSupply);
  const tokenBalanceRatio = invariantRatio.pow(decimal(1).div(weight));
  const tokenBalancePercentageExcess = decimal(1).sub(weight);
  const amountInAfterFee = balance.mul(tokenBalanceRatio.sub(decimal(1)));

  const amountIn = amountInAfterFee.div(decimal(1).sub(tokenBalancePercentageExcess.mul(swapFeePercentage)));
  return fp(amountIn);
}

export function computeBptInGivenExactTokensOut(
  fpBalances: bigint[],
  fpNormalizedWeights: bigint[],
  fpAmountsOut: bigint[],
  fpBptTotalSupply: bigint,
  fpSwapFeePercentage: bigint
): bigint {
  const swapFeePercentage = fromFp(fpSwapFeePercentage);
  const normalizedWeights = fpNormalizedWeights.map(fromFp);
  const balances = fpBalances.map(fromFp);
  const amountsOut = fpAmountsOut.map(fromFp);
  const bptTotalSupply = fromFp(fpBptTotalSupply);

  const balanceRatiosWithoutFee = [];
  let invariantRatioWithoutFees = decimal(0);
  for (let i = 0; i < balances.length; i++) {
    const balanceRatioWithoutFee = balances[i].sub(amountsOut[i]).div(balances[i]);
    balanceRatiosWithoutFee.push(balanceRatioWithoutFee);
    invariantRatioWithoutFees = invariantRatioWithoutFees.add(balanceRatioWithoutFee.mul(normalizedWeights[i]));
  }

  let invariantRatio = decimal(1);
  for (let i = 0; i < balances.length; i++) {
    let amountOutWithFee;
    if (invariantRatioWithoutFees > balanceRatiosWithoutFee[i]) {
      const nonTaxableAmount = balances[i].mul(complement(invariantRatioWithoutFees));
      const taxableAmount = amountsOut[i].sub(nonTaxableAmount);
      const taxableAmountPlusFees = taxableAmount.div(complement(swapFeePercentage));

      amountOutWithFee = nonTaxableAmount.add(taxableAmountPlusFees);
    } else {
      amountOutWithFee = amountsOut[i];
      if (amountOutWithFee.floor().toNumber() == 0) {
        continue;
      }
    }

    const balanceRatio = balances[i].sub(amountOutWithFee).div(balances[i]);
    invariantRatio = invariantRatio.mul(balanceRatio.pow(normalizedWeights[i]));
  }

  const bptIn = bptTotalSupply.mul(complement(invariantRatio));
  return fp(bptIn);
}

export function computeBptInGivenExactTokenOut(
  fpBalance: bigint,
  fpWeight: bigint,
  fpAmountOut: bigint,
  fpBptTotalSupply: bigint,
  fpSwapFeePercentage: bigint
): bigint {
  const balance = fromFp(fpBalance);
  const normalizedWeight = fromFp(fpWeight);
  const amountOut = fromFp(fpAmountOut);
  const bptTotalSupply = fromFp(fpBptTotalSupply);
  const swapFeePercentage = fromFp(fpSwapFeePercentage);

  let amountOutWithFee;
  const balanceRatioWithoutFee = balance.sub(amountOut).div(balance);

  const invariantRatioWithoutFees = balanceRatioWithoutFee.mul(normalizedWeight).add(complement(normalizedWeight));

  if (invariantRatioWithoutFees.gt(balanceRatioWithoutFee)) {
    const nonTaxableAmount = balance.mul(complement(invariantRatioWithoutFees));
    const taxableAmount = amountOut.sub(nonTaxableAmount);
    const taxableAmountPlusFees = taxableAmount.div(complement(swapFeePercentage));

    amountOutWithFee = nonTaxableAmount.add(taxableAmountPlusFees);
  } else {
    amountOutWithFee = amountOut;
    // If a token's amount in is not being charged a swap fee then it might be zero.
    // In this case, it's clear that the sender should receive no BPT.
    if (amountOutWithFee.floor().toNumber() == 0) {
      return 0;
    }
  }

  const balanceRatio = balance.sub(amountOutWithFee).div(balance);

  const invariantRatio = balanceRatio.pow(normalizedWeight);

  const bptOut = bptTotalSupply.mul(complement(invariantRatio));
  return fp(bptOut);
}

export function computeTokenOutGivenExactBptIn(
  fpBalance: bigint,
  fpWeight: bigint,
  fpBptAmountIn: bigint,
  fpBptTotalSupply: bigint,
  fpSwapFeePercentage: bigint
): bigint {
  const bptAmountIn = fromFp(fpBptAmountIn);
  const bptTotalSupply = fromFp(fpBptTotalSupply);
  const swapFeePercentage = fromFp(fpSwapFeePercentage);
  const weight = fromFp(fpWeight);
  const balance = fromFp(fpBalance);

  const invariantRatio = bptTotalSupply.sub(bptAmountIn).div(bptTotalSupply);
  const tokenBalanceRatio = invariantRatio.pow(decimal(1).div(weight));
  const tokenBalancePercentageExcess = decimal(1).sub(weight);
  const amountOutBeforeFee = balance.mul(decimal(1).sub(tokenBalanceRatio));

  const amountOut = amountOutBeforeFee.mul(decimal(1).sub(tokenBalancePercentageExcess.mul(swapFeePercentage)));
  return fp(amountOut);
}

export function computeTokensOutGivenExactBptIn(
  fpBalances: bigint[],
  fpBptAmountIn: bigint,
  fpBptTotalSupply: bigint
): bigint[] {
  const balances = fpBalances.map(fromFp);
  const bptRatio = fromFp(fpBptAmountIn).div(fromFp(fpBptTotalSupply));
  const amountsOut = balances.map((balance) => balance.mul(bptRatio));
  return amountsOut.map(fp);
}

export function computeOneTokenSwapFeeAmount(
  fpBalances: bigint[],
  fpWeights: bigint[],
  lastInvariant: bigint,
  tokenIndex: number
): Decimal {
  const balance = fpBalances.map(fromFp)[tokenIndex];
  const weight = fromFp(fpWeights[tokenIndex]);
  const exponent = decimal(1).div(weight);
  const currentInvariant = computeInvariant(fpBalances, fpWeights);
  const invariantRatio = decimal(lastInvariant).div(decimal(currentInvariant));
  const accruedFees = balance.mul(decimal(1).sub(invariantRatio.pow(exponent)));

  return toFp(accruedFees);
}

export function computeBPTSwapFeeAmount(
  fpInvariantGrowthRatio: bigint,
  preSupply: bigint,
  postSupply: bigint,
  fpProtocolSwapFeePercentage: bigint
): bigint {
  const supplyGrowthRatio = fpDiv(postSupply, preSupply);

  if (bn(fpInvariantGrowthRatio) <= supplyGrowthRatio) {
    return bn(0);
  }
  const swapFeePercentage = FP_100_PCT - fpDiv(supplyGrowthRatio, fpInvariantGrowthRatio);
  const k = fpMul(swapFeePercentage, fpProtocolSwapFeePercentage);

  const numerator = bn(postSupply) * k;
  const denominator = FP_ONE - k;

  return numerator / denominator;
}

export function computeMaxOneTokenSwapFeeAmount(
  fpBalances: bigint[],
  fpWeights: bigint[],
  fpMinInvariantRatio: bigint,
  tokenIndex: number
): Decimal {
  const balance = fpBalances.map(fromFp)[tokenIndex];
  const weight = fromFp(fpWeights[tokenIndex]);

  const exponent = decimal(1).div(weight);
  const maxAccruedFees = balance.mul(decimal(1).sub(fromFp(fpMinInvariantRatio).pow(exponent)));

  return toFp(maxAccruedFees);
}

export function computeSpotPrice(fpBalances: bigint[], fpWeights: bigint[]): bigint {
  const numerator = fromFp(fpBalances[0]).div(fromFp(fpWeights[0]));
  const denominator = fromFp(fpBalances[1]).div(fromFp(fpWeights[1]));
  return fp(numerator.div(denominator).toFixed(0));
}

export function computeBPTPrice(fpBalance: bigint, fpWeight: bigint, totalSupply: bigint): bigint {
  return fp(fromFp(fpBalance).div(fromFp(fpWeight)).div(fromFp(totalSupply)).toFixed(0));
}

export function computeBptOutAddToken(totalSupply: bigint, fpWeight: bigint): bigint {
  const weightSumRatio = decimal(1).div(decimal(1).sub(fromFp(fpWeight)));
  return fp(fromFp(totalSupply).mul(weightSumRatio.sub(1)));
}

function complement(val: Decimal) {
  return val.lt(1) ? decimal(1).sub(val) : 0;
}
