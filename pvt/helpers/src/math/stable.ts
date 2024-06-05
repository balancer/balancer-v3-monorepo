import { Decimal } from 'decimal.js';
import { BigNumberish } from 'ethers';
import { decimal, bn, fp, fromFp, toFp } from '../numbers';

export function calculateInvariant(fpRawBalances: BigNumberish[], amplificationParameter: BigNumberish): bigint {
  return calculateApproxInvariant(fpRawBalances, amplificationParameter);
}

export function calculateApproxInvariant(fpRawBalances: BigNumberish[], amplificationParameter: BigNumberish): bigint {
  const totalCoins = fpRawBalances.length;
  const balances: Decimal[] = fpRawBalances.map(fromFp);

  const sum: Decimal = balances.reduce((a, b) => a.add(b), decimal(0));

  if (sum.isZero()) {
    return bn(0);
  }

  let inv = sum;
  let prevInv = decimal(0);
  const ampTimesTotal = decimal(amplificationParameter).mul(totalCoins);

  for (let i = 0; i < 255; i++) {
    let P_D = balances[0].mul(totalCoins);
    for (let j = 1; j < totalCoins; j++) {
      P_D = P_D.mul(balances[j]).mul(totalCoins).div(inv);
    }

    prevInv = inv;
    inv = decimal(totalCoins)
      .mul(inv)
      .mul(inv)
      .add(ampTimesTotal.mul(sum).mul(P_D))
      .div(decimal(totalCoins).add(1).mul(inv).add(ampTimesTotal.sub(1).mul(P_D)));

    // converge with precision of integer 1
    if (inv.gt(prevInv)) {
      if (inv.sub(prevInv).lte(1)) {
        break;
      }
    } else if (prevInv.sub(inv).lte(1)) {
      break;
    }
  }

  return fp(inv);
}

export function calculateAnalyticalInvariantForTwoTokens(
  fpRawBalances: BigNumberish[],
  amplificationParameter: BigNumberish
): bigint {
  if (fpRawBalances.length !== 2) {
    throw 'Analytical invariant is solved only for 2 balances';
  }

  const sum = fpRawBalances.reduce((a: Decimal, b: BigNumberish) => a.add(fromFp(b)), decimal(0));
  const prod = fpRawBalances.reduce((a: Decimal, b: BigNumberish) => a.mul(fromFp(b)), decimal(1));

  // The amplification parameter equals to: A n^(n-1), where A is the amplification coefficient
  const amplificationCoefficient = decimal(amplificationParameter).div(2);

  //Q
  const q = amplificationCoefficient.mul(-16).mul(sum).mul(prod);

  //P
  const p = amplificationCoefficient.minus(decimal(1).div(4)).mul(16).mul(prod);

  //C
  const c = q
    .pow(2)
    .div(4)
    .add(p.pow(3).div(27))
    .pow(1 / 2)
    .minus(q.div(2))
    .pow(1 / 3);

  const invariant = c.minus(p.div(c.mul(3)));
  return fp(invariant);
}

export function calcOutGivenExactIn(
  fpBalances: BigNumberish[],
  amplificationParameter: BigNumberish,
  tokenIndexIn: number,
  tokenIndexOut: number,
  fpTokenAmountIn: BigNumberish
): Decimal {
  const invariant = fromFp(calculateInvariant(fpBalances, amplificationParameter));

  const balances = fpBalances.map(fromFp);
  balances[tokenIndexIn] = balances[tokenIndexIn].add(fromFp(fpTokenAmountIn));

  const finalBalanceOut = _getTokenBalanceGivenInvariantAndAllOtherBalances(
    balances,
    decimal(amplificationParameter),
    invariant,
    tokenIndexOut
  );

  return toFp(balances[tokenIndexOut].sub(finalBalanceOut));
}

export function calcInGivenExactOut(
  fpBalances: BigNumberish[],
  amplificationParameter: BigNumberish,
  tokenIndexIn: number,
  tokenIndexOut: number,
  fpTokenAmountOut: BigNumberish
): Decimal {
  const invariant = fromFp(calculateInvariant(fpBalances, amplificationParameter));

  const balances = fpBalances.map(fromFp);
  balances[tokenIndexOut] = balances[tokenIndexOut].sub(fromFp(fpTokenAmountOut));

  const finalBalanceIn = _getTokenBalanceGivenInvariantAndAllOtherBalances(
    balances,
    decimal(amplificationParameter),
    invariant,
    tokenIndexIn
  );

  return toFp(finalBalanceIn.sub(balances[tokenIndexIn]));
}

// The amp factor input must be a number: *not* multiplied by the precision
export function getTokenBalanceGivenInvariantAndAllOtherBalances(
  amp: number,
  fpBalances: BigNumberish[],
  fpInvariant: BigNumberish,
  tokenIndex: number
): bigint {
  const invariant = fromFp(fpInvariant);
  const balances = fpBalances.map(fromFp);
  return fp(_getTokenBalanceGivenInvariantAndAllOtherBalances(balances, decimal(amp), invariant, tokenIndex));
}

function _getTokenBalanceGivenInvariantAndAllOtherBalances(
  balances: Decimal[],
  amplificationParameter: Decimal | BigNumberish,
  invariant: Decimal,
  tokenIndex: number
): Decimal {
  let sum = decimal(0);
  let mul = decimal(1);
  const numTokens = balances.length;

  for (let i = 0; i < numTokens; i++) {
    if (i != tokenIndex) {
      sum = sum.add(balances[i]);
      mul = mul.mul(balances[i]);
    }
  }

  // const a = 1;
  amplificationParameter = decimal(amplificationParameter);
  const b = invariant.div(amplificationParameter.mul(numTokens)).add(sum).sub(invariant);
  const c = invariant
    .pow(numTokens + 1)
    .mul(-1)
    .div(
      amplificationParameter.mul(
        decimal(numTokens)
          .pow(numTokens + 1)
          .mul(mul)
      )
    );

  return b
    .mul(-1)
    .add(b.pow(2).sub(c.mul(4)).squareRoot())
    .div(2);
}
