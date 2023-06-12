import { expect } from 'chai';
import { Contract } from 'ethers';

import { fp, FP_ONE } from '@balancer-labs/v3-helpers/src/numbers';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';

describe('ExpLog', () => {
  let lib: Contract;

  const MAX_X = 2n ** 255n - 1n;
  const MAX_Y = 2n ** 254n / 10n ** 20n - 1n;
  const LN_36_LOWER_BOUND = FP_ONE - fp(0.1);
  const LN_36_UPPER_BOUND = FP_ONE + fp(0.1);
  const MIN_NATURAL_EXPONENT = fp(-41);
  const MAX_NATURAL_EXPONENT = fp(130);
  const EXPECTED_RELATIVE_ERROR = 1e-14;

  sharedBeforeEach('deploy lib', async () => {
    lib = await deploy('LogExpMathMock', { args: [] });
  });

  describe('pow', () => {
    describe('exponent zero', () => {
      const exponent = 0;

      it('handles base zero', async () => {
        const base = 0;

        expect(await lib.pow(base, exponent)).to.be.equal(FP_ONE);
      });

      it('handles base one', async () => {
        const base = 1;

        expect(await lib.pow(base, exponent)).to.be.equal(FP_ONE);
      });

      it('handles base greater than one', async () => {
        const base = 10;

        expect(await lib.pow(base, exponent)).to.be.equal(FP_ONE);
      });
    });

    describe('base zero', () => {
      const base = 0;

      it('handles exponent zero', async () => {
        const exponent = 0;

        expect(await lib.pow(base, exponent)).to.be.equal(FP_ONE);
      });

      it('handles exponent one', async () => {
        const exponent = 1;
        const expectedResult = 0;

        expect(await lib.pow(base, exponent)).to.be.equal(expectedResult);
      });

      it('handles exponent greater than one', async () => {
        const exponent = 10;
        const expectedResult = 0;

        expect(await lib.pow(base, exponent)).to.be.equal(expectedResult);
      });
    });

    describe('base one', () => {
      const base = 1;

      it('handles exponent zero', async () => {
        const exponent = 0;

        expect(await lib.pow(base, exponent)).to.be.equal(FP_ONE);
      });

      it('handles exponent one', async () => {
        const exponent = 1;

        expectEqualWithError(await lib.pow(base, exponent), FP_ONE, EXPECTED_RELATIVE_ERROR);
      });

      it('handles exponent greater than one', async () => {
        const exponent = 10;

        expectEqualWithError(await lib.pow(base, exponent), FP_ONE, EXPECTED_RELATIVE_ERROR);
      });
    });

    describe('base and exponent greater than one', () => {
      it('handles base and exponent greater than one', async () => {
        const base = fp(2);
        const exponent = fp(2);
        const expectedResult = fp(4);

        expectEqualWithError(await lib.pow(base, exponent), expectedResult, EXPECTED_RELATIVE_ERROR);
      });
    });

    describe('x between LN_36_LOWER_BOUND and LN_36_UPPER_BOUND', () => {
      it('handles x in the specific range properly', async () => {
        const base = (LN_36_LOWER_BOUND + LN_36_UPPER_BOUND) / 2n;

        // Choose an arbitrary exponent, like 2
        const exponent = 2;

        // 1^2 == 1
        expect(await lib.pow(base, exponent)).to.be.equal(FP_ONE);
      });
    });

    describe('exponent as decimal', () => {
      it('handles decimals properly', async () => {
        const base = fp(2);
        const exponent = fp(0.5);
        const expectedResult = fp(Math.sqrt(2));

        const result = await lib.pow(base, exponent);
        expectEqualWithError(result, expectedResult, EXPECTED_RELATIVE_ERROR);
      });
    });

    describe('decimals', () => {
      it('handles decimals properly', async () => {
        const base = fp(2);
        const exponent = fp(4);
        const expectedResult = fp(Math.pow(2, 4));

        const result = await lib.pow(base, exponent);
        expectEqualWithError(result, expectedResult, EXPECTED_RELATIVE_ERROR);
      });
    });

    describe('max values', () => {
      it('cannot handle a product when logx_times_y > MAX_NATURAL_EXPONENT', async () => {
        const base = 2n ** 254n;
        const exponent = 10n ** 20n;

        await expect(lib.pow(base, exponent)).to.be.revertedWithCustomError(lib, 'ProductOutOfBounds');
      });

      it('cannot handle a product when logx_times_y < MIN_NATURAL_EXPONENT', async () => {
        const base = 1;
        const exponent = 10n ** 20n;

        await expect(lib.pow(base, exponent)).to.be.revertedWithCustomError(lib, 'ProductOutOfBounds');
      });

      it('cannot handle a base greater than 2^255 - 1', async () => {
        const base = MAX_X + 1n;
        const exponent = 1;

        await expect(lib.pow(base, exponent)).to.be.revertedWithCustomError(lib, 'BaseOutOfBounds');
      });

      it('cannot handle an exponent greater than (2^254/1e20) - 1', async () => {
        const base = 1;
        const exponent = MAX_Y + 1n;

        await expect(lib.pow(base, exponent)).to.be.revertedWithCustomError(lib, 'ExponentOutOfBounds');
      });
    });
  });

  describe('exp', () => {
    it('handles zero', async () => {
      const x = 0;

      expect(await lib.exp(x)).to.be.equal(FP_ONE);
    });

    it('handles one', async () => {
      const x = fp(1);
      const expectedResult = fp(Math.E); // Since e^1 = e

      expectEqualWithError(await lib.exp(x), expectedResult, EXPECTED_RELATIVE_ERROR);
    });

    it('handles negative input', async () => {
      const x = fp(-1);
      const expectedResult = fp(1 / Math.E); // Since e^-1 = 1/e

      expectEqualWithError(await lib.exp(x), expectedResult, EXPECTED_RELATIVE_ERROR);
    });

    it('handles large positive input within the defined bounds', async () => {
      expectEqualWithError(
        await lib.exp(MAX_NATURAL_EXPONENT),
        fp(Math.exp(Number(MAX_NATURAL_EXPONENT / FP_ONE))),
        EXPECTED_RELATIVE_ERROR
      );
    });

    it('handles large negative input within the defined bounds', async () => {
      expectEqualWithError(
        await lib.exp(MIN_NATURAL_EXPONENT),
        fp(Math.exp(Number(MIN_NATURAL_EXPONENT / FP_ONE))),
        EXPECTED_RELATIVE_ERROR
      );
    });

    it('cannot handle input larger than MAX_NATURAL_EXPONENT', async () => {
      const x = MAX_NATURAL_EXPONENT + 1n;

      await expect(lib.exp(x)).to.be.revertedWithCustomError(lib, 'InvalidExponent');
    });

    it('cannot handle input smaller than MIN_NATURAL_EXPONENT', async () => {
      const x = MIN_NATURAL_EXPONENT - 1n;

      await expect(lib.exp(x)).to.be.revertedWithCustomError(lib, 'InvalidExponent');
    });
  });

  describe('log', () => {
    it('handles log base e (ln)', async () => {
      const arg = fp(10);
      const base = fp(Math.E);

      const expectedResult = fp(Math.log(10));

      expectEqualWithError(await lib.log(arg, base), expectedResult, EXPECTED_RELATIVE_ERROR);
    });

    it('handles log base 10', async () => {
      const arg = fp(100);
      const base = fp(10);

      const expectedResult = fp(Math.log10(100));

      expectEqualWithError(await lib.log(arg, base), expectedResult, EXPECTED_RELATIVE_ERROR);
    });

    it('handles arg within LN_36_LOWER_BOUND bounds', async () => {
      const arg = LN_36_LOWER_BOUND + 1n;
      const base = fp(10);

      expectEqualWithError(await lib.log(arg, base), fp(Math.log10(0.9)), EXPECTED_RELATIVE_ERROR);
    });

    it('handles base within LN_36_LOWER_BOUND bounds', async () => {
      const arg = fp(100);
      const base = LN_36_LOWER_BOUND + 1n;

      expectEqualWithError(await lib.log(arg, base), fp(Math.log(100) / Math.log(0.9)), EXPECTED_RELATIVE_ERROR);
    });

    it('handles arg larger than LN_36_UPPER_BOUND', async () => {
      const arg = LN_36_UPPER_BOUND + 1n;
      const base = fp(10);

      expectEqualWithError(await lib.log(arg, base), fp(Math.log10(1.1)), EXPECTED_RELATIVE_ERROR);
    });

    it('handles base larger than LN_36_UPPER_BOUND', async () => {
      const arg = fp(100);
      const base = LN_36_UPPER_BOUND + 1n;

      expectEqualWithError(await lib.log(arg, base), fp(Math.log(100) / Math.log(1.1)), EXPECTED_RELATIVE_ERROR);
    });
  });

  describe('ln', () => {
    it('handles ln of e', async () => {
      const a = fp(Math.E);

      const expectedResult = fp(Math.log(Math.E));

      expectEqualWithError(await lib.ln(a), expectedResult, EXPECTED_RELATIVE_ERROR);
    });

    it('handles ln of 1', async () => {
      const a = FP_ONE;

      const expectedResult = 0; // ln(1) is 0

      expectEqualWithError(await lib.ln(a), expectedResult, EXPECTED_RELATIVE_ERROR);
    });

    it('handles input within LN_36 bounds', async () => {
      const a = LN_36_LOWER_BOUND + 1n;

      expectEqualWithError(await lib.ln(a), fp(Math.log(0.9)), EXPECTED_RELATIVE_ERROR);
    });

    it('handles input larger than LN_36_UPPER_BOUND', async () => {
      const a = LN_36_UPPER_BOUND + 1n;

      expectEqualWithError(await lib.ln(a), fp(Math.log(1.1)), EXPECTED_RELATIVE_ERROR);
    });

    it('handles input equal to a3 * ONE_18', async () => {
      // eslint-disable-next-line @typescript-eslint/no-loss-of-precision
      const a3 = 888611052050787263676000000;
      const a = fp(a3);

      expectEqualWithError(await lib.ln(a), fp(Math.log(a3)), EXPECTED_RELATIVE_ERROR);
    });

    it('handles input equal to a1 * ONE_18', async () => {
      // eslint-disable-next-line @typescript-eslint/no-loss-of-precision
      const a1 = 6235149080811616882910000000;
      const a = fp(a1);

      expectEqualWithError(await lib.ln(a), fp(Math.log(a1)), EXPECTED_RELATIVE_ERROR);
    });

    it('throws OutOfBounds error for zero', async () => {
      const a = 0;

      await expect(lib.ln(a)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
    });

    it('throws OutOfBounds error for negative number', async () => {
      const a = -1;

      await expect(lib.ln(a)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
    });
  });
});
