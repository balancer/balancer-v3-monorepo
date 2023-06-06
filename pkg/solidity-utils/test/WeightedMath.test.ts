import { bn } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_IN_RATIO, MAX_RELATIVE_ERROR } from '@balancer-labs/v3-helpers/src/constants';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { expect } from 'chai';

import {
  calculateInvariant,
  calcInGivenOut,
  calcOutGivenIn,
  calcBptOutGivenExactTokensIn,
} from '@balancer-labs/v3-helpers/src/math/weighted';

import { WeightedMathMock } from '../typechain-types/contracts/test/WeightedMathMock';

describe.only('WeightedMath', function () {
  let math: WeightedMathMock;

  before(async function () {
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
        const expectedInvariant = calculateInvariant(balances, normalizedWeights);

        expectEqualWithError(result, bn(expectedInvariant), MAX_RELATIVE_ERROR);
      });
    });

    context('three tokens', () => {
      it('calculates invariant', async () => {
        const normalizedWeights = [bn(0.3e18), bn(0.2e18), bn(0.5e18)];
        const balances = [bn(10e18), bn(12e18), bn(14e18)];

        const result = await math.calculateInvariant(normalizedWeights, balances);
        const expectedInvariant = calculateInvariant(balances, normalizedWeights);

        expectEqualWithError(result, bn(expectedInvariant), MAX_RELATIVE_ERROR);
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

      const outAmountMath = calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const outAmountPool = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      expectEqualWithError(outAmountPool, bn(outAmountMath.toFixed(0)), MAX_RELATIVE_ERROR);
    });

    it('calculates correct outAmountPool when tokenAmountIn is extermely small', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountIn = bn(10e6); // (MIN AMOUNT = 0.00000000001)

      const outAmountMath = calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const outAmountPool = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      //TODO: review high rel error for small amount
      expectEqualWithError(outAmountPool, bn(outAmountMath.toFixed(0)), 0.1);
    });

    it('calculates correct outAmountPool when tokenWeightIn is extermely big', async () => {
      //Weight relation = 130.07

      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(130.7e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(1e18);
      const tokenAmountIn = bn(15e18);

      const outAmountMath = calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const outAmountPool = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      expectEqualWithError(outAmountPool, bn(outAmountMath.toFixed(0)), MAX_RELATIVE_ERROR);
    });

    it('calculates correct outAmountPool when tokenWeightIn is extermely small', async () => {
      //Weight relation = 0.00769

      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(0.00769e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(1e18);
      const tokenAmountIn = bn(15e18);

      const outAmountMath = calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const outAmountPool = await math.calcOutGivenIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      expectEqualWithError(outAmountPool, bn(outAmountMath.toFixed(0)), MAX_RELATIVE_ERROR);
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
    it('calculates correct inAmountPool', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountOut = bn(15e18);

      const inAmountMath = calcInGivenOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      const inAmountPool = await math.calcInGivenOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      expectEqualWithError(inAmountPool, bn(inAmountMath.toFixed(0)), MAX_RELATIVE_ERROR);
    });

    it('calculates correct inAmountPool when tokenAmountOut is extermely small', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountOut = bn(10e6); // (MIN AMOUNT = 0.00000000001)

      const inAmountMath = calcInGivenOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      const inAmountPool = await math.calcInGivenOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      //TODO: review high rel error for small amount
      expectEqualWithError(inAmountPool, bn(inAmountMath.toFixed(0)), 0.5);
    });
  });

  describe('calcBptOutGivenExactTokensIn', () => {
    it('calculates correct BPT out for exact tokens in', async () => {
      const balances = [bn(100e18), bn(100e18)];
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(10e18), bn(10e18)];
      const bptTotalSupply = bn(100e18);
      const swapFeePercentage = bn(0.01e18);

      const bptOutMath = calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const bptOutPool = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      console.log('bptOutPool:', bptOutPool);
      console.log('bptOutMath:', bptOutMath);
      expectEqualWithError(bptOutPool, bptOutMath, MAX_RELATIVE_ERROR);
    });

    it('returns zero BPT out when invariantRatio is less than ONE', async () => {
      const balances = [bn(100e18), bn(100e18)];
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(0), bn(0)];
      const bptTotalSupply = bn(1000e18);
      const swapFeePercentage = bn(0.01e18);

      const bptOutPool = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(bptOutPool, 0, MAX_RELATIVE_ERROR);
    });

    it('calculates correct BPT out when amountsIn are extremely small', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(0.01e18), bn(0.02e18)];
      const bptTotalSupply = bn(1000e18);
      const swapFeePercentage = bn(0.01e18);

      const bptOutMath = calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const bptOutPool = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(bptOutPool, bptOutMath, MAX_RELATIVE_ERROR);
    });

    it('calculates correct BPT out when normalizedWeights are unbalanced', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const normalizedWeights = [bn(0.2e18), bn(0.8e18)];
      const amountsIn = [bn(10e18), bn(20e18)];
      const bptTotalSupply = bn(1000e18);
      const swapFeePercentage = bn(0.01e18);

      const bptOutMath = calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      const bptOutPool = await math.calcBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        swapFeePercentage
      );
      expectEqualWithError(bptOutPool, bptOutMath, MAX_RELATIVE_ERROR);
    });
  });
});
