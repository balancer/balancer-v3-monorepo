import { BigNumberish } from 'ethers';
import { AsyncFunc } from 'mocha';
import chai, { expect } from 'chai';

import { NAry } from '@balancer-labs/v3-helpers/src/models/types/types';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { bn, fp, isBn } from '@balancer-labs/v3-helpers/src/numbers';
import { expectEqualWithError, expectLessThanOrEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';

import { sharedBeforeEach } from './sharedBeforeEach';

/* eslint-disable @typescript-eslint/ban-ts-comment */
/* eslint-disable @typescript-eslint/no-explicit-any */

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  export namespace Chai {
    interface Assertion {
      zero: void;
      zeros: void;
      zeroAddress: void;
      equalFp(value: BigNumberish): void;
      lteWithError(value: NAry<BigNumberish>, error: BigNumberish): void;
      equalWithError(value: NAry<BigNumberish>, error: BigNumberish): void;
      almostEqual(value: NAry<BigNumberish>, error?: BigNumberish, message?: string): void;
      almostEqualFp(value: NAry<BigNumberish>, error?: BigNumberish): void;
    }
  }

  function sharedBeforeEach(fn: AsyncFunc): void;
  function sharedBeforeEach(name: string, fn: AsyncFunc): void;
}

global.sharedBeforeEach = (nameOrFn: string | AsyncFunc, maybeFn?: AsyncFunc): void => {
  sharedBeforeEach(nameOrFn, maybeFn);
};

chai.use(function (chai, utils) {
  const { Assertion } = chai;

  Assertion.addProperty('zero', function () {
    new Assertion(this._obj).to.be.equal(bn(0));
  });

  Assertion.addProperty('zeros', function () {
    const obj = this._obj;
    const expectedValue = Array(obj.length).fill(bn(0));
    new Assertion(obj).to.be.deep.equal(expectedValue);
  });

  Assertion.addProperty('zeroAddress', function () {
    new Assertion(this._obj).to.be.equal(ZERO_ADDRESS);
  });

  Assertion.addMethod('equalFp', function (expectedValue: BigNumberish) {
    expect(this._obj).to.be.equal(fp(expectedValue));
  });

  Assertion.addMethod('equalWithError', function (expectedValue: NAry<BigNumberish>, error: BigNumberish) {
    if (Array.isArray(expectedValue)) {
      const actual: BigNumberish[] = this._obj;
      actual.forEach((actual, i) => expectEqualWithError(actual, expectedValue[i], error));
    } else {
      expectEqualWithError(this._obj, expectedValue, error);
    }
  });

  Assertion.addMethod('lteWithError', function (expectedValue: NAry<BigNumberish>, error: BigNumberish) {
    if (Array.isArray(expectedValue)) {
      const actual: BigNumberish[] = this._obj;
      actual.forEach((actual, i) => expectLessThanOrEqualWithError(actual, expectedValue[i], error));
    } else {
      expectLessThanOrEqualWithError(this._obj, expectedValue, error);
    }
  });

  Assertion.addMethod(
    'almostEqual',
    function (expectedValue: NAry<BigNumberish>, error?: BigNumberish, message?: string) {
      if (Array.isArray(expectedValue)) {
        const actuals: BigNumberish[] = this._obj;
        actuals.forEach((actual, i) => expectEqualWithError(actual, expectedValue[i], error, message));
      } else {
        expectEqualWithError(this._obj, expectedValue, error, message);
      }
    }
  );

  Assertion.addMethod(
    'almostEqualFp',
    function (expectedValue: NAry<BigNumberish>, error?: BigNumberish, message?: string) {
      if (Array.isArray(expectedValue)) {
        const actuals: BigNumberish[] = this._obj;
        actuals.forEach((actual, i) => expectEqualWithError(actual, fp(expectedValue[i]), error, message));
      } else {
        expectEqualWithError(this._obj, fp(expectedValue), error, message);
      }
    }
  );

  ['eq', 'equal', 'equals'].forEach((fn: string) => {
    Assertion.overwriteMethod(fn, function (_super) {
      return function (this: any, expected: any) {
        const actual = utils.flag(this, 'object');
        if (
          utils.flag(this, 'deep') &&
          Array.isArray(actual) &&
          Array.isArray(expected) &&
          actual.length === expected.length &&
          (actual.some((v) => isBn(v)) || expected.some((v) => isBn(v)))
        ) {
          const equal = actual.every((value: any, i: number) => bn(value) == expected[i]);
          this.assert(
            equal,
            `Expected "[${expected}]" to be deeply equal [${actual}]`,
            `Expected "[${expected}]" NOT to be deeply equal [${actual}]`,
            expected,
            actual
          );
        } else {
          // eslint-disable-next-line prefer-rest-params
          _super.apply(this, arguments);
        }
      };
    });
  });
});
