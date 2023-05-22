import { Contract } from 'ethers';
import { expect } from 'chai';
import Decimal from 'decimal.js';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { decimal, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe.only('FixedPoint', () => {
  let lib: Contract;

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

    it('multiplies large numbers correctly', async () => {
      const largeNumber = decimal('1e18');
      expectEqualWithError(
        await lib.mulDown(fp(largeNumber), fp(largeNumber)),
        fp(largeNumber.pow(2)),
        EXPECTED_RELATIVE_ERROR
      );
    });
  });

  describe('mulUp', () => {
    it('multiplies 0 and 0 correctly', async () => {
      expect(await lib.mulUp(fp(0), fp(0))).to.equal(fp(0));
    });

    it('multiplies 1 and 1 correctly', async () => {
      expect(await lib.mulUp(fp(1), fp(1))).to.equal(fp(1));
    });

    it('multiplies large numbers correctly', async () => {
      const largeNumber = decimal('1e18');
      expectEqualWithError(
        await lib.mulUp(fp(largeNumber), fp(largeNumber)),
        fp(largeNumber.pow(2)),
        EXPECTED_RELATIVE_ERROR
      );
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
      const largeNumber = decimal('1e18');
      expect(await lib.divDown(fp(largeNumber), fp(largeNumber))).to.equal(fp(1));
    });

    it('should revert on division by zero', async () => {
      // 0x12 (Division or modulo division by zero)
      await expect(lib.divDown(fp(1), fp(0))).to.be.revertedWithPanic('0x12');
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

    it('should revert on division by zero', async () => {
      await expect(lib.divUp(fp(1), fp(0))).to.be.revertedWithCustomError(lib,'ZeroDivision');
    });
  });

  describe('complement', () => {
    it('returns the correct complement for 0', async () => {
      expect(await lib.complement(fp(0))).to.equal(fp(1));
    });

    it('returns the correct complement for 1', async () => {
      expect(await lib.complement(fp(1))).to.equal(fp(0));
    });

    it('returns the correct complement for a number greater than 1', async () => {
      const value = decimal('2');
      expect(await lib.complement(fp(value))).to.equal(fp(0));
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
      expectEqualWithError(await lib.powDown(fp(2), fp(2)), fp(4), EXPECTED_RELATIVE_ERROR);
    });

    it('returns the correct power for large base and exponent', async () => {
      const base = decimal('1e18');
      const exponent = decimal('2');
      expectEqualWithError(await lib.powDown(fp(base), fp(exponent)), fp(base.pow(exponent)), EXPECTED_RELATIVE_ERROR);
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
      const exponent = decimal('2');
      expectEqualWithError(await lib.powUp(fp(base), fp(exponent)), fp(base.pow(exponent)), EXPECTED_RELATIVE_ERROR);
    });
  });
});
