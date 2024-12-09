import { expect } from 'chai';
import { Decimal } from 'decimal.js';
import { BigNumberish } from 'ethers';
import { bn, pct } from '../numbers';

export function expectEqualWithError(
  actual: BigNumberish,
  expected: BigNumberish,
  error: BigNumberish = 0.001,
  message?: string
): void {
  actual = bn(actual);
  expected = bn(expected);
  const acceptedError = pct(expected, error);

  if (actual >= 0) {
    expect(actual).to.be.at.least(expected - acceptedError, message);
    expect(actual).to.be.at.most(expected + acceptedError, message);
  } else {
    expect(actual).to.be.at.most(expected - acceptedError, message);
    expect(actual).to.be.at.least(expected + acceptedError, message);
  }
}

export function expectArrayEqualWithError(
  actual: Array<BigNumberish>,
  expected: Array<BigNumberish>,
  error: BigNumberish = 0.001,
  message?: string
): void {
  expect(actual.length).to.be.eq(expected.length);
  for (let i = 0; i < actual.length; i++) {
    expectEqualWithError(actual[i], expected[i], error, message);
  }
}

export function expectLessThanOrEqualWithError(
  actual: BigNumberish,
  expected: BigNumberish,
  error: BigNumberish = 0.001,
  message?: string
): void {
  actual = bn(actual);
  expected = bn(expected);
  const minimumValue = expected - pct(expected, error);

  expect(actual).to.be.at.most(expected, message);
  expect(actual).to.be.at.least(minimumValue, message);
}

export function expectRelativeError(actual: Decimal, expected: Decimal, maxRelativeError: Decimal): void {
  const lessThanOrEqualTo = actual.dividedBy(expected).sub(1).abs().lessThanOrEqualTo(maxRelativeError);
  expect(lessThanOrEqualTo, 'Relative error too big').to.be.true;
}
