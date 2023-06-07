import { bn } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_OUT_RATIO, MAX_IN_RATIO, MAX_RELATIVE_ERROR } from '@balancer-labs/v3-helpers/src/constants';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import '@balancer-labs/v3-common/setupTests';
import { expect } from 'chai';

import {
  calculateInvariant,
  calcInGivenOut,
  calcOutGivenIn,
  calcBptOutGivenExactTokensIn,
  calcBptOutGivenExactTokenIn,
  calcTokenInGivenExactBptOut,
} from '@balancer-labs/v3-helpers/src/math/weighted';

import { WeightedMathMock } from '../typechain-types/contracts/test/WeightedMathMock';

describe.only('WeightedMath', function () {
  let math: WeightedMathMock;

  sharedBeforeEach('deploy', async function () {
    math = await deploy('WeightedMathMock');
  });

  context('calculateInvariant', () => {
    it('reverts if zero invariant', async () => {
      await expect(math.calculateInvariant([bn(1)], [0])).to.be.revertedWithCustomError(math, 'ZeroInvariant');
    });

    context('two tokens', () => {
      it('calculates invariant', async () => {
        const normalizedWeights = [bn(0.3e18), bn(0.7e18)];
        const balances = [bn(10e18), bn(12e18)];

        const result = await math.calculateInvariant(normalizedWeights, balances);
        const expected = calculateInvariant(balances, normalizedWeights);

        expectEqualWithError(result, bn(expected), MAX_RELATIVE_ERROR);
      });
    });

    context('three tokens', () => {
      it('calculates invariant', async () => {
        const normalizedWeights = [bn(0.3e18), bn(0.2e18), bn(0.5e18)];
        const balances = [bn(10e18), bn(12e18), bn(14e18)];

        const result = await math.calculateInvariant(normalizedWeights, balances);
        const expected = calculateInvariant(balances, normalizedWeights);

        expectEqualWithError(result, bn(expected), MAX_RELATIVE_ERROR);
      });
    });
  });

  describe('calcOutGivenIn', () => {
    it('calculates correct outAmountPool', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountIn = bn(15e18);

      const expected = calcOutGivenIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn);
      const result = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates correct outAmountPool when tokenAmountIn is extermely small', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountIn = bn(10e6); // (MIN AMOUNT = 0.00000000001)

      const expected = calcOutGivenIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn);
      const result = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      //TODO: review high rel error for small amount
      expectEqualWithError(result, expected, 0.1);
    });

    it('calculates correct outAmountPool when tokenWeightIn is extermely big', async () => {
      //Weight relation = 130.07

      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(130.7e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(1e18);
      const tokenAmountIn = bn(15e18);

      const expected = calcOutGivenIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn);
      const result = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates correct outAmountPool when tokenWeightIn is extermely small', async () => {
      //Weight relation = 0.00769

      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(0.00769e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(1e18);
      const tokenAmountIn = bn(15e18);

      const expected = calcOutGivenIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn);
      const result = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('throws MaxInRatio error when tokenAmountIn exceeds maximum allowed', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);

      // The amount in exceeds the maximum in ratio (i.e. tokenBalanceIn * MAX_IN_RATIO)
      const tokenAmountIn = tokenBalanceIn.mul(MAX_IN_RATIO).add(bn('1')); // Just slightly greater than maximum allowed

      await expect(
        math.calcOutGivenIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn)
      ).to.be.revertedWithCustomError(math, 'MaxInRatio');
    });
  });

  describe('calcInGivenOut', () => {
    it('calculates correct result', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountOut = bn(15e18);

      const expected = calcInGivenOut(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountOut);
      const result = await math.calcInGivenOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates correct inAmountPool when tokenAmountOut is extermely small', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountOut = bn(10e6); // (MIN AMOUNT = 0.00000000001)

      const expected = calcInGivenOut(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountOut);
      const result = await math.calcInGivenOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      //TODO: review high rel error for small amount
      expectEqualWithError(result, expected, 0.5);
    });

    it('throws MaxOutRatio error when amountOut exceeds maximum allowed', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);

      // The amount in exceeds the maximum in ratio (i.e. tokenBalanceIn * MAX_IN_RATIO)
      const tokenAmountOut = tokenBalanceOut.mul(MAX_OUT_RATIO).add(bn('1')); // Just slightly greater than maximum allowed

      await expect(
        math.calcInGivenOut(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountOut)
      ).to.be.revertedWithCustomError(math, 'MaxOutRatio');
    });
  });

  describe('calcBptOutGivenExactTokensIn', () => {
    it('calculates correct BPT out for exact tokens in', async () => {
      const balances = [bn(100e18), bn(100e18)];
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(10e18), bn(10e18)];
      const bptTotalSupply = bn(100e18);
      const swapFeePercentage = bn(0.01e18);

      const expected = calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('returns zero BPT out when invariantRatio is less than ONE', async () => {
      const balances = [bn(100e18), bn(100e18)];
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(0), bn(0)];
      const bptTotalSupply = bn(1000e18);
      const swapFeePercentage = bn(0.01e18);

      const result = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expect(result).to.be.zero;
    });

    it('calculates correct BPT out when amountsIn are extremely small', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(1e12), bn(2e12)];
      const bptTotalSupply = bn(1000e18);
      const swapFeePercentage = bn(0.01e18);

      const expected = calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates correct BPT out when normalizedWeights are unbalanced', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const normalizedWeights = [bn(0.2e18), bn(0.8e18)];
      const amountsIn = [bn(10e18), bn(20e18)];
      const bptTotalSupply = bn(1000e18);
      const swapFeePercentage = bn(0.01e18);

      const expected = calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });
  });

  describe('calcBptOutGivenExactTokenIn', () => {
    // Define a standard BPT total supply and swap fee for tests.
    const bptTotalSupply = bn(1000e18);
    const swapFeePercentage = bn(0.01e18); // 1% swap fee
    const normalizedWeight = bn(0.5e18); // 50% normalized weight

    it('calculates correct BPT out amount with no swap fee', async () => {
      const balance = bn(100e18);
      const amountIn = bn(10e18);

      const expected = calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates correct BPT out amount with swap fee', async () => {
      const balance = bn(100e18);
      const amountIn = bn(200e18); // Big enough to trigger swap fee

      const expected = calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates 0 BPT out when amountIn is 0', async () => {
      const balance = bn(100e18);
      const amountIn = bn(0);

      const expected = calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates correct BPT out amount when balance is extremely small', async () => {
      const balance = bn(1e6); // 0.000001 token
      const amountIn = bn(1e6);

      const expected = calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('calculates correct BPT out amount when balance is extremely large', async () => {
      const balance = bn(1000000e18); // 1,000,000 tokens
      const amountIn = bn(100e18);

      const expected = calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });
  });

  describe('calcTokenInGivenExactBptOut', () => {
    it('calculates correct token amountIn', async () => {
      const balance = bn(1e21);
      const normalizedWeight = bn(5e17);
      const bptAmountOut = bn(1e16);
      const bptTotalSupply = bn(1e20);
      const swapFeePercentage = bn(1e16);

      const expected = calcTokenInGivenExactBptOut(
        balance,
        normalizedWeight,
        bptAmountOut,
        bptTotalSupply,
        swapFeePercentage
      );
      const result = await math.calcTokenInGivenExactBptOut(
        balance,
        normalizedWeight,
        bptAmountOut,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('throws MaxOutBptForTokenIn error when invariant ratio exceeds MAX_INVARIANT_RATIO', async () => {
      const balance = bn(1e20);
      const normalizedWeight = bn(5e17);
      const bptAmountOut = bn(3e20); // This will trigger the MaxOutBptForTokenIn error
      const bptTotalSupply = bn(1e20);
      const swapFeePercentage = bn(1e16);

      await expect(
        math.calcTokenInGivenExactBptOut(balance, normalizedWeight, bptAmountOut, bptTotalSupply, swapFeePercentage)
      ).to.be.revertedWithCustomError(math, 'MaxOutBptForTokenIn');
    });
  });
});
