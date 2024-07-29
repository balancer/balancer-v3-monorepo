import { bn, fp, toFp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_RELATIVE_ERROR } from '@balancer-labs/v3-helpers/src/constants';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import '@balancer-labs/v3-common/setupTests';
import { expect } from 'chai';

import {
  computeProportionalAmountsIn,
  computeProportionalAmountsOut,
  computeAddLiquidityUnbalanced,
  computeAddLiquiditySingleTokenExactOut,
  computeRemoveLiquiditySingleTokenExactOut,
  computeRemoveLiquiditySingleTokenExactIn,
} from '@balancer-labs/v3-helpers/src/math/base';

import { BasePoolMathMock } from '../typechain-types/contracts/test/BasePoolMathMock';

const SWAP_FEE = fp(0.01);

describe('BasePoolMath', function () {
  let math: BasePoolMathMock;

  sharedBeforeEach('deploy', async function () {
    math = await deploy('BasePoolMathMock');
  });

  it('test computeProportionalAmountsIn', async () => {
    const balances = [fp(100), fp(200)];
    const bptTotalSupply = fp(300);
    const bptAmountOut = fp(30);

    const expected = computeProportionalAmountsIn(balances, bptTotalSupply, bptAmountOut);
    const result = await math.computeProportionalAmountsIn(
      balances.map((balance) => bn(toFp(balance))),
      bn(toFp(bptTotalSupply)),
      bn(toFp(bptAmountOut))
    );

    result.forEach((res, index) => {
      expect(res).not.to.be.equal(0n, 'result is 0');
      expectEqualWithError(res, bn(toFp(expected[index])), MAX_RELATIVE_ERROR, 'unexpected result');
    });
  });

  it('test computeProportionalAmountsOut', async () => {
    const balances = [fp(100), fp(200)];
    const bptTotalSupply = fp(300);
    const bptAmountIn = fp(30);

    const expected = computeProportionalAmountsOut(balances, bptTotalSupply, bptAmountIn);
    const result = await math.computeProportionalAmountsOut(
      balances.map((balance) => bn(toFp(balance))),
      bn(toFp(bptTotalSupply)),
      bn(toFp(bptAmountIn))
    );

    result.forEach((res, index) => {
      expect(res).not.to.be.equal(0n, 'result is 0');
      expectEqualWithError(res, bn(toFp(expected[index])), MAX_RELATIVE_ERROR, 'unexpected result');
    });
  });

  it('test computeAddLiquidityUnbalanced', async () => {
    const currentBalances = [fp(100), fp(200)];
    const exactAmounts = [fp(10), fp(20)];
    const totalSupply = fp(300);

    const { bptAmountOut: expectedBptAmountOut, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeAddLiquidityUnbalanced(currentBalances, exactAmounts, totalSupply, SWAP_FEE);

    const result = await math.computeAddLiquidityUnbalanced(currentBalances, exactAmounts, totalSupply, SWAP_FEE);

    expect(result.bptAmountOut).not.to.be.equal(0n, 'bptAmountOut is 0');
    expectEqualWithError(result.bptAmountOut, expectedBptAmountOut, MAX_RELATIVE_ERROR, 'unexpected bptAmountOut');
    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        expectedSwapFeeAmounts[i],
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });

  it('test computeAddLiquiditySingleTokenExactOut', async () => {
    const currentBalances = [fp(100), fp(200)];
    const tokenInIndex = 0;
    const exactBptAmountOut = fp(30);
    const totalSupply = fp(300);

    const { amountInWithFee: expectedAmountInWithFee, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeAddLiquiditySingleTokenExactOut(currentBalances, tokenInIndex, exactBptAmountOut, totalSupply, SWAP_FEE);

    const result = await math.computeAddLiquiditySingleTokenExactOut(
      currentBalances,
      tokenInIndex,
      exactBptAmountOut,
      totalSupply,
      SWAP_FEE
    );

    expect(result.amountInWithFee).not.to.be.equal(0n, 'amountInWithFee is 0');
    expectEqualWithError(
      result.amountInWithFee,
      expectedAmountInWithFee,
      MAX_RELATIVE_ERROR,
      'unexpected amountInWithFee'
    );
    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        expectedSwapFeeAmounts[i],
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });

  it('test computeRemoveLiquiditySingleTokenExactOut', async () => {
    const currentBalances = [fp(100), fp(200)];
    const tokenOutIndex = 0;
    const exactAmountOut = fp(10);
    const totalSupply = fp(300);

    const { bptAmountIn: expectedBptAmountIn, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeRemoveLiquiditySingleTokenExactOut(currentBalances, tokenOutIndex, exactAmountOut, totalSupply, SWAP_FEE);

    const result = await math.computeRemoveLiquiditySingleTokenExactOut(
      currentBalances,
      tokenOutIndex,
      exactAmountOut,
      totalSupply,
      SWAP_FEE
    );

    expect(result.bptAmountIn).not.to.be.equal(0n, 'bptAmountIn is 0');
    expectEqualWithError(result.bptAmountIn, expectedBptAmountIn, MAX_RELATIVE_ERROR, 'unexpected bptAmountIn');

    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        expectedSwapFeeAmounts[i],
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });

  it('test computeRemoveLiquiditySingleTokenExactIn', async () => {
    const currentBalances = [fp(100), fp(200)];
    const tokenOutIndex = 0;
    const exactBptAmountIn = fp(30);
    const totalSupply = fp(300);

    const { amountOutWithFee: expectedAmountOutWithFee, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeRemoveLiquiditySingleTokenExactIn(currentBalances, tokenOutIndex, exactBptAmountIn, totalSupply, SWAP_FEE);

    const result = await math.computeRemoveLiquiditySingleTokenExactIn(
      currentBalances,
      tokenOutIndex,
      exactBptAmountIn,
      totalSupply,
      SWAP_FEE
    );

    expect(result.amountOutWithFee).not.to.be.equal(0n, 'amountOutWithFee is 0');
    expectEqualWithError(
      result.amountOutWithFee,
      expectedAmountOutWithFee,
      MAX_RELATIVE_ERROR,
      'unexpected amountOutWithFee'
    );
    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        expectedSwapFeeAmounts[i],
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });
});
