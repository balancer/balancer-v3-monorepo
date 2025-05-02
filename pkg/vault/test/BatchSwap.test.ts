import { expect } from 'chai';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { pct } from '@balancer-labs/v3-helpers/src/numbers';

import { BatchSwapBaseTest } from './BatchSwapBase';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';

describe('BatchSwap', function () {
  const baseTest = new BatchSwapBaseTest(false);

  before('setup signers', async () => {
    await baseTest.setUpSigners();
  });

  sharedBeforeEach('setup test', async function () {
    await baseTest.deployContracts();
    await baseTest.setUpNestedPools();
    await baseTest.setUpAllowances();
    await baseTest.initPools();
  });

  // This checks that the Batch Router is not susceptible to DDoS attacks by dusting the Vault.
  sharedBeforeEach('add some dust to the Vault (DDoS check)', async () => {
    await baseTest.tokens.mint({ to: baseTest.vault, amount: 1234 });
    await Promise.all(baseTest.pools.map((pool) => pool.connect(baseTest.lp).transfer(baseTest.vault, 12345)));
  });

  afterEach('clean up expected results and inputs', () => {
    baseTest.cleanVariables();
  });

  describe('common tests', () => {
    baseTest.itCommonTests();
  });

  describe('batch swap given in', () => {
    context('pure swaps with no nesting', () => {
      context('single path', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = baseTest.pathAmountsOut; // 1 path, 1 token out

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn();
      });

      context('single path, first - intermediate - final steps', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = baseTest.pathAmountsOut; // 1 path, 1 token out

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
                { pool: baseTest.poolC, tokenOut: baseTest.token0, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn();
      });

      context('multi path, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactIn, single token output

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
            {
              tokenIn: baseTest.token0,
              steps: [{ pool: baseTest.poolC, tokenOut: baseTest.token2, isBuffer: false }],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn();
      });

      context('multi path, MISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];
          const secondPathTokenIn = baseTest.tokens.get(1);

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactIn, single token output

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.pathExactAmountIn],
                [await secondPathTokenIn.symbol()]: ['equal', -baseTest.pathExactAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.pathMinAmountOut],
                [await secondPathTokenIn.symbol()]: ['equal', baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
            {
              tokenIn: baseTest.token1,
              steps: [{ pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false }],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, true);
      });

      context('multi path, SIMO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2), baseTest.tokens.get(1)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = baseTest.pathAmountsOut; // 2 baseTest.pathsExactIn, 2 outputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', baseTest.pathMinAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', -baseTest.pathMinAmountOut],
              },
            },
          ];
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
            {
              tokenIn: baseTest.token0,
              steps: [{ pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false }],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(true, false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2), baseTest.poolC];
          const secondPathTokenIn = baseTest.poolA;

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = baseTest.pathAmountsOut; // 2 baseTest.pathsExactIn, 2 outputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.pathExactAmountIn],
                [await secondPathTokenIn.symbol()]: ['equal', -baseTest.pathExactAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', baseTest.pathMinAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.pathExactAmountIn],
                [await secondPathTokenIn.symbol()]: ['equal', baseTest.pathExactAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', -baseTest.pathMinAmountOut],
              },
            },
          ];
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
            {
              tokenIn: baseTest.poolA,
              steps: [
                { pool: baseTest.poolAB, tokenOut: baseTest.poolB, isBuffer: false },
                { pool: baseTest.poolBC, tokenOut: baseTest.poolC, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, false);
      });

      context('multi path, circular inputs/outputs', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2), baseTest.tokens.get(0)];

          baseTest.totalAmountIn = 0n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = 0n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.pathMinAmountOut, baseTest.pathMinAmountOut]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = baseTest.pathAmountsOut; // 2 baseTest.pathsExactIn, 2 different outputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', 0],
                [await baseTest.tokensOut[0].symbol()]: ['equal', 0],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', 0],
                [await baseTest.tokensOut[1].symbol()]: ['equal', 0],
              },
            },
          ];
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
            {
              tokenIn: baseTest.token2,
              steps: [{ pool: baseTest.poolC, tokenOut: baseTest.token0, isBuffer: false }],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, false);
      });
    });

    context('joinswaps (add liquidity step)', () => {
      context('single path - initial add liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.poolB];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolAB, tokenOut: baseTest.poolB, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn();
      });

      context('single path - intermediate add liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.poolC];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.poolB, isBuffer: false },
                { pool: baseTest.poolBC, tokenOut: baseTest.poolC, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn();
      });

      context('multi path - initial and final add liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.poolB];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolAB, tokenOut: baseTest.poolB, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError,
            },
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.poolB, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError,
            },
          ];
        });

        // The second step of the second path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        baseTest.itTestsBatchSwapExactIn(true, false);
      });
    });

    context('exitswaps (remove liquidity step)', () => {
      context('single path - initial remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.poolA];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.poolA,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, true);
      });

      context('single path - intermediate remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: pct(baseTest.pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];
        });
        // There are rounding issues in the output transfer, so we skip it.
        baseTest.itTestsBatchSwapExactIn(true, false);
      });

      context('single path - final remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(1)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: pct(baseTest.pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];
        });

        // The first step of first path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        // There are rounding issues in the output transfer, so we skip it.
        baseTest.itTestsBatchSwapExactIn(false, false);
      });

      context('multi path - final remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(1)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: pct(baseTest.pathMinAmountOut, 0.999), // Rounding tolerance
            },
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolC, tokenOut: baseTest.poolC, isBuffer: false },
                { pool: baseTest.poolBC, tokenOut: baseTest.poolB, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token1, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: pct(baseTest.pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];
        });

        // The first step of first path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        // There are rounding issues in the output transfer, so we skip it.
        baseTest.itTestsBatchSwapExactIn(false, false);
      });

      context('multi path - mid remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.poolA, baseTest.poolB];
          baseTest.tokensOut = [baseTest.poolC, baseTest.tokens.get(1)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn;
          baseTest.totalAmountOut = baseTest.pathMinAmountOut;
          baseTest.pathAmountsOut = [baseTest.totalAmountOut, baseTest.totalAmountOut];
          baseTest.amountsOut = [baseTest.totalAmountOut, baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
                [await baseTest.tokensIn[1].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[1].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
                [await baseTest.tokensIn[1].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[1].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.poolA,
              steps: [{ pool: baseTest.poolAC, tokenOut: baseTest.poolC, isBuffer: false }],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: pct(baseTest.pathMinAmountOut, 0.999), // Rounding tolerance
            },
            {
              tokenIn: baseTest.poolB,
              steps: [
                { pool: baseTest.poolAB, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: pct(baseTest.pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, false);
      });
    });
  });

  describe('batch swap given out', () => {
    context('pure swaps with no nesting', () => {
      context('single path', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountIn]; // 1 path, all tokens out
          baseTest.amountsIn = [baseTest.totalAmountIn]; // 1 path

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut();
      });

      context('single path, first - intermediate - final steps', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountIn]; // 1 path, all tokens out
          baseTest.amountsIn = [baseTest.totalAmountIn]; // 1 path

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
                { pool: baseTest.poolC, tokenOut: baseTest.token0, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut();
      });

      context('multi path, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountOut * 2n; // 2 paths
          baseTest.totalAmountOut = baseTest.pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 paths, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountOut]; // 2 paths, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.token0,
              steps: [{ pool: baseTest.poolC, tokenOut: baseTest.token2, isBuffer: false }],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut();
      });

      context('multi path, MISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0), baseTest.tokens.get(1)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountOut * 2n; // 2 paths
          baseTest.totalAmountOut = baseTest.pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 paths, half the output in each
          baseTest.amountsIn = baseTest.pathAmountsIn; // 2 paths, multiple token inputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.pathMaxAmountIn],
                [await baseTest.tokensIn[1].symbol()]: ['equal', -baseTest.pathMaxAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.pathMaxAmountIn],
                [await baseTest.tokensIn[1].symbol()]: ['equal', baseTest.pathMaxAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.token1,
              steps: [{ pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false }],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('multi path, SIMO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];
          const secondPathTokenOut = baseTest.tokens.get(1);

          baseTest.totalAmountIn = baseTest.pathExactAmountOut * 2n; // 2 paths
          baseTest.totalAmountOut = baseTest.pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 paths, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountIn]; // 2 paths, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', baseTest.pathExactAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -baseTest.pathExactAmountOut],
              },
            },
          ];
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.token0,
              steps: [{ pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false }],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(true, false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0), baseTest.poolA];
          baseTest.tokensOut = [baseTest.tokens.get(2)];
          const secondPathTokenOut = baseTest.poolC;

          baseTest.totalAmountIn = baseTest.pathExactAmountOut * 2n; // 2 paths
          baseTest.totalAmountOut = baseTest.pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 paths, half the output in each
          baseTest.amountsIn = baseTest.pathAmountsIn; // 2 paths, multiple token inputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.pathMaxAmountIn],
                [await baseTest.tokensIn[1].symbol()]: ['equal', -baseTest.pathMaxAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', baseTest.pathExactAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.pathMaxAmountIn],
                [await baseTest.tokensIn[1].symbol()]: ['equal', baseTest.pathMaxAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -baseTest.pathExactAmountOut],
              },
            },
          ];
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.poolA,
              steps: [
                { pool: baseTest.poolAB, tokenOut: baseTest.poolB, isBuffer: false },
                { pool: baseTest.poolBC, tokenOut: baseTest.poolC, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, false);
      });

      context('multi path, circular inputs/outputs', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0), baseTest.tokens.get(2)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];
          const secondPathTokenOut = baseTest.tokens.get(0);

          baseTest.totalAmountIn = 0n; // 2 paths
          baseTest.totalAmountOut = 0n; // 2 paths, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.pathMaxAmountIn, baseTest.pathMaxAmountIn]; // 2 paths, half the output in each
          baseTest.amountsIn = baseTest.pathAmountsIn; // 2 paths, 2 circular inputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', 0],
                [await baseTest.tokensOut[0].symbol()]: ['equal', 0],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', 0],
                [await secondPathTokenOut.symbol()]: ['equal', 0],
              },
            },
          ];
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.token2,
              steps: [{ pool: baseTest.poolC, tokenOut: baseTest.token0, isBuffer: false }],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, false);
      });
    });

    context('joinswaps (add liquidity step)', () => {
      context('single path - first add liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.poolB];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsIn = [baseTest.totalAmountIn];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolAB, tokenOut: baseTest.poolB, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut();
      });

      context('multi path - first and intermediate add liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.poolB];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn * 2n; // 2 paths
          baseTest.totalAmountOut = baseTest.pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 paths, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountIn];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolAB, tokenOut: baseTest.poolB, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.poolB, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        // The second step of the second path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        baseTest.itTestsBatchSwapExactOut(true, false);
      });

      context('single path - final add liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.poolB];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsIn = [baseTest.totalAmountIn];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.poolB, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(true, false);

        it('mints amount out', async () => {
          await expect(baseTest.doSwapExactOut())
            .to.emit(baseTest.tokensOut[0], 'Transfer')
            .withArgs(ZERO_ADDRESS, baseTest.sender.address, baseTest.totalAmountOut);
        });
      });
    });

    context('exitswaps (remove liquidity step)', () => {
      context('single path - first remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.poolA];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsIn = [baseTest.totalAmountIn];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.poolA,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn + baseTest.roundingError,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, true);

        it('burns amount in', async () => {
          // Some operations have rounding error, and event arguments are precise. So we get the result from
          // the query to check the event arguments.
          const { amountsIn } = await baseTest.runQueryExactOut();

          // Router is the one that burns the baseTest.tokens, not baseTest.sender.
          await expect(baseTest.doSwapExactOut())
            .to.emit(baseTest.tokensIn[0], 'Transfer')
            .withArgs(baseTest.router, ZERO_ADDRESS, amountsIn[0]);
        });
      });

      context('single path - intermediate remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.poolC];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsIn = [baseTest.totalAmountIn];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.poolC,
              steps: [
                { pool: baseTest.poolAC, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn + baseTest.roundingError,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('single path - final remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.poolA];
          baseTest.tokensOut = [baseTest.tokens.get(1)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsIn = [baseTest.totalAmountIn];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.poolA,
              steps: [
                { pool: baseTest.poolAB, tokenOut: baseTest.poolB, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token1, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn + baseTest.roundingError,
            },
          ];
        });

        // Rounding errors don't allow testing precise transfers for amount out.
        baseTest.itTestsBatchSwapExactOut(true, false);
      });

      context('multi path - final remove liquidity step', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(1)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn * 2n; // 2 paths
          baseTest.totalAmountOut = baseTest.pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 paths, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountIn];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', baseTest.totalAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.poolA, isBuffer: false },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: pct(baseTest.pathMaxAmountIn, 1.001), // Rounding tolerance
            },
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolC, tokenOut: baseTest.poolC, isBuffer: false },
                { pool: baseTest.poolBC, tokenOut: baseTest.poolB, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token1, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: pct(baseTest.pathMaxAmountIn, 1.001), // Rounding tolerance
            },
          ];
        });

        // The first step of both paths are an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount in as argument.
        // Rounding errors make the output inexact, so we skip the transfer checks.
        baseTest.itTestsBatchSwapExactOut(false, false);
      });
    });
  });
});
