import { bn, decimal, fromFp, toFp } from '@balancer-labs/v3-helpers/src/numbers';
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

const SWAP_FEE = decimal(0.01);

describe('BasePoolMath', function () {
  let math: BasePoolMathMock;

  sharedBeforeEach('deploy', async function () {
    math = await deploy('BasePoolMathMock');
  });

  it('test computeProportionalAmountsIn', async () => {
    const balances = [decimal(100), decimal(200)];
    const bptTotalSupply = decimal(300);
    const bptAmountOut = decimal(30);

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
    const balances = [decimal(100), decimal(200)];
    const bptTotalSupply = decimal(300);
    const bptAmountIn = decimal(30);

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
    const currentBalances = [decimal(100), decimal(200)];
    const exactAmounts = [decimal(10), decimal(20)];
    const totalSupply = decimal(300);

    const { bptAmountOut: expectedBptAmountOut, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeAddLiquidityUnbalanced(currentBalances, exactAmounts, totalSupply, SWAP_FEE);

    const result = await math.computeAddLiquidityUnbalanced(
      currentBalances.map((balance) => bn(toFp(balance))),
      exactAmounts.map((amount) => bn(toFp(amount))),
      bn(toFp(totalSupply)),
      bn(toFp(SWAP_FEE))
    );

    expect(result.bptAmountOut).not.to.be.equal(0n, 'bptAmountOut is 0');
    expectEqualWithError(
      result.bptAmountOut,
      bn(toFp(expectedBptAmountOut)),
      MAX_RELATIVE_ERROR,
      'unexpected bptAmountOut'
    );
    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        bn(toFp(expectedSwapFeeAmounts[i])),
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });

  it('test computeAddLiquiditySingleTokenExactOut', async () => {
    const currentBalances = [decimal(100), decimal(200)];
    const tokenInIndex = 0;
    const exactBptAmountOut = decimal(30);
    const totalSupply = decimal(300);

    const { amountInWithFee: expectedAmountInWithFee, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeAddLiquiditySingleTokenExactOut(currentBalances, tokenInIndex, exactBptAmountOut, totalSupply, SWAP_FEE);

    const result = await math.computeAddLiquiditySingleTokenExactOut(
      currentBalances.map((balance) => bn(toFp(balance))),
      tokenInIndex,
      bn(toFp(exactBptAmountOut)),
      bn(toFp(totalSupply)),
      bn(toFp(SWAP_FEE))
    );

    expect(result.amountInWithFee).not.to.be.equal(0n, 'amountInWithFee is 0');
    expectEqualWithError(
      result.amountInWithFee,
      bn(toFp(expectedAmountInWithFee)),
      MAX_RELATIVE_ERROR,
      'unexpected amountInWithFee'
    );
    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        bn(toFp(expectedSwapFeeAmounts[i])),
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });

  it('test computeRemoveLiquiditySingleTokenExactOut', async () => {
    const currentBalances = [decimal(100), decimal(200)];
    const tokenOutIndex = 0;
    const exactAmountOut = decimal(10);
    const totalSupply = decimal(300);

    const { bptAmountIn: expectedBptAmountIn, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeRemoveLiquiditySingleTokenExactOut(currentBalances, tokenOutIndex, exactAmountOut, totalSupply, SWAP_FEE);

    const result = await math.computeRemoveLiquiditySingleTokenExactOut(
      currentBalances.map((balance) => bn(toFp(balance))),
      tokenOutIndex,
      bn(toFp(exactAmountOut)),
      bn(toFp(totalSupply)),
      bn(toFp(SWAP_FEE))
    );

    expect(result.bptAmountIn).not.to.be.equal(0n, 'bptAmountIn is 0');
    expectEqualWithError(
      result.bptAmountIn,
      bn(toFp(expectedBptAmountIn)),
      MAX_RELATIVE_ERROR,
      'unexpected bptAmountIn'
    );

    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        bn(toFp(expectedSwapFeeAmounts[i])),
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });

  it('test computeRemoveLiquiditySingleTokenExactIn', async () => {
    const currentBalances = [decimal(100), decimal(200)];
    const tokenOutIndex = 0;
    const exactBptAmountIn = decimal(30);
    const totalSupply = decimal(300);

    const { amountOutWithFee: expectedAmountOutWithFee, swapFeeAmounts: expectedSwapFeeAmounts } =
      computeRemoveLiquiditySingleTokenExactIn(currentBalances, tokenOutIndex, exactBptAmountIn, totalSupply, SWAP_FEE);

    const result = await math.computeRemoveLiquiditySingleTokenExactIn(
      currentBalances.map((balance) => bn(toFp(balance))),
      tokenOutIndex,
      bn(toFp(exactBptAmountIn)),
      bn(toFp(totalSupply)),
      bn(toFp(SWAP_FEE))
    );

    expect(result.amountOutWithFee).not.to.be.equal(0n, 'amountOutWithFee is 0');
    expectEqualWithError(
      result.amountOutWithFee,
      bn(toFp(expectedAmountOutWithFee)),
      MAX_RELATIVE_ERROR,
      'unexpected amountOutWithFee'
    );
    result.swapFeeAmounts.forEach((res, i) => {
      expectEqualWithError(
        result.swapFeeAmounts[i],
        bn(toFp(expectedSwapFeeAmounts[i])),
        MAX_RELATIVE_ERROR,
        'unexpected swapFeeAmounts'
      );
    });
  });
});
