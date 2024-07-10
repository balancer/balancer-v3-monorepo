import { bn, fromFp } from '@balancer-labs/v3-helpers/src/numbers';
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
  computeInvariantMock,
} from '@balancer-labs/v3-helpers/src/math/base';

import { BasePoolMathMock } from '../typechain-types/contracts/test/BasePoolMathMock';

const SWAP_FEE = bn(0.01e18);

describe('BasePoolMath', function () {
  let math: BasePoolMathMock;

  sharedBeforeEach('deploy', async function () {
    math = await deploy('BasePoolMathMock');
  });

  context('computeProportionalAmountsIn', () => {
    it('computes correct proportional amounts in', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const bptTotalSupply = bn(300e18);
      const bptAmountOut = bn(30e18);

      const expected = computeProportionalAmountsIn(balances, bptTotalSupply, bptAmountOut);
      const result = await math.computeProportionalAmountsIn(balances, bptTotalSupply, bptAmountOut);

      result.forEach((res, index) => {
        expect(res).not.to.be.equal(0n);
        expectEqualWithError(res, expected[index], MAX_RELATIVE_ERROR);
      });
    });
  });

  context('computeProportionalAmountsOut', () => {
    it('computes correct proportional amounts out', async () => {
      const balances = [bn(100e18), bn(200e18)];
      const bptTotalSupply = bn(300e18);
      const bptAmountIn = bn(30e18);

      const expected = computeProportionalAmountsOut(balances, bptTotalSupply, bptAmountIn);
      const result = await math.computeProportionalAmountsOut(balances, bptTotalSupply, bptAmountIn);

      result.forEach((res, index) => {
        expect(res).not.to.be.equal(0n);
        expectEqualWithError(res, expected[index], MAX_RELATIVE_ERROR);
      });
    });
  });

  context('computeAddLiquidityUnbalanced', () => {
    it('computes correct BPT amount out and swap fees for unbalanced liquidity addition', async () => {
      const currentBalances = [bn(100e18), bn(200e18)];
      const exactAmounts = [bn(10e18), bn(20e18)];
      const totalSupply = bn(300e18);

      const { bptAmountOut: expectedBptAmountOut, swapFeeAmounts: expectedSwapFeeAmounts } =
        computeAddLiquidityUnbalanced(currentBalances, exactAmounts, totalSupply, SWAP_FEE, computeInvariantMock);

      const result = await math.computeAddLiquidityUnbalanced(currentBalances, exactAmounts, totalSupply, SWAP_FEE);

      expect(result.bptAmountOut).not.to.be.equal(0n);
      expectEqualWithError(result.bptAmountOut, expectedBptAmountOut, MAX_RELATIVE_ERROR);
      result.swapFeeAmounts.forEach((res, i) => {
        expectEqualWithError(result.swapFeeAmounts[i], expectedSwapFeeAmounts[i], MAX_RELATIVE_ERROR);
      });
    });
  });

  // context('computeAddLiquiditySingleTokenExactOut', () => {
  //   it('computes correct input amount for single-token liquidity addition', async () => {
  //     const currentBalances = [bn(100e18), bn(200e18)];
  //     const tokenInIndex = 0;
  //     const exactBptAmountOut = bn(30e18);
  //     const totalSupply = bn(300e18);
  //     const computeBalance = (balances: BigNumberish[], index: number, ratio: Decimal) => {
  //       // Dummy balance computation for test purposes
  //       return fromFp(balances[index]).mul(ratio);
  //     };

  //     const { amountInWithFee: expectedAmountInWithFee, swapFeeAmounts: expectedSwapFeeAmounts } =
  //       computeAddLiquiditySingleTokenExactOut(
  //         currentBalances,
  //         tokenInIndex,
  //         exactBptAmountOut,
  //         totalSupply,
  //         SWAP_FEE,
  //         computeBalance
  //       );

  //     const result = await math.computeAddLiquiditySingleTokenExactOut(
  //       currentBalances,
  //       tokenInIndex,
  //       exactBptAmountOut,
  //       totalSupply,
  //       SWAP_FEE,
  //       computeBalance
  //     );

  //     expectEqualWithError(result.amountInWithFee, expectedAmountInWithFee, MAX_RELATIVE_ERROR);
  //     expectEqualWithError(result.swapFeeAmounts, expectedSwapFeeAmounts, MAX_RELATIVE_ERROR);
  //   });
  // });

  // context('computeRemoveLiquiditySingleTokenExactOut', () => {
  //   it('computes correct BPT amount in for exact single-token withdrawal', async () => {
  //     const currentBalances = [bn(100e18), bn(200e18)];
  //     const tokenOutIndex = 0;
  //     const exactAmountOut = bn(10e18);
  //     const totalSupply = bn(300e18);
  //     const computeInvariant = (balances: BigNumberish[]) => {
  //       // Dummy invariant computation for test purposes
  //       return balances.reduce((a, b) => bn(a).add(b), bn(0));
  //     };

  //     const { bptAmountIn: expectedBptAmountIn, swapFeeAmounts: expectedSwapFeeAmounts } =
  //       computeRemoveLiquiditySingleTokenExactOut(
  //         currentBalances,
  //         tokenOutIndex,
  //         exactAmountOut,
  //         totalSupply,
  //         SWAP_FEE,
  //         computeInvariant
  //       );

  //     const result = await math.computeRemoveLiquiditySingleTokenExactOut(
  //       currentBalances,
  //       tokenOutIndex,
  //       exactAmountOut,
  //       totalSupply,
  //       SWAP_FEE,
  //       computeInvariant
  //     );

  //     expectEqualWithError(result.bptAmountIn, expectedBptAmountIn, MAX_RELATIVE_ERROR);
  //     expectEqualWithError(result.swapFeeAmounts, expectedSwapFeeAmounts, MAX_RELATIVE_ERROR);
  //   });
  // });

  // context('computeRemoveLiquiditySingleTokenExactIn', () => {
  //   it('computes correct token amount out for exact BPT amount in', async () => {
  //     const currentBalances = [bn(100e18), bn(200e18)];
  //     const tokenOutIndex = 0;
  //     const exactBptAmountIn = bn(30e18);
  //     const totalSupply = bn(300e18);
  //     const computeBalance = (balances: bigint[], index: number, ratio: Decimal) => {
  //       // Dummy balance computation for test purposes
  //       return fromFp(balances[index]).mul(ratio);
  //     };

  //     const { amountOutWithFee: expectedAmountOutWithFee, swapFeeAmounts: expectedSwapFeeAmounts } =
  //       computeRemoveLiquiditySingleTokenExactIn(
  //         currentBalances,
  //         tokenOutIndex,
  //         exactBptAmountIn,
  //         totalSupply,
  //         SWAP_FEE,
  //         computeBalance
  //       );

  //     const result = await math.computeRemoveLiquiditySingleTokenExactIn(
  //       currentBalances,
  //       tokenOutIndex,
  //       exactBptAmountIn,
  //       totalSupply,
  //       SWAP_FEE,
  //       computeBalance
  //     );

  //     expectEqualWithError(result.amountOutWithFee, expectedAmountOutWithFee, MAX_RELATIVE_ERROR);
  //     expectEqualWithError(result.swapFeeAmounts, expectedSwapFeeAmounts, MAX_RELATIVE_ERROR);
  //   });
  // });
});
