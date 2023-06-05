import { Contract } from 'ethers';
import { expect } from 'chai';
import Decimal from 'decimal.js';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { decimal, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, ARITHMETIC_FLOW_PANIC, DIVISION_BY_ZERO_PANIC } from '@balancer-labs/v3-helpers/src/constants';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe('FixedPoint', () => {
  let lib: Contract;

  const ONE = fp(1);
  const TWO = fp(2);

  const EXPECTED_RELATIVE_ERROR = 1e-14;

  const valuesPow4 = [
    0.0007, 0.0022, 0.093, 2.9, 13.3, 450.8, 1550.3339, 69039.11, 7834839.432, 83202933.5433, 9983838318.4,
    15831567871.1,
  ];

  const valuesPow2 = [
    8e-9,
    0.0000013,
    0.000043,
    ...valuesPow4,
    8382392893832.1,
    38859321075205.1,
    decimal('848205610278492.2383'),
    decimal('371328129389320282.3783289'),
  ];

  const valuesPow1 = [
    1.7e-18,
    1.7e-15,
    1.7e-11,
    ...valuesPow2,
    decimal('701847104729761867823532.139'),
    decimal('175915239864219235419349070.947'),
  ];

  sharedBeforeEach('deploy lib', async () => {
    lib = await deploy('FixedPointMock', { args: [] });
  });

  const checkPow = async (x: Decimal, pow: number) => {
    const result = fp(x.pow(pow));
    expectEqualWithError(await lib.powDown(fp(x), fp(pow)), result, EXPECTED_RELATIVE_ERROR);
    expectEqualWithError(await lib.powUp(fp(x), fp(pow)), result, EXPECTED_RELATIVE_ERROR);
  };

  const checkPows = async (pow: number, values: (Decimal | number)[]) => {
    for (const value of values) {
      it(`handles ${value}`, async () => {
        await checkPow(decimal(value), pow);
      });
    }
  };

  describe('powUp/powDown', () => {
    context('non-fractional pow 1', () => {
      checkPows(1, valuesPow1);
    });

    context('non-fractional pow 2', async () => {
      checkPows(2, valuesPow2);
    });

    context('non-fractional pow 4', async () => {
      checkPows(4, valuesPow4);
    });
  });

  describe('mulDown', () => {
    it('multiplies 0 and 0 correctly', async () => {
      expect(await lib.mulDown(fp(0), fp(0))).to.equal(fp(0));
    });

    it('multiplies 1 and 1 correctly', async () => {
      expect(await lib.mulDown(fp(1), fp(1))).to.equal(fp(1));
    });

    it('returns product when both factors are not 0', async function () {
      expect(await lib.mulDown(ONE, fp(42))).to.equal(fp(42));
      expect(await lib.mulDown(fp(42), ONE)).to.equal(fp(42));
    });

    it('reverts on overflow', async function () {
      await expect(lib.mulDown(MAX_UINT256, TWO)).to.be.revertedWithPanic(ARITHMETIC_FLOW_PANIC);
    });
  });

  describe('mulUp', () => {
    it('multiplies 0 and 0 correctly', async () => {
      expect(await lib.mulUp(fp(0), fp(0))).to.equal(fp(0));
    });

    it('multiplies 1 and 1 correctly', async () => {
      expect(await lib.mulUp(fp(1), fp(1))).to.equal(fp(1));
    });

    it('reverts on overflow', async function () {
      await expect(lib.mulUp(MAX_UINT256, TWO)).to.be.revertedWithPanic(ARITHMETIC_FLOW_PANIC);
    });

    it('returns product when both factors are not 0', async function () {
      expect(await lib.mulUp(ONE, fp(42))).to.equal(fp(42));
      expect(await lib.mulUp(fp(42), ONE)).to.equal(fp(42));
    });
  });

  describe('divDown', () => {
    it('divides 0 by 1 correctly', async () => {
      expect(await lib.divDown(fp(0), fp(1))).to.equal(fp(0));
    });

    it('divides 1 by 1 correctly', async () => {
      expect(await lib.divDown(fp(1), fp(1))).to.equal(fp(1));
    });

    it('divides large number by itself correctly', async () => {
      const largeNumber = decimal('1e18').mul(Math.random());
      expect(await lib.divDown(fp(largeNumber), fp(largeNumber))).to.equal(fp(1));
    });

    it('reverts on underflow', async function () {
      await expect(lib.divDown(MAX_UINT256, ONE)).to.be.revertedWithPanic(ARITHMETIC_FLOW_PANIC);
    });

    it('should revert on division by zero', async () => {
      await expect(lib.divDown(fp(1), fp(0))).to.be.revertedWithPanic(DIVISION_BY_ZERO_PANIC);
    });
  });

  describe('divUp', () => {
    it('divides 0 by 1 correctly', async () => {
      expect(await lib.divUp(fp(0), fp(1))).to.equal(fp(0));
    });

    it('divides 1 by 1 correctly', async () => {
      expect(await lib.divUp(fp(1), fp(1))).to.equal(fp(1));
    });

    it('divides large number by itself correctly', async () => {
      const largeNumber = decimal('1e18');
      expect(await lib.divUp(fp(largeNumber), fp(largeNumber))).to.equal(fp(1));
    });

    it('returns quotient when divisor is not 0', async function () {
      expect(await lib.divUp(fp(42), ONE)).to.equal(fp(42));
    });

    it('should revert on division by zero', async () => {
      await expect(lib.divUp(fp(1), fp(0))).to.be.revertedWithCustomError(lib, 'ZeroDivision');
    });
  });

  describe('complement', () => {
    it('returns the correct complement for 0', async () => {
      expect(await lib.complement(fp(0))).to.equal(fp(1));
    });

    it('returns the correct complement for 0.3', async () => {
      expect(await lib.complement(fp(0.3))).to.equal(fp(0.7));
    });

    it('returns the correct complement for 1', async () => {
      expect(await lib.complement(fp(1))).to.equal(fp(0));
    });

    it('returns the correct complement for a number greater than 1', async () => {
      expect(await lib.complement(fp(2))).to.equal(fp(0));
    });
  });

  describe('powDown', () => {
    it('returns the correct power for base 0', async () => {
      expect(await lib.powDown(fp(0), fp(2))).to.equal(fp(0));
    });

    it('returns the correct power for base 1', async () => {
      expect(await lib.powDown(fp(1), fp(2))).to.equal(fp(1));
    });

    it('returns the correct power for base 2 power 2', async () => {
      expect(await lib.powDown(fp(2), fp(2))).to.equal(fp(4));
    });

    it('returns the correct power for base 2 power 4', async () => {
      expect(await lib.powDown(fp(2), fp(4))).to.equal(fp(16));
    });

    it('returns the correct power for large base and exponent', async () => {
      const base = decimal('1e18');
      const exponent = 3;
      // TODO: Precision seems to differ for powDow and powUp. Should check this.
      expectEqualWithError(await lib.powDown(fp(base), fp(exponent)), fp(base.pow(exponent)), 1e-13);
    });

    it('returns 0 when result is less than maxError', async function () {
      // These x and y values need to be found experimentally such that 0 < x^y < MAX_POW_RELATIVE_ERROR
      const x = 0;
      const y = 1;

      expect(await lib.powDown(x, y)).to.equal(0);
    });
  });

  describe('powUp', () => {
    it('returns the correct power for base 0', async () => {
      expect(await lib.powUp(fp(0), fp(2))).to.equal(fp(0));
    });

    it('returns the correct power for base 1', async () => {
      expect(await lib.powUp(fp(1), fp(2))).to.equal(fp(1));
    });

    it('returns the correct power for base 2 power 2', async () => {
      expectEqualWithError(await lib.powUp(fp(2), fp(2)), fp(4), EXPECTED_RELATIVE_ERROR);
    });

    it('returns the correct power for large base and exponent', async () => {
      const base = decimal('1e18');
      const exponent = 3;
      expectEqualWithError(await lib.powUp(fp(base), fp(exponent)), fp(base.pow(exponent)), EXPECTED_RELATIVE_ERROR);
    });
  });
});
