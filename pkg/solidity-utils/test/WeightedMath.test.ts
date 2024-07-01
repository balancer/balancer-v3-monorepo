import { bn } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_OUT_RATIO, MAX_IN_RATIO, MAX_RELATIVE_ERROR } from '@balancer-labs/v3-helpers/src/constants';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import '@balancer-labs/v3-common/setupTests';
import { expect } from 'chai';

import {
  computeInvariant,
  computeInGivenExactOut,
  computeOutGivenExactIn,
  computeBptOutGivenExactTokensIn,
  computeBptOutGivenExactTokenIn,
  computeTokenInGivenExactBptOut,
  computeBptInGivenExactTokensOut,
  computeBptInGivenExactTokenOut,
  computeTokenOutGivenExactBptIn,
  computeBptOutAddToken,
} from '@balancer-labs/v3-helpers/src/math/weighted';

import { WeightedMathMock } from '../typechain-types/contracts/test/WeightedMathMock';

const SWAP_FEE = bn(0.01e18);

describe('WeightedMath', function () {
  let math: WeightedMathMock;

  sharedBeforeEach('deploy', async function () {
    math = await deploy('WeightedMathMock');
  });

  context('computeInvariant', () => {
    it('reverts if zero invariant', async () => {
      await expect(math.computeInvariant([bn(1)], [0])).to.be.revertedWithCustomError(math, 'ZeroInvariant');
    });

    it('computes invariant for two tokens', async () => {
      const normalizedWeights = [bn(0.3e18), bn(0.7e18)];
      const balances = [bn(10e18), bn(12e18)];

      const result = await math.computeInvariant(normalizedWeights, balances);
      const expected = computeInvariant(balances, normalizedWeights);

      expectEqualWithError(result, bn(expected), MAX_RELATIVE_ERROR);
    });

    it('computes invariant for three tokens', async () => {
      const normalizedWeights = [bn(0.3e18), bn(0.2e18), bn(0.5e18)];
      const balances = [bn(10e18), bn(12e18), bn(14e18)];

      const result = await math.computeInvariant(normalizedWeights, balances);
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

  describe('computeBptOutGivenExactTokensIn', () => {
    const standardBalances = [bn(100e18), bn(100e18)];
    const roundedUpBalances = [bn(100.1e18), bn(100.1e18)];
    const roundedDownBalances = [bn(99.9e18), bn(99.9e18)];

    it('computes correct BPT out for exact tokens in', async () => {
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(10e18), bn(10e18)];
      const bptTotalSupply = bn(100e18);
      const expected = computeBptOutGivenExactTokensIn(
        standardBalances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeBptOutGivenExactTokensIn(
        standardBalances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);

      const bptOutWithRoundedUpBalances = await math.computeBptOutGivenExactTokensIn(
        roundedUpBalances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );

      const bptOutWithRoundedDownBalances = await math.computeBptOutGivenExactTokensIn(
        roundedDownBalances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );

      // Ensure "rounding" balances moves the bptOut in the expected direction.
      expect(bptOutWithRoundedUpBalances).to.lt(result);
      expect(bptOutWithRoundedDownBalances).to.gt(result);
    });

    it('computes correct BPT out when swap fee is applied', async () => {
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(10e18), bn(1e18)];
      const bptTotalSupply = bn(100e18);

      const expected = computeBptOutGivenExactTokensIn(
        standardBalances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeBptOutGivenExactTokensIn(
        standardBalances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('returns zero BPT out when invariantRatio is less than ONE', async () => {
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(0), bn(0)];
      const bptTotalSupply = bn(1000e18);

      const result = await math.computeBptOutGivenExactTokensIn(
        standardBalances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expect(result).to.be.zero;
    });

    it('computes correct BPT out when amountsIn are extremely small', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsIn = [bn(1e12), bn(2e12)];
      const bptTotalSupply = bn(1000e18);

      const expected = computeBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('computes correct BPT out when normalizedWeights are unbalanced', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const normalizedWeights = [bn(0.2e18), bn(0.8e18)];
      const amountsIn = [bn(10e18), bn(20e18)];
      const bptTotalSupply = bn(1000e18);

      const expected = computeBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeBptOutGivenExactTokensIn(
        balances,
        normalizedWeights,
        amountsIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });
  });

  describe('computeBptOutGivenExactTokenIn', () => {
    // Define a standard BPT total supply and swap fee for tests.
    const bptTotalSupply = bn(1000e18);
    const normalizedWeight = bn(0.5e18); // 50% normalized weight

    it('computes correct BPT out amount with no swap fee', async () => {
      const balance = bn(100e18);
      const amountIn = bn(10e18);

      const expected = computeBptOutGivenExactTokenIn(balance, normalizedWeight, amountIn, bptTotalSupply, SWAP_FEE);
      const result = await math.computeBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('computes correct BPT out amount with swap fee', async () => {
      const balance = bn(100e18);
      const amountIn = bn(200e18); // Big enough to trigger swap fee

      const expected = computeBptOutGivenExactTokenIn(balance, normalizedWeight, amountIn, bptTotalSupply, SWAP_FEE);
      const result = await math.computeBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('computes zero BPT out when amountIn is zero', async () => {
      const balance = bn(100e18);
      const amountIn = bn(0);

      const result = await math.computeBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, 0, MAX_RELATIVE_ERROR);
    });

    it('computes correct BPT out amount when balance is extremely small', async () => {
      const balance = bn(1e6); // 0.000001 token
      const amountIn = bn(1e6);

      const expected = computeBptOutGivenExactTokenIn(balance, normalizedWeight, amountIn, bptTotalSupply, SWAP_FEE);
      const result = await math.computeBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('computes correct BPT out amount when balance is extremely large', async () => {
      const balance = bn(1000000e18); // 1,000,000 tokens
      const amountIn = bn(100e18);

      const expected = computeBptOutGivenExactTokenIn(balance, normalizedWeight, amountIn, bptTotalSupply, SWAP_FEE);
      const result = await math.computeBptOutGivenExactTokenIn(
        balance,
        normalizedWeight,
        amountIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });
  });

  describe('computeTokenInGivenExactBptOut', () => {
    it('computes correct token amountIn', async () => {
      const balance = bn(1e21);
      const normalizedWeight = bn(5e17);
      const bptAmountOut = bn(1e16);
      const bptTotalSupply = bn(1e20);

      const expected = computeTokenInGivenExactBptOut(
        balance,
        normalizedWeight,
        bptAmountOut,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeTokenInGivenExactBptOut(
        balance,
        normalizedWeight,
        bptAmountOut,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('throws MaxOutBptForTokenIn error when invariant ratio exceeds MAX_INVARIANT_RATIO', async () => {
      const balance = bn(1e20);
      const normalizedWeight = bn(5e17);
      const bptAmountOut = bn(3e20); // This will trigger the MaxOutBptForTokenIn error
      const bptTotalSupply = bn(1e20);

      await expect(
        math.computeTokenInGivenExactBptOut(balance, normalizedWeight, bptAmountOut, bptTotalSupply, SWAP_FEE)
      ).to.be.revertedWithCustomError(math, 'MaxOutBptForTokenIn');
    });
  });

  describe('computeBptInGivenExactTokensOut', () => {
    const standardBalances = [bn(100e18), bn(100e18)];
    const roundedUpBalances = [bn(100.1e18), bn(100.1e18)];
    const roundedDownBalances = [bn(99.9e18), bn(99.9e18)];

    it('comptues correct BPT in for exact tokens out', async () => {
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsOut = [bn(10e18), bn(10e18)];
      const bptTotalSupply = bn(100e18);

      const expected = computeBptInGivenExactTokensOut(
        standardBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeBptInGivenExactTokensOut(
        standardBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);

      const bptInWithRoundedUpBalances = await math.computeBptInGivenExactTokensOut(
        roundedUpBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );

      const bptInWithRoundedDownBalances = await math.computeBptInGivenExactTokensOut(
        roundedDownBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );

      // Ensure "rounding" the balances move the bptIn in the expected direction.
      expect(bptInWithRoundedUpBalances).to.lt(result);
      expect(bptInWithRoundedDownBalances).to.gt(result);
    });

    it('computes correct BPT when swap fee is applied', async () => {
      const normalizedWeights = [bn(0.01e18), bn(0.99e18)];
      const amountsOut = [bn(50e18), bn(10e18)];
      const bptTotalSupply = bn(100e18);

      const expected = computeBptInGivenExactTokensOut(
        standardBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeBptInGivenExactTokensOut(
        standardBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('computes correct BPT when one of the token amountsOut is zero', async () => {
      const normalizedWeights = [bn(0.5e18), bn(0.5e18)];
      const amountsOut = [bn(0), bn(10e18)];
      const bptTotalSupply = bn(100e18);

      const expected = computeBptInGivenExactTokensOut(
        standardBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );
      const result = await math.computeBptInGivenExactTokensOut(
        standardBalances,
        normalizedWeights,
        amountsOut,
        bptTotalSupply,
        SWAP_FEE
      );
      // TODO: For some reason precision loss here is high
      expectEqualWithError(result, expected, 0.01);
    });
  });

  describe('computeBptInGivenExactTokenOut', () => {
    // Define a standard BPT total supply and swap fee for tests.
    const bptTotalSupply = bn(1000e18);
    const normalizedWeight = bn(0.5e18); // 50% normalized weight

    it('computes correct BPT in amount with no swap fee', async () => {
      const balance = bn(100e18);
      const amountOut = bn(10e18);

      const expected = computeBptInGivenExactTokenOut(balance, normalizedWeight, amountOut, bptTotalSupply, SWAP_FEE);
      const result = await math.computeBptInGivenExactTokenOut(
        balance,
        normalizedWeight,
        amountOut,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('computes correct BPT in amount with swap fee', async () => {
      const balance = bn(100e18);
      const amountOut = bn(90e18); // Big enough to trigger swap fee

      const expected = computeBptInGivenExactTokenOut(balance, normalizedWeight, amountOut, bptTotalSupply, SWAP_FEE);
      const result = await math.computeBptInGivenExactTokenOut(
        balance,
        normalizedWeight,
        amountOut,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('computes zero BPT in when amountOut is zero', async () => {
      const balance = bn(100e18);
      const amountOut = bn(0);

      const expected = computeBptInGivenExactTokenOut(balance, normalizedWeight, amountOut, bptTotalSupply, SWAP_FEE);
      const result = await math.computeBptInGivenExactTokenOut(
        balance,
        normalizedWeight,
        amountOut,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });
  });

  describe('computeTokenOutGivenExactBptIn', () => {
    it('computes correct token amountOut', async () => {
      const balance = bn(1e21);
      const normalizedWeight = bn(5e17);
      const bptAmountIn = bn(1e16);
      const bptTotalSupply = bn(1e20);

      const expected = computeTokenOutGivenExactBptIn(balance, normalizedWeight, bptAmountIn, bptTotalSupply, SWAP_FEE);
      const result = await math.computeTokenOutGivenExactBptIn(
        balance,
        normalizedWeight,
        bptAmountIn,
        bptTotalSupply,
        SWAP_FEE
      );
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });

    it('throws MinBPTInForTokenOut error when invariant ratio exceeds MIN_INVARIANT_RATIO', async () => {
      const balance = bn(1e20);
      const normalizedWeight = bn(5e17);
      const bptAmountIn = bn(9e19); // This will trigger the MinBPTInForTokenOut error
      const bptTotalSupply = bn(1e20);

      await expect(
        math.computeTokenOutGivenExactBptIn(balance, normalizedWeight, bptAmountIn, bptTotalSupply, SWAP_FEE)
      ).to.be.revertedWithCustomError(math, 'MinBPTInForTokenOut');
    });
  });

  describe('computeBptOutAddToken', () => {
    it('computes the amount of BPT which should be minted when adding a new token', async () => {
      const normalizedWeight = bn(5e17);
      const bptTotalSupply = bn(1e20);

      const expected = computeBptOutAddToken(bptTotalSupply, normalizedWeight);
      const result = await math.computeBptOutAddToken(bptTotalSupply, normalizedWeight);
      expectEqualWithError(result, expected, MAX_RELATIVE_ERROR);
    });
  });
});
