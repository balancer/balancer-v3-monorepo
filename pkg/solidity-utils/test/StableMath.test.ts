import { Contract, BigNumberish } from 'ethers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { random } from 'lodash';
import { expect } from 'chai';
import {
  calculateInvariant,
  calculateAnalyticalInvariantForTwoTokens,
  getTokenBalanceGivenInvariantAndAllOtherBalances,
  calcInGivenExactOut,
  calcOutGivenExactIn,
  calcBptOutGivenExactTokensIn,
  calcTokenInGivenExactBptOut,
  calcTokenOutGivenExactBptIn,
  calcBptInGivenExactTokensOut,
} from '@balancer-labs/v3-helpers/src/math/stable';

const MAX_RELATIVE_ERROR = 0.0001; // Max relative error

// TODO: Test this math by checking extremes values for the amplification field (0 and infinite)
// to verify that it equals constant sum and constant product (weighted) invariants.

describe('StableMath', function () {
  let mock: Contract;

  const AMP_PRECISION = bn(1e3);
  const MAX_TOKENS = 4;

  before(async function () {
    mock = await deploy('StableMathMock');
  });

  context('invariant', () => {
    async function checkInvariant(balances: bigint[], amp: number): Promise<void> {
      const ampParameter = bn(amp) * AMP_PRECISION;

      const actualInvariant = await mock.calculateInvariant(ampParameter, balances);
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

        const result = await mock.calculateInvariant(amp * AMP_PRECISION, balances);
        const expectedInvariant = calculateAnalyticalInvariantForTwoTokens(balances, amp);

        expectEqualWithError(result, expectedInvariant, MAX_RELATIVE_ERROR);
      });
    });

    it('still converges at extreme values', async () => {
      const amp = bn(1);
      const balances = [fp(0.00000001), fp(1200000000), fp(300)];

      const result = await mock.calculateInvariant(amp * AMP_PRECISION, balances);
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

      const actualTokenBalance = await mock.getTokenBalanceGivenInvariantAndAllOtherBalances(
        ampParameter,
        balances,
        invariant,
        tokenIndex
      );

      // Note this function takes the decimal amp (unadjusted)
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

        const result = await mock.inGivenExactOut(
          amp * AMP_PRECISION,
          balances,
          tokenIndexIn,
          tokenIndexOut,
          amountOut
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

        const result = await mock.inGivenExactOut(
          amp * AMP_PRECISION,
          balances,
          tokenIndexIn,
          tokenIndexOut,
          amountOut
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

        const result = await mock.outGivenExactIn(amp * AMP_PRECISION, balances, tokenIndexIn, tokenIndexOut, amountIn);
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

        const result = await mock.outGivenExactIn(amp * AMP_PRECISION, balances, tokenIndexIn, tokenIndexOut, amountIn);
        const expectedAmountOut = calcOutGivenExactIn(balances, amp, tokenIndexIn, tokenIndexOut, amountIn);

        expectEqualWithError(result, bn(expectedAmountOut.toFixed(0)), MAX_RELATIVE_ERROR);
      });
    });
  });

  context('BPT out given exact tokens in', () => {
    const SWAP_FEE = fp(0.022);

    async function checkBptOutGivenTokensIn(
      amp: number,
      balances: BigNumberish[],
      amountsIn: BigNumberish[],
      bptTotalSupply: BigNumberish,
      swapFee: BigNumberish
    ): Promise<void> {
      const ampParameter = bn(amp) * AMP_PRECISION;
      const currentInvariant = calculateInvariant(balances, amp);

      const actualBptOut = await mock.exactTokensInForBPTOut(
        ampParameter,
        balances,
        amountsIn,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      const expectedBptOut = calcBptOutGivenExactTokensIn(
        balances,
        amp,
        amountsIn,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      expect(actualBptOut).gt(0);
      expectEqualWithError(actualBptOut, expectedBptOut, MAX_RELATIVE_ERROR);
    }

    context('check over a range of inputs', () => {
      for (let numTokens = 2; numTokens <= MAX_TOKENS; numTokens++) {
        const balances: bigint[] = Array.from({ length: numTokens }, () => random(250, 350)).map(fp);
        const totalSupply = balances.reduce((sum, current) => {
          return sum + current;
        });
        const amountsIn = Array.from({ length: numTokens }, () => random(0, 50)).map(fp);

        it(`computes the bptOut for ${numTokens} tokens`, async () => {
          for (let amp = 100; amp <= 5000; amp += 100) {
            await checkBptOutGivenTokensIn(amp, balances, amountsIn, totalSupply, SWAP_FEE);
          }
        });
      }
    });
  });

  context('token in given exact BPT out', () => {
    const SWAP_FEE = fp(0.012);

    async function checkTokenInGivenBptOut(
      amp: number,
      balances: BigNumberish[],
      tokenIndex: number,
      bptAmountOut: BigNumberish,
      bptTotalSupply: BigNumberish,
      currentInvariant: BigNumberish,
      swapFee: BigNumberish
    ): Promise<void> {
      const ampParameter = bn(amp) * AMP_PRECISION;

      const actualTokenIn = await mock.tokenInForExactBPTOut(
        ampParameter,
        balances,
        tokenIndex,
        bptAmountOut,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      const expectedTokenIn = calcTokenInGivenExactBptOut(
        tokenIndex,
        balances,
        amp,
        bptAmountOut,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      expect(actualTokenIn).gt(0);
      expectEqualWithError(actualTokenIn, expectedTokenIn, MAX_RELATIVE_ERROR);
    }

    context('check over a range of inputs', () => {
      const bptAmountOut = fp(1);

      for (let numTokens = 2; numTokens <= MAX_TOKENS; numTokens++) {
        const balances: bigint[] = Array.from({ length: numTokens }, () => random(250, 350)).map(fp);
        const totalSupply = balances.reduce((sum, current) => {
          return sum + current;
        });

        it(`computes the token in for ${numTokens} tokens`, async () => {
          for (let amp = 100; amp <= 5000; amp += 100) {
            const currentInvariant = calculateInvariant(balances, amp);

            for (let tokenIndex = 0; tokenIndex < numTokens; tokenIndex++) {
              await checkTokenInGivenBptOut(
                amp,
                balances,
                tokenIndex,
                bptAmountOut,
                totalSupply,
                currentInvariant,
                SWAP_FEE
              );
            }
          }
        });
      }
    });
  });

  context('BPT in given exact tokens out', () => {
    const SWAP_FEE = fp(0.038);

    async function checkBptInGivenTokensOut(
      amp: number,
      balances: BigNumberish[],
      amountsOut: BigNumberish[],
      bptTotalSupply: BigNumberish,
      currentInvariant: BigNumberish,
      swapFee: BigNumberish
    ): Promise<void> {
      const ampParameter = bn(amp) * AMP_PRECISION;

      const actualBptIn = await mock.bptInForExactTokensOut(
        ampParameter,
        balances,
        amountsOut,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      const expectedBptIn = calcBptInGivenExactTokensOut(
        balances,
        amp,
        amountsOut,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      expect(actualBptIn).gt(0);
      expectEqualWithError(actualBptIn, expectedBptIn, MAX_RELATIVE_ERROR);
    }

    context('check over a range of inputs', () => {
      for (let numTokens = 2; numTokens <= MAX_TOKENS; numTokens++) {
        const balances: bigint[] = Array.from({ length: numTokens }, () => random(250, 350)).map(fp);
        const totalSupply = balances.reduce((sum, current) => {
          return sum + current;
        });
        const amountsOut = Array.from({ length: numTokens }, () => random(0, 50)).map(fp);

        it(`computes the bptOut for ${numTokens} tokens`, async () => {
          for (let amp = 100; amp <= 5000; amp += 100) {
            const currentInvariant = calculateInvariant(balances, amp);

            await checkBptInGivenTokensOut(amp, balances, amountsOut, totalSupply, currentInvariant, SWAP_FEE);
          }
        });
      }
    });
  });

  context('token out given exact BPT in', () => {
    const SWAP_FEE = fp(0.012);

    async function checkTokenOutGivenBptIn(
      amp: number,
      balances: BigNumberish[],
      tokenIndex: number,
      bptAmountIn: BigNumberish,
      bptTotalSupply: BigNumberish,
      currentInvariant: BigNumberish,
      swapFee: BigNumberish
    ): Promise<void> {
      const ampParameter = bn(amp) * AMP_PRECISION;

      const actualTokenOut = await mock.exactBPTInForTokenOut(
        ampParameter,
        balances,
        tokenIndex,
        bptAmountIn,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      const expectedTokenOut = calcTokenOutGivenExactBptIn(
        tokenIndex,
        balances,
        amp,
        bptAmountIn,
        bptTotalSupply,
        currentInvariant,
        swapFee
      );

      expect(actualTokenOut).gt(0);
      expectEqualWithError(actualTokenOut, expectedTokenOut, MAX_RELATIVE_ERROR);
    }

    context('check over a range of inputs', () => {
      const bptAmountIn = fp(1);

      for (let numTokens = 2; numTokens <= MAX_TOKENS; numTokens++) {
        const balances: bigint[] = Array.from({ length: numTokens }, () => random(250, 350)).map(fp);
        const totalSupply = balances.reduce((sum, current) => {
          return sum + current;
        });

        it(`computes the token out for ${numTokens} tokens`, async () => {
          for (let amp = 100; amp <= 5000; amp += 100) {
            const currentInvariant = calculateInvariant(balances, amp);

            for (let tokenIndex = 0; tokenIndex < numTokens; tokenIndex++) {
              await checkTokenOutGivenBptIn(
                amp,
                balances,
                tokenIndex,
                bptAmountIn,
                totalSupply,
                currentInvariant,
                SWAP_FEE
              );
            }
          }
        });
      }
    });
  });
});
