import { expect } from 'chai';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256 } from '@balancer-labs/v3-helpers/src/constants';
import { fp, fpDivDown, fpDivUp } from '@balancer-labs/v3-helpers/src/numbers';
import { ERC20TestToken__factory } from '@balancer-labs/v3-solidity-utils/typechain-types';

import { BatchSwapBaseTest, WRAPPED_TOKEN_AMOUNT } from './BatchSwapBase';

describe('PrepaidBatchSwap', function () {
  const baseTest = new BatchSwapBaseTest(true);
  baseTest.pathMaxAmountIn = fp(2);

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
      context('should revert if path is incorrect', () => {
        it('should revert if the step.pool is tokenIn', async () => {
          expect(
            baseTest.aggregatorRouter.connect(baseTest.sender).swapExactIn(
              [
                {
                  tokenIn: baseTest.token0,
                  steps: [{ pool: baseTest.token0, tokenOut: baseTest.token1, isBuffer: false }],
                  exactAmountIn: baseTest.pathExactAmountIn,
                  minAmountOut: baseTest.pathMinAmountOut,
                },
              ],
              MAX_UINT256,
              false,
              '0x'
            )
          ).to.be.revertedWithCustomError(baseTest.aggregatorRouter, 'OperationNotSupported');
        });
        it('should revert if the step.pool is baseTest.tokensOut', async () => {
          expect(
            baseTest.aggregatorRouter.connect(baseTest.sender).swapExactIn(
              [
                {
                  tokenIn: baseTest.token0,
                  steps: [{ pool: baseTest.token1, tokenOut: baseTest.token0, isBuffer: false }],
                  exactAmountIn: baseTest.pathExactAmountIn,
                  minAmountOut: baseTest.pathMinAmountOut,
                },
              ],
              MAX_UINT256,
              false,
              '0x'
            )
          ).to.be.revertedWithCustomError(baseTest.aggregatorRouter, 'OperationNotSupported');
        });
      });
      context('single path', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = baseTest.pathAmountsOut; // 1 path, 1 token out

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.totalAmountIn
            )
          ).wait();
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, true);
      });

      context('single path, first - intermediate - final steps', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut]; // 1 path, all tokens out
          baseTest.amountsOut = baseTest.pathAmountsOut; // 1 path, 1 token out

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.totalAmountIn
            )
          ).wait();
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

        baseTest.itTestsBatchSwapExactIn(false, true);
      });

      context('multi path, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactIn, single token output

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.totalAmountIn
            )
          ).wait();
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

        baseTest.itTestsBatchSwapExactIn(false, true);
      });

      context('multi path, MISO', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactIn, single token output

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathExactAmountIn
            )
          ).wait();
          await (
            await ERC20TestToken__factory.connect(baseTest.token1, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathExactAmountIn
            )
          ).wait();
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
          baseTest.tokensOut = [baseTest.tokens.get(2), baseTest.tokens.get(1)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = baseTest.pathAmountsOut; // 2 baseTest.pathsExactIn, 2 outputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', baseTest.pathMinAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', -baseTest.pathMinAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.totalAmountIn
            )
          ).wait();
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

        baseTest.itTestsBatchSwapExactIn(false, false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [baseTest.tokens.get(2), baseTest.poolC];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = baseTest.pathAmountsOut; // 2 baseTest.pathsExactIn, 2 outputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', baseTest.pathMinAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathMinAmountOut],
                [await baseTest.tokensOut[1].symbol()]: ['equal', -baseTest.pathMinAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathExactAmountIn
            )
          ).wait();
          await (
            await ERC20TestToken__factory.connect(await baseTest.poolA.getAddress(), baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathExactAmountIn
            )
          ).wait();
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

      context('unwrap first, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactIn, single token output

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['very-near', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.wToken0Address, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.totalAmountIn
            )
          ).wait();
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError,
            },
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, true);
      });

      context('unwrap first - wrap end, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [ERC20TestToken__factory.connect(baseTest.wToken2Address, baseTest.sender)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokens.get(2).symbol()]: ['very-near', -1n * fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
                [await baseTest.tokensOut[0].symbol()]: ['very-near', fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
            {
              account: baseTest.wToken2Address,
              changes: {
                [await baseTest.tokens.get(2).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.wToken0Address, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.totalAmountIn
            )
          ).wait();
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.wToken2, isBuffer: true },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError * 2n,
            },
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.wToken2, isBuffer: true },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError * 2n,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, true);
      });

      context('wrap first - unwrap end, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathExactAmountIn * 2n; // 2 baseTest.pathsExactIn
          baseTest.totalAmountOut = baseTest.pathMinAmountOut * 2n; // 2 baseTest.pathsExactIn, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsOut = [baseTest.totalAmountOut / 2n, baseTest.totalAmountOut / 2n]; // 2 baseTest.pathsExactIn, half the output in each
          baseTest.amountsOut = [baseTest.totalAmountOut];

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensOut[0].symbol()]: ['very-near', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokens.get(2).symbol()]: ['very-near', -baseTest.totalAmountOut],
                [await baseTest.tokens.get(0).symbol()]: ['very-near', -1n * fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
                [await baseTest.wToken0.symbol()]: ['very-near', fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
            {
              account: baseTest.wToken0Address,
              changes: {
                [await baseTest.tokens.get(0).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.totalAmountIn
            )
          ).wait();
          baseTest.pathsExactIn = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.wToken0, isBuffer: true },
                { pool: baseTest.poolWA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolWB, tokenOut: baseTest.wToken2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.token2, isBuffer: true },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError * 2n,
            },
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.wToken0, isBuffer: true },
                { pool: baseTest.poolWA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolWB, tokenOut: baseTest.wToken2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.token2, isBuffer: true },
              ],
              exactAmountIn: baseTest.pathExactAmountIn,
              minAmountOut: baseTest.pathMinAmountOut - baseTest.roundingError * 2n,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactIn(false, true);
      });
    });
  });

  describe('batch swap given out', () => {
    const expectedAmountToReturn = baseTest.pathMaxAmountIn - baseTest.pathExactAmountOut;
    const expectedAmountIn = baseTest.pathMaxAmountIn - expectedAmountToReturn;

    context('pure swaps with no nesting', () => {
      it('should revert if the step.pool is tokenIn', async () => {
        expect(
          baseTest.aggregatorRouter.connect(baseTest.sender).swapExactOut(
            [
              {
                tokenIn: baseTest.token0,
                steps: [{ pool: baseTest.token0, tokenOut: baseTest.token1, isBuffer: false }],
                exactAmountOut: baseTest.pathExactAmountOut,
                maxAmountIn: baseTest.pathMaxAmountIn,
              },
            ],
            MAX_UINT256,
            false,
            '0x'
          )
        ).to.be.revertedWithCustomError(baseTest.aggregatorRouter, 'OperationNotSupported');
      });
      it('should revert if the step.pool is baseTest.tokensOut', async () => {
        expect(
          baseTest.aggregatorRouter.connect(baseTest.sender).swapExactOut(
            [
              {
                tokenIn: baseTest.token0,
                steps: [{ pool: baseTest.token1, tokenOut: baseTest.token0, isBuffer: false }],
                exactAmountOut: baseTest.pathExactAmountOut,
                maxAmountIn: baseTest.pathMaxAmountIn,
              },
            ],
            MAX_UINT256,
            false,
            '0x'
          )
        ).to.be.revertedWithCustomError(baseTest.aggregatorRouter, 'OperationNotSupported');
      });

      context('single path', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn]; // 1 path, all tokens out
          baseTest.amountsIn = [expectedAmountIn]; // 1 path

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
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

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('single path, first - intermediate - final steps', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = baseTest.pathMaxAmountIn; // 1 path
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn]; // 1 path, all tokens out
          baseTest.amountsIn = [expectedAmountIn]; // 1 path

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
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

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('multi path, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          const maxAmountIn = baseTest.pathMaxAmountIn * 2n;
          baseTest.totalAmountIn = expectedAmountIn * 2n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = baseTest.pathExactAmountOut * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactOut, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              maxAmountIn
            )
          ).wait();
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

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('multi path, MISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0), baseTest.tokens.get(1)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = expectedAmountIn * 2n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = baseTest.pathExactAmountOut * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = baseTest.pathAmountsIn; // 2 baseTest.pathsExactOut, multiple token inputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await baseTest.tokensIn[1].symbol()]: ['equal', expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await baseTest.tokensIn[1].symbol()]: ['equal', -expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
          await (
            await ERC20TestToken__factory.connect(baseTest.token1, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
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

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          const maxAmountIn = baseTest.pathMaxAmountIn * 2n;

          baseTest.totalAmountIn = expectedAmountIn * 2n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountIn]; // 2 baseTest.pathsExactOut, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', baseTest.pathExactAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -baseTest.pathExactAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              maxAmountIn
            )
          ).wait();
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

        baseTest.itTestsBatchSwapExactOut(false, false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0), baseTest.poolA];
          baseTest.tokensOut = [baseTest.tokens.get(2)];
          const secondPathTokenOut = baseTest.poolC;

          baseTest.totalAmountIn = expectedAmountIn * 2n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = baseTest.pathExactAmountOut; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.poolA.symbol()]: ['equal', expectedAmountToReturn],
                [await baseTest.tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', baseTest.pathExactAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.poolA.symbol()]: ['equal', -expectedAmountToReturn],
                [await baseTest.tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -baseTest.pathExactAmountOut],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
          await (
            await ERC20TestToken__factory.connect(await baseTest.poolA.getAddress(), baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
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

      context('unwrap first, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [ERC20TestToken__factory.connect(baseTest.wToken0Address, baseTest.sender)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          const maxAmountIn = baseTest.pathMaxAmountIn * 2n;
          baseTest.totalAmountIn = expectedAmountIn * 2n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = baseTest.pathExactAmountOut * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactOut, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.totalAmountOut],
              },
            },
          ];

          await (await baseTest.tokensIn[0].transfer(baseTest.vault, maxAmountIn)).wait();
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('unwrap first - wrap end, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [ERC20TestToken__factory.connect(baseTest.wToken0Address, baseTest.sender)];
          baseTest.tokensOut = [ERC20TestToken__factory.connect(baseTest.wToken2Address, baseTest.sender)];

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          const maxAmountIn = baseTest.pathMaxAmountIn * 2n;
          baseTest.totalAmountIn = expectedAmountIn * 2n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = baseTest.pathExactAmountOut * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactOut, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', -totalAmountToReturn],
                [await baseTest.tokens.get(2).symbol()]: ['very-near', -1n * fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
                [await baseTest.tokensOut[0].symbol()]: [
                  'very-near',
                  fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2)) - baseTest.totalAmountOut,
                ], // Rebalancing
              },
            },
            {
              account: baseTest.wToken2Address,
              changes: {
                [await baseTest.tokens.get(2).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (await baseTest.tokensIn[0].transfer(baseTest.vault, maxAmountIn)).wait();
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.wToken2, isBuffer: true },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.wToken0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.token0, isBuffer: true },
                { pool: baseTest.poolA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolB, tokenOut: baseTest.token2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.wToken2, isBuffer: true },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('wrap first - unwrap end, SISO', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          const maxAmountIn = baseTest.pathMaxAmountIn * 2n;
          baseTest.totalAmountIn = expectedAmountIn * 2n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = baseTest.pathExactAmountOut * 2n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = [baseTest.totalAmountOut]; // 2 baseTest.pathsExactOut, single token input

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['very-near', totalAmountToReturn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.totalAmountOut],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokens.get(2).symbol()]: ['equal', -baseTest.totalAmountOut],
                [await baseTest.tokensIn[0].symbol()]: [
                  'very-near',
                  -1n * fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2)) - totalAmountToReturn,
                ], // Rebalancing
                [await baseTest.wToken0.symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
            {
              account: baseTest.wToken0Address,
              changes: {
                [await baseTest.tokens.get(0).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              maxAmountIn
            )
          ).wait();
          baseTest.pathsExactOut = [
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.wToken0, isBuffer: true },
                { pool: baseTest.poolWA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolWB, tokenOut: baseTest.wToken2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.token2, isBuffer: true },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
            {
              tokenIn: baseTest.token0,
              steps: [
                { pool: baseTest.wToken0, tokenOut: baseTest.wToken0, isBuffer: true },
                { pool: baseTest.poolWA, tokenOut: baseTest.token1, isBuffer: false },
                { pool: baseTest.poolWB, tokenOut: baseTest.wToken2, isBuffer: false },
                { pool: baseTest.wToken2, tokenOut: baseTest.token2, isBuffer: true },
              ],
              exactAmountOut: baseTest.pathExactAmountOut,
              maxAmountIn: baseTest.pathMaxAmountIn,
            },
          ];
        });

        baseTest.itTestsBatchSwapExactOut(false, true);
      });

      context('multi path, circular inputs/outputs', () => {
        beforeEach(async () => {
          baseTest.tokensIn = [baseTest.tokens.get(0), baseTest.tokens.get(2)];
          baseTest.tokensOut = [baseTest.tokens.get(2)];

          baseTest.totalAmountIn = 0n; // 2 baseTest.pathsExactOut
          baseTest.totalAmountOut = 0n; // 2 baseTest.pathsExactOut, 1:1 ratio between inputs and outputs
          baseTest.pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 baseTest.pathsExactOut, half the output in each
          baseTest.amountsIn = baseTest.pathAmountsIn; // 2 baseTest.pathsExactOut, 2 circular inputs

          baseTest.balanceChange = [
            {
              account: baseTest.sender,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', baseTest.pathMaxAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', baseTest.pathMaxAmountIn],
              },
            },
            {
              account: baseTest.vaultAddress,
              changes: {
                [await baseTest.tokensIn[0].symbol()]: ['equal', -baseTest.pathMaxAmountIn],
                [await baseTest.tokensOut[0].symbol()]: ['equal', -baseTest.pathMaxAmountIn],
              },
            },
          ];

          await (
            await ERC20TestToken__factory.connect(baseTest.token0, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
          await (
            await ERC20TestToken__factory.connect(baseTest.token2, baseTest.sender).transfer(
              baseTest.vault,
              baseTest.pathMaxAmountIn
            )
          ).wait();
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
  });
});
