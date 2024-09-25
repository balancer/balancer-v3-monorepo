import { Contract, BigNumberish } from 'ethers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { random } from 'lodash';
import {
  calculateInvariant,
  calculateAnalyticalInvariantForTwoTokens,
  getTokenBalanceGivenInvariantAndAllOtherBalances,
  calcInGivenExactOut,
  calcOutGivenExactIn,
} from '@balancer-labs/v3-helpers/src/math/stable';

const MAX_RELATIVE_ERROR = 0.0001; // Max relative error

// TODO: Test this math by checking extremes values for the amplification field (0 and infinite)
// to verify that it equals constant sum and constant product (weighted) invariants.

describe('StableMath', function () {
  let mock: Contract;

  const AMP_PRECISION = bn(1e3);
  const MAX_TOKENS = 5;

  before(async function () {
    mock = await deploy('StableMathMock');
  });

  context('invariant', () => {
    async function checkInvariant(balances: bigint[], amp: number): Promise<void> {
      const ampParameter = bn(amp) * AMP_PRECISION;

      const actualInvariant = await mock.computeInvariant(ampParameter, balances);
      const expectedInvariant = calculateInvariant(balances, amp);

      expectEqualWithError(actualInvariant, expectedInvariant, MAX_RELATIVE_ERROR);
    }

    context('check over a range of inputs', () => {
      for (let numTokens = 2; numTokens <= MAX_TOKENS; numTokens++) {
        const balances = Array.from({ length: numTokens }, () => random(250, 350)).map(fp);

        it(`computes the invariant for ${numTokens} tokens`, async () => {
          for (let amp = 100; amp <= 5000; amp += 100) {
            await checkInvariant(balances, amp);
          }
        });
      }
    });

    context('two tokens', () => {
      it('invariant equals analytical solution', async () => {
        const amp = bn(100);
        const balances = [fp(10), fp(12)];

        const result = await mock.computeInvariant(amp * AMP_PRECISION, balances);
        const expectedInvariant = calculateAnalyticalInvariantForTwoTokens(balances, amp);

        expectEqualWithError(result, expectedInvariant, MAX_RELATIVE_ERROR);
      });
    });

    it('still converges at extreme values', async () => {
      const amp = bn(1);
      const balances = [fp(0.00000001), fp(1200000000), fp(300)];

      const result = await mock.computeInvariant(amp * AMP_PRECISION, balances);
      const expectedInvariant = calculateInvariant(balances, amp);

      expectEqualWithError(result, expectedInvariant, MAX_RELATIVE_ERROR);
    });
  });

  context('token balance given invariant and other balances', () => {
    async function checkTokenBalanceGivenInvariant(
      balances: BigNumberish[],
      invariant: BigNumberish,
      amp: number,
      tokenIndex: number
    ): Promise<void> {
      const ampParameter = bn(amp) * AMP_PRECISION;

      const actualTokenBalance = await mock.computeBalance(ampParameter, balances, invariant, tokenIndex);

      // Note this function takes the decimal amp (unadjusted).
      const expectedTokenBalance = getTokenBalanceGivenInvariantAndAllOtherBalances(
        amp,
        balances,
        invariant,
        tokenIndex
      );

      expectEqualWithError(actualTokenBalance, expectedTokenBalance, MAX_RELATIVE_ERROR);
    }

    context('check over a range of inputs', () => {
      for (let numTokens = 2; numTokens <= MAX_TOKENS; numTokens++) {
        const balances = Array.from({ length: numTokens }, () => random(250, 350)).map(fp);

        it(`computes the token balance for ${numTokens} tokens`, async () => {
          for (let amp = 100; amp <= 5000; amp += 100) {
            const currentInvariant = calculateInvariant(balances, amp);

            // mutate the balances
            for (let tokenIndex = 0; tokenIndex < numTokens; tokenIndex++) {
              const newBalances: BigNumberish[] = Object.assign([], balances);
              newBalances[tokenIndex] = newBalances[tokenIndex] + fp(100);

              await checkTokenBalanceGivenInvariant(newBalances, currentInvariant, amp, tokenIndex);
            }
          }
        });
      }
    });
  });

  context('in given exact out', () => {
    context('two tokens', () => {
      it('returns in given exact out', async () => {
        const amp = bn(100);
        const balances = Array.from({ length: 2 }, () => random(8, 12)).map(fp);
        const tokenIndexIn = 0;
        const tokenIndexOut = 1;
        const amountOut = fp(1);
        const invariant = calculateInvariant(balances, amp);

        const result = await mock.computeInGivenExactOut(
          amp * AMP_PRECISION,
          balances,
          tokenIndexIn,
          tokenIndexOut,
          amountOut,
          invariant
        );
        const expectedAmountIn = calcInGivenExactOut(balances, amp, tokenIndexIn, tokenIndexOut, amountOut);

        expectEqualWithError(result, bn(expectedAmountIn.toFixed(0)), MAX_RELATIVE_ERROR);
      });
    });
    context('three tokens', () => {
      it('returns in given exact out', async () => {
        const amp = bn(100);
        const balances = Array.from({ length: 3 }, () => random(10, 14)).map(fp);
        const tokenIndexIn = 0;
        const tokenIndexOut = 1;
        const amountOut = fp(1);
        const invariant = calculateInvariant(balances, amp);

        const result = await mock.computeInGivenExactOut(
          amp * AMP_PRECISION,
          balances,
          tokenIndexIn,
          tokenIndexOut,
          amountOut,
          invariant
        );
        const expectedAmountIn = calcInGivenExactOut(balances, amp, tokenIndexIn, tokenIndexOut, amountOut);

        expectEqualWithError(result, bn(expectedAmountIn.toFixed(0)), MAX_RELATIVE_ERROR);
      });
    });
  });

  context('out given exact in', () => {
    context('two tokens', () => {
      it('returns out given exact in', async () => {
        const amp = bn(10);
        const balances = Array.from({ length: 2 }, () => random(10, 12)).map(fp);
        const tokenIndexIn = 0;
        const tokenIndexOut = 1;
        const amountIn = fp(1);
        const invariant = calculateInvariant(balances, amp);

        const result = await mock.computeOutGivenExactIn(
          amp * AMP_PRECISION,
          balances,
          tokenIndexIn,
          tokenIndexOut,
          amountIn,
          invariant
        );
        const expectedAmountOut = calcOutGivenExactIn(balances, amp, tokenIndexIn, tokenIndexOut, amountIn);

        expectEqualWithError(result, bn(expectedAmountOut.toFixed(0)), MAX_RELATIVE_ERROR);
      });
    });
    context('three tokens', () => {
      it('returns out given exact in', async () => {
        const amp = bn(10);
        const balances = Array.from({ length: 3 }, () => random(10, 14)).map(fp);
        const tokenIndexIn = 0;
        const tokenIndexOut = 1;
        const amountIn = fp(1);
        const invariant = calculateInvariant(balances, amp);

        const result = await mock.computeOutGivenExactIn(
          amp * AMP_PRECISION,
          balances,
          tokenIndexIn,
          tokenIndexOut,
          amountIn,
          invariant
        );
        const expectedAmountOut = calcOutGivenExactIn(balances, amp, tokenIndexIn, tokenIndexOut, amountIn);

        expectEqualWithError(result, bn(expectedAmountOut.toFixed(0)), MAX_RELATIVE_ERROR);
      });
    });
  });
});
