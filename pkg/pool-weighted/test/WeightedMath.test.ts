import { expect } from 'chai';
import { bn } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_OUT_RATIO, MAX_IN_RATIO, MAX_RELATIVE_ERROR } from '@balancer-labs/v3-helpers/src/constants';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import '@balancer-labs/v3-common/setupTests';

import {
  computeInvariant,
  computeInGivenExactOut,
  computeOutGivenExactIn,
} from '@balancer-labs/v3-helpers/src/math/weighted';

import { WeightedMathMock } from '../typechain-types/contracts/test/WeightedMathMock';

enum Rounding {
  ROUND_UP,
  ROUND_DOWN,
}

describe('WeightedMath', function () {
  let math: WeightedMathMock;

  sharedBeforeEach('deploy', async function () {
    math = await deploy('WeightedMathMock');
  });

  context('computeInvariant', () => {
    it('reverts if zero invariant', async () => {
      await expect(math.computeInvariant([bn(1)], [0], Rounding.ROUND_DOWN)).to.be.revertedWithCustomError(
        math,
        'ZeroInvariant'
      );
    });

    it('computes invariant for two tokens', async () => {
      const normalizedWeights = [bn(0.3e18), bn(0.7e18)];
      const balances = [bn(10e18), bn(12e18)];

      const result = await math.computeInvariant(normalizedWeights, balances, Rounding.ROUND_DOWN);
      const expected = computeInvariant(balances, normalizedWeights);

      expectEqualWithError(result, bn(expected), MAX_RELATIVE_ERROR);
    });

    it('computes invariant for three tokens', async () => {
      const normalizedWeights = [bn(0.3e18), bn(0.2e18), bn(0.5e18)];
      const balances = [bn(10e18), bn(12e18), bn(14e18)];

      const result = await math.computeInvariant(normalizedWeights, balances, Rounding.ROUND_DOWN);
      const expected = computeInvariant(balances, normalizedWeights);

      expectEqualWithError(result, bn(expected), MAX_RELATIVE_ERROR);
    });
  });

  describe('computeOutGivenExactIn', () => {
    it('computes correct outAmountPool', async () => {
      const tokenWeightIn = bn(50e18);
      const tokenWeightOut = bn(40e18);

      const tokenBalanceIn = bn(100e18);
      const roundedUpBalanceIn = bn(100.1e18);
      const roundedDownBalanceIn = bn(99.9e18);

      const tokenBalanceOut = bn(100e18);
      const roundedUpBalanceOut = bn(100.1e18);
      const roundedDownBalanceOut = bn(99.9e18);

      const tokenAmountIn = bn(15e18);
      const roundedUpAmountGiven = bn(15.01e18);
      const roundedDownAmountGiven = bn(14.99e18);

      const expected = computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const result = await math.computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );

      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);

      const amountOutWithRoundedUpBalances = await math.computeOutGivenExactIn(
        roundedUpBalanceIn,
        tokenWeightIn,
        roundedUpBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );

      const amountOutWithRoundedDownBalances = await math.computeOutGivenExactIn(
        roundedDownBalanceIn,
        tokenWeightIn,
        roundedDownBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );

      // Ensure "rounding" the balances moves the amountOut in the expected direction.
      expect(amountOutWithRoundedUpBalances).gt(result);
      expect(amountOutWithRoundedDownBalances).lt(result);

      const amountOutWithRoundedUpAmountGiven = await math.computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        roundedUpAmountGiven
      );

      const amountOutWithRoundedDownAmountGiven = await math.computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        roundedDownAmountGiven
      );

      // Ensure "rounding" the amountIn moves the amountOut in the expected direction.
      expect(amountOutWithRoundedUpAmountGiven).gt(result);
      expect(amountOutWithRoundedDownAmountGiven).lt(result);
    });

    it('computes correct outAmountPool when tokenAmountIn is extremely small', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountIn = bn(10e6); // (MIN AMOUNT = 0.00000000001)

      const expected = computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const result = await math.computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      //TODO: review high rel error for small amount
      expectEqualWithError(result, expected, 0.1);
    });

    it('comptues correct outAmountPool when tokenWeightIn is extremely big', async () => {
      //Weight relation = 130.07

      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(130.7e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(1e18);
      const tokenAmountIn = bn(15e18);

      const expected = computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const result = await math.computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('comptues correct outAmountPool when tokenWeightIn is extremely small', async () => {
      //Weight relation = 0.00769

      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(0.00769e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(1e18);
      const tokenAmountIn = bn(15e18);

      const expected = computeOutGivenExactIn(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountIn
      );
      const result = await math.computeOutGivenExactIn(
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
      const tokenAmountIn = tokenBalanceIn * MAX_IN_RATIO + 1n; // Just slightly greater than maximum allowed

      await expect(
        math.computeOutGivenExactIn(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountIn)
      ).to.be.revertedWithCustomError(math, 'MaxInRatio');
    });
  });

  describe('computeInGivenExactOut', () => {
    it('computes correct result', async () => {
      const tokenWeightIn = bn(50e18);
      const tokenWeightOut = bn(40e18);

      const tokenBalanceIn = bn(100e18);
      const roundedUpBalanceIn = bn(100.1e18);
      const roundedDownBalanceIn = bn(99.9e18);

      const tokenBalanceOut = bn(100e18);
      const roundedUpBalanceOut = bn(100.1e18);
      const roundedDownBalanceOut = bn(99.9e18);

      const tokenAmountOut = bn(15e18);
      const roundedUpAmountGiven = bn(15.01e18);
      const roundedDownAmountGiven = bn(14.99e18);

      const expected = computeInGivenExactOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      const result = await math.computeInGivenExactOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );

      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);

      const amountInWithRoundedUpBalances = await math.computeInGivenExactOut(
        roundedUpBalanceIn,
        tokenWeightIn,
        roundedUpBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );

      const amountInWithRoundedDownBalances = await math.computeInGivenExactOut(
        roundedDownBalanceIn,
        tokenWeightIn,
        roundedDownBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );

      // Ensure "rounding" the balances moves the amountIn in the expected direction.
      expect(amountInWithRoundedUpBalances).lt(result);
      expect(amountInWithRoundedDownBalances).gt(result);

      const amountInWithRoundedUpAmountGiven = await math.computeInGivenExactOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        roundedUpAmountGiven
      );

      const amountInWithRoundedDownAmountGiven = await math.computeInGivenExactOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        roundedDownAmountGiven
      );

      // Ensure "rounding" the amountGiven moves the amountOut in the expected direction.
      expect(amountInWithRoundedUpAmountGiven).gt(result);
      expect(amountInWithRoundedDownAmountGiven).lt(result);
    });

    it('computes correct inAmountPool when tokenAmountOut is extremely small', async () => {
      const tokenBalanceIn = bn(100e18);
      const tokenWeightIn = bn(50e18);
      const tokenBalanceOut = bn(100e18);
      const tokenWeightOut = bn(40e18);
      const tokenAmountOut = bn(10e6); // (MIN AMOUNT = 0.00000000001)

      const expected = computeInGivenExactOut(
        tokenBalanceIn,
        tokenWeightIn,
        tokenBalanceOut,
        tokenWeightOut,
        tokenAmountOut
      );
      const result = await math.computeInGivenExactOut(
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
      const tokenAmountOut = tokenBalanceOut * MAX_OUT_RATIO + 1n; // Just slightly greater than maximum allowed

      await expect(
        math.computeInGivenExactOut(tokenBalanceIn, tokenWeightIn, tokenBalanceOut, tokenWeightOut, tokenAmountOut)
      ).to.be.revertedWithCustomError(math, 'MaxOutRatio');
    });
  });
});
