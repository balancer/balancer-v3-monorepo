import { Decimal } from 'decimal.js';
import { BigNumberish } from 'ethers';

import _BN from 'bn.js';

const SCALING_FACTOR = 1e18;

export const decimal = (x: BigNumberish | Decimal): Decimal => new Decimal(x.toString());

export const fp = (x: BigNumberish | Decimal): bigint => bn(toFp(x));

export const toFp = (x: BigNumberish | Decimal): Decimal => decimal(x).mul(SCALING_FACTOR);

export const fromFp = (x: BigNumberish | Decimal): Decimal => decimal(x).div(SCALING_FACTOR);

export const bn = (x: BigNumberish | Decimal): bigint => {
  if (typeof x === 'bigint') return x;
  const stringified = parseScientific(x.toString());
  const integer = stringified.split('.')[0];
  return BigInt(integer);
};

export const negate = (x: BigNumberish): bigint => {
  // Ethers does not expose the .notn function from bn.js, so we must use it ourselves
  return bn(new _BN(bn(x).toString()).notn(256).toString());
};

export const maxUint = (e: number): bigint => 2n ** bn(e) - 1n;

export const maxInt = (e: number): bigint => 2n ** bn(e - 1) - 1n;

export const minInt = (e: number): bigint => 2n ** bn(e - 1) * -1n;

export const pct = (x: BigNumberish, pct: BigNumberish): bigint => bn(decimal(x).mul(decimal(pct)));

export const max = (a: BigNumberish, b: BigNumberish): bigint => {
  a = bn(a);
  b = bn(b);

  return a > b ? a : b;
};

export const min = (a: BigNumberish, b: BigNumberish): bigint => {
  a = bn(a);
  b = bn(b);

  return a < b ? a : b;
};

export const bnSum = (bnArr: BigNumberish[]): bigint => {
  return bn(bnArr.reduce((prev, curr) => bn(prev) + bn(curr), 0));
};

export const arrayAdd = (arrA: BigNumberish[], arrB: BigNumberish[]): bigint[] =>
  arrA.map((a, i) => bn(a) + bn(arrB[i]));

export const arrayFpMulDown = (arrA: BigNumberish[], arrB: BigNumberish[]): bigint[] =>
  arrA.map((a, i) => fpMulDown(a, arrB[i]));

export const arraySub = (arrA: BigNumberish[], arrB: BigNumberish[]): bigint[] =>
  arrA.map((a, i) => bn(a) - bn(arrB[i]));

export const fpMulDown = (a: BigNumberish, b: BigNumberish): bigint => (bn(a) * bn(b)) / FP_SCALING_FACTOR;

export const fpDivDown = (a: BigNumberish, b: BigNumberish): bigint => (bn(a) * FP_SCALING_FACTOR) / bn(b);

export const fpDivUp = (a: BigNumberish, b: BigNumberish): bigint => fpMulDivUp(bn(a), FP_SCALING_FACTOR, bn(b));

export const fpMulUp = (a: BigNumberish, b: BigNumberish): bigint => fpMulDivUp(bn(a), bn(b), FP_SCALING_FACTOR);

export const fpMulDivUp = (a: bigint, b: bigint, c: bigint) => {
  const product = a * b;
  return product === 0n ? 0n : (product - 1n) / c + 1n;
};

// ceil(x/y) == (x + y - 1) / y
export const divCeil = (x: bigint, y: bigint): bigint => (x + y - 1n) / y;

const FP_SCALING_FACTOR = bn(SCALING_FACTOR);
export const FP_ZERO = fp(0);
export const FP_ONE = fp(1);
export const FP_100_PCT = fp(1);

export function printGas(gas: number | bigint): string {
  if (typeof gas !== 'number') {
    gas = Number(gas);
  }

  return `${(gas / 1000).toFixed(1)}k`;
}

export function scaleUp(n: bigint, scalingFactor: bigint): bigint {
  if (scalingFactor == bn(1)) {
    return n;
  }

  return n * scalingFactor;
}

export function scaleDown(n: bigint, scalingFactor: bigint): bigint {
  if (scalingFactor == bn(1)) {
    return n;
  }

  return n / scalingFactor;
}

function parseScientific(num: string): string {
  // If the number is not in scientific notation return it as it is
  if (!/\d+\.?\d*e[+-]*\d+/i.test(num)) return num;

  // Remove the sign
  const numberSign = Math.sign(Number(num));
  num = Math.abs(Number(num)).toString();

  // Parse into coefficient and exponent
  const [coefficient, exponent] = num.toLowerCase().split('e');
  let zeros = Math.abs(Number(exponent));
  const exponentSign = Math.sign(Number(exponent));
  const [integer, decimals] = (coefficient.indexOf('.') != -1 ? coefficient : `${coefficient}.`).split('.');

  if (exponentSign === -1) {
    zeros -= integer.length;
    num =
      zeros < 0
        ? integer.slice(0, zeros) + '.' + integer.slice(zeros) + decimals
        : '0.' + '0'.repeat(zeros) + integer + decimals;
  } else {
    if (decimals) zeros -= decimals.length;
    num =
      zeros < 0
        ? integer + decimals.slice(0, zeros) + '.' + decimals.slice(zeros)
        : integer + decimals + '0'.repeat(zeros);
  }

  return numberSign < 0 ? '-' + num : num;
}

export function randomFromInterval(min: number, max: number): number {
  // min and max included
  return Math.random() * (max - min) + min;
}

export function isBn(n: unknown): boolean {
  return typeof n === 'bigint';
}
