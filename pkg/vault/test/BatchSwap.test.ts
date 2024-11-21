import { ethers } from 'hardhat';
import { VoidSigner } from 'ethers';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { fp, pct } from '@balancer-labs/v3-helpers/src/numbers';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';

import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import { BatchRouter, Router, PoolFactoryMock, Vault } from '../typechain-types';
import { BalanceChange, expectBalanceChange } from '@balancer-labs/v3-helpers/src/test/tokenBalance';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { buildTokenConfig } from './poolSetup';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from './Permit2Deployer';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { IBatchRouter } from '@balancer-labs/v3-interfaces/typechain-types';

describe('BatchSwap', function () {
  const BATCH_ROUTER_VERSION = 'BatchRouter v9';
  const ROUTER_VERSION = 'Router v9';

  let permit2: IPermit2;
  let vault: Vault;
  let factory: PoolFactoryMock;
  let poolA: PoolMock, poolB: PoolMock, poolC: PoolMock;
  let poolAB: PoolMock, poolAC: PoolMock, poolBC: PoolMock;
  let pools: PoolMock[];
  let tokens: ERC20TokenList;
  let router: BatchRouter, basicRouter: Router;

  let lp: SignerWithAddress, sender: SignerWithAddress, zero: VoidSigner;

  let poolATokens: string[], poolBTokens: string[], poolCTokens: string[];
  let poolABTokens: string[], poolACTokens: string[], poolBCTokens: string[];
  let token0: string, token1: string, token2: string;
  let vaultAddress: string;

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, lp, sender] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await VaultDeployer.deploy();
    vaultAddress = await vault.getAddress();
    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await deploy('BatchRouter', { args: [vaultAddress, WETH, permit2, BATCH_ROUTER_VERSION] });
    basicRouter = await deploy('Router', { args: [vaultAddress, WETH, permit2, ROUTER_VERSION] });

    factory = await deploy('PoolFactoryMock', { args: [vaultAddress, 12 * MONTH] });

    tokens = await ERC20TokenList.create(3, { sorted: true });
    token0 = await tokens.get(0).getAddress();
    token1 = await tokens.get(1).getAddress();
    token2 = await tokens.get(2).getAddress();
    poolATokens = sortAddresses([token0, token1]);
    poolBTokens = sortAddresses([token1, token2]);
    poolCTokens = sortAddresses([token0, token2]);

    // Pool A has tokens 0 and 1.
    poolA = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool A', 'POOL-A'],
    });

    // Pool A has tokens 1 and 2.
    poolB = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool B', 'POOL-B'],
    });

    // Pool C has tokens 0 and 2.
    poolC = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool C', 'POOL-C'],
    });

    await factory.registerTestPool(poolA, buildTokenConfig(poolATokens));
    await factory.registerTestPool(poolB, buildTokenConfig(poolBTokens));
    await factory.registerTestPool(poolC, buildTokenConfig(poolCTokens));
  });

  sharedBeforeEach('nested pools', async () => {
    poolABTokens = sortAddresses([await poolA.getAddress(), await poolB.getAddress()]);
    poolAB = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool A-B', 'POOL-AB'],
    });

    poolACTokens = sortAddresses([await poolA.getAddress(), await poolC.getAddress()]);
    poolAC = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool A-C', 'POOL-AC'],
    });

    poolBCTokens = sortAddresses([await poolB.getAddress(), await poolC.getAddress()]);
    poolBC = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool B-C', 'POOL-BC'],
    });

    await factory.registerTestPool(poolAB, buildTokenConfig(poolABTokens));
    await factory.registerTestPool(poolAC, buildTokenConfig(poolACTokens));
    await factory.registerTestPool(poolBC, buildTokenConfig(poolBCTokens));
  });

  sharedBeforeEach('allowances', async () => {
    pools = [poolA, poolB, poolC, poolAB, poolAC, poolBC];

    await tokens.mint({ to: lp, amount: fp(1e12) });
    await tokens.mint({ to: sender, amount: fp(1e12) });
    for (const pool of pools) {
      await pool.connect(lp).approve(router, MAX_UINT256);
      await pool.connect(lp).approve(basicRouter, MAX_UINT256);
    }
    for (const token of [...tokens.tokens, poolA, poolB, poolC, poolAB, poolAC, poolBC]) {
      for (const from of [lp, sender]) {
        await token.connect(from).approve(permit2, MAX_UINT256);
        for (const to of [router, basicRouter]) {
          await permit2.connect(from).approve(token, to, MAX_UINT160, MAX_UINT48);
        }
      }
    }
  });

  sharedBeforeEach('initialize pools', async () => {
    await basicRouter
      .connect(lp)
      .initialize(poolA, poolATokens, Array(poolATokens.length).fill(fp(10000)), 0, false, '0x');
    await basicRouter
      .connect(lp)
      .initialize(poolB, poolBTokens, Array(poolBTokens.length).fill(fp(10000)), 0, false, '0x');
    await basicRouter
      .connect(lp)
      .initialize(poolC, poolCTokens, Array(poolCTokens.length).fill(fp(10000)), 0, false, '0x');

    await basicRouter
      .connect(lp)
      .initialize(poolAB, poolABTokens, Array(poolABTokens.length).fill(fp(1000)), 0, false, '0x');
    await basicRouter
      .connect(lp)
      .initialize(poolAC, poolACTokens, Array(poolACTokens.length).fill(fp(1000)), 0, false, '0x');
    await basicRouter
      .connect(lp)
      .initialize(poolBC, poolBCTokens, Array(poolBCTokens.length).fill(fp(1000)), 0, false, '0x');

    await poolA.connect(lp).transfer(sender, fp(100));
    await poolB.connect(lp).transfer(sender, fp(100));
    await poolC.connect(lp).transfer(sender, fp(100));
  });

  // This checks that the Batch Router is not susceptible to DDoS attacks by dusting the Vault.
  sharedBeforeEach('add some dust to the Vault (DDoS check)', async () => {
    await tokens.mint({ to: vault, amount: 1234 });
    await Promise.all(pools.map((pool) => pool.connect(lp).transfer(vault, 12345)));
  });

  describe('batch swap given in', () => {
    let doSwap: () => Promise<unknown>;
    let doSwapStatic: () => Promise<{
      pathAmountsOut: bigint[];
      tokensOut: string[];
      amountsOut: bigint[];
    }>;
    let runQuery: () => Promise<{
      pathAmountsOut: bigint[];
      tokensOut: string[];
      amountsOut: bigint[];
    }>;
    let tokensIn: (ERC20TestToken | PoolMock)[];
    let tokensOut: (ERC20TestToken | PoolMock)[];
    const pathExactAmountIn = fp(1);
    const pathMinAmountOut = fp(1);
    const unbalancedAddRoundingError = 2n;

    let totalAmountIn: bigint, totalAmountOut: bigint, pathAmountsOut: bigint[], amountsOut: bigint[];
    let balanceChange: BalanceChange[];
    let paths: IBatchRouter.SwapPathExactAmountInStruct[];

    function setUp() {
      const _doSwap = async (isStatic: boolean) =>
        (isStatic ? router.connect(sender).swapExactIn.staticCall : router.connect(sender).swapExactIn)(
          paths,
          MAX_UINT256,
          false,
          '0x'
        );
      doSwap = async () => _doSwap(false);
      doSwapStatic = async () =>
        _doSwap(true) as unknown as {
          pathAmountsOut: bigint[];
          tokensOut: string[];
          amountsOut: bigint[];
        };
      runQuery = async () => router.connect(zero).querySwapExactIn.staticCall(paths, zero.address, '0x');
    }

    function itTestsBatchSwap(singleTransferIn = true, singleTransferOut = true) {
      it('performs swap, transfers tokens', async () => {
        await expectBalanceChange(doSwap, tokens, balanceChange);
      });

      if (singleTransferIn) {
        it('performs single transfer for token in', async () => {
          await expect(doSwap()).to.emit(tokensIn[0], 'Transfer').withArgs(sender.address, vaultAddress, totalAmountIn);
        });
      }

      if (singleTransferOut) {
        it('performs single transfer for token out', async () => {
          // Some operations have rounding error, and event arguments are precise. So we get the result from
          // the query to check the event arguments.
          const { amountsOut } = await runQuery();
          await expect(doSwap())
            .to.emit(tokensOut[0], 'Transfer')
            .withArgs(vaultAddress, sender.address, amountsOut[0]);
        });
      }

      it('returns path amounts out', async () => {
        const calculatedPathAmountsOut = (await doSwapStatic()).pathAmountsOut;
        calculatedPathAmountsOut.map((pathAmountOut, i) =>
          expect(pathAmountOut).to.be.almostEqual(pathAmountsOut[i], 1e-8)
        );
      });

      it('returns tokens out', async () => {
        const calculatedTokensOut = (await doSwapStatic()).tokensOut;
        expect(calculatedTokensOut).to.be.deep.eq(
          await Promise.all(tokensOut.map(async (tokenOut) => await tokenOut.getAddress()))
        );
      });

      it('returns token amounts out', async () => {
        const calculatedAmountsOut = (await doSwapStatic()).amountsOut;
        calculatedAmountsOut.map((amountOut, i) => expect(amountOut).to.be.almostEqual(amountsOut[i], 1e-8));
      });

      it('returns same outputs as query', async () => {
        const realOutputs = await doSwapStatic();
        const queryOutputs = await runQuery();

        expect(realOutputs.pathAmountsOut).to.be.deep.eq(queryOutputs.pathAmountsOut);
        expect(realOutputs.amountsOut).to.be.deep.eq(queryOutputs.amountsOut);
        expect(realOutputs.tokensOut).to.be.deep.eq(queryOutputs.tokensOut);
      });
    }

    afterEach('clean up expected results and inputs', () => {
      tokensIn = undefined;
      tokensOut = undefined;
      totalAmountIn = undefined;
      totalAmountOut = undefined;
      pathAmountsOut = undefined;
      amountsOut = undefined;
      balanceChange = undefined;
      paths = undefined;
    });

    context('pure swaps with no nesting', () => {
      context('single path', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = pathAmountsOut; // 1 path, 1 token out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('single path, first - intermediate - final steps', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = pathAmountsOut; // 1 path, 1 token out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
                { pool: poolC, tokenOut: token0, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path, SISO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut]; // 2 paths, single token output

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: token0,
              steps: [{ pool: poolC, tokenOut: token2, isBuffer: false }],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path, MISO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2)];
          const secondPathTokenIn = tokens.get(1);

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut]; // 2 paths, single token output

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -pathExactAmountIn],
                [await secondPathTokenIn.symbol()]: ['equal', -pathExactAmountIn],
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', pathMinAmountOut],
                [await secondPathTokenIn.symbol()]: ['equal', pathMinAmountOut],
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: token1,
              steps: [{ pool: poolB, tokenOut: token2, isBuffer: false }],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, true);
      });

      context('multi path, SIMO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2), tokens.get(1)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = pathAmountsOut; // 2 paths, 2 outputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', pathMinAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', -pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', -pathMinAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: token0,
              steps: [{ pool: poolA, tokenOut: token1, isBuffer: false }],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(true, false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2), poolC];
          const secondPathTokenIn = poolA;

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = pathAmountsOut; // 2 paths, 2 outputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -pathExactAmountIn],
                [await secondPathTokenIn.symbol()]: ['equal', -pathExactAmountIn],
                [await tokensOut[0].symbol()]: ['equal', pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', pathMinAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', pathExactAmountIn],
                [await secondPathTokenIn.symbol()]: ['equal', pathExactAmountIn],
                [await tokensOut[0].symbol()]: ['equal', -pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', -pathMinAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: poolA,
              steps: [
                { pool: poolAB, tokenOut: poolB, isBuffer: false },
                { pool: poolBC, tokenOut: poolC, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, false);
      });

      context('multi path, circular inputs/outputs', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2), tokens.get(0)];

          totalAmountIn = 0n; // 2 paths
          totalAmountOut = 0n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [pathMinAmountOut, pathMinAmountOut]; // 2 paths, half the output in each
          amountsOut = pathAmountsOut; // 2 paths, 2 different outputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', 0],
                [await tokensOut[0].symbol()]: ['equal', 0],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', 0],
                [await tokensOut[1].symbol()]: ['equal', 0],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: token2,
              steps: [{ pool: poolC, tokenOut: token0, isBuffer: false }],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, false);
      });
    });

    context('joinswaps (add liquidity step)', () => {
      context('single path - initial add liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [poolB];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolAB, tokenOut: poolB, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - unbalancedAddRoundingError,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('single path - intermediate add liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [poolC];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: poolB, isBuffer: false },
                { pool: poolBC, tokenOut: poolC, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - unbalancedAddRoundingError,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path - initial and final add liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [poolB];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolAB, tokenOut: poolB, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - unbalancedAddRoundingError,
            },
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: poolB, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - unbalancedAddRoundingError,
            },
          ];

          setUp();
        });

        // The second step of the second path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        itTestsBatchSwap(true, false);
      });
    });

    context('exitswaps (remove liquidity step)', () => {
      context('single path - initial remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = poolA;
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn.symbol()]: ['equal', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn.symbol()]: ['equal', totalAmountIn],
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: poolA,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, true);
      });

      context('single path - intermediate remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pct(pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];

          setUp();
        });
        // There are rounding issues in the output transfer, so we skip it.
        itTestsBatchSwap(true, false);
      });

      context('single path - final remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(1)];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pct(pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];

          setUp();
        });

        // The first step of first path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        // There are rounding issues in the output transfer, so we skip it.
        itTestsBatchSwap(false, false);
      });

      context('multi path - final remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokensOut = [tokens.get(1)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pct(pathMinAmountOut, 0.999), // Rounding tolerance
            },
            {
              tokenIn: token0,
              steps: [
                { pool: poolC, tokenOut: poolC, isBuffer: false },
                { pool: poolBC, tokenOut: poolB, isBuffer: false },
                { pool: poolB, tokenOut: token1, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pct(pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];

          setUp();
        });

        // The first step of first path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        // There are rounding issues in the output transfer, so we skip it.
        itTestsBatchSwap(false, false);
      });

      context('multi path - mid remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [poolA, poolB];
          tokensOut = [poolC, tokens.get(1)];

          totalAmountIn = pathExactAmountIn;
          totalAmountOut = pathMinAmountOut;
          pathAmountsOut = [totalAmountOut, totalAmountOut];
          amountsOut = [totalAmountOut, totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
                [await tokensIn[1].symbol()]: ['very-near', -totalAmountIn],
                [await tokensOut[1].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
                [await tokensIn[1].symbol()]: ['very-near', totalAmountIn],
                [await tokensOut[1].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: poolA,
              steps: [{ pool: poolAC, tokenOut: poolC, isBuffer: false }],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pct(pathMinAmountOut, 0.999), // Rounding tolerance
            },
            {
              tokenIn: poolB,
              steps: [
                { pool: poolAB, tokenOut: poolA, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pct(pathMinAmountOut, 0.999), // Rounding tolerance
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, false);
      });
    });
  });

  describe('batch swap given out', () => {
    let doSwap: () => Promise<unknown>;
    let doSwapStatic: () => Promise<{
      pathAmountsIn: bigint[];
      tokensIn: string[];
      amountsIn: bigint[];
    }>;
    let runQuery: () => Promise<{
      pathAmountsIn: bigint[];
      tokensIn: string[];
      amountsIn: bigint[];
    }>;
    let tokensIn: (ERC20TestToken | PoolMock)[];
    let tokenOut: ERC20TestToken | PoolMock;
    const pathExactAmountOut = fp(1);
    const pathMaxAmountIn = fp(1);
    const unbalancedAddRoundingError = 2n;

    let totalAmountIn: bigint, totalAmountOut: bigint, pathAmountsIn: bigint[], amountsIn: bigint[];
    let balanceChange: BalanceChange[];
    let paths: IRouter.SwapPathExactAmountOutStruct[];

    function setUp() {
      const _doSwap = async (isStatic: boolean) =>
        (isStatic ? router.connect(sender).swapExactOut.staticCall : router.connect(sender).swapExactOut)(
          paths,
          MAX_UINT256,
          false,
          '0x'
        );
      doSwap = async () => _doSwap(false);
      doSwapStatic = async () =>
        _doSwap(true) as unknown as {
          pathAmountsIn: bigint[];
          tokensIn: string[];
          amountsIn: bigint[];
        };
      runQuery = async () => router.connect(zero).querySwapExactOut.staticCall(paths, zero.address, '0x');
    }

    function itTestsBatchSwap(singleTransferIn = true, singleTransferOut = true) {
      it('performs swap, transfers tokens', async () => {
        await expectBalanceChange(doSwap, tokens, balanceChange);
      });

      if (singleTransferIn) {
        it('performs single transfer for token in', async () => {
          // Some operations have rounding error, and event arguments are precise. So we get the result from
          // the query to check the event arguments.
          const { amountsIn } = await runQuery();

          await expect(doSwap()).to.emit(tokensIn[0], 'Transfer').withArgs(sender.address, vaultAddress, amountsIn[0]);
        });
      }

      if (singleTransferOut) {
        it('performs single transfer for token out', async () => {
          await expect(doSwap()).to.emit(tokenOut, 'Transfer').withArgs(vaultAddress, sender.address, totalAmountOut);
        });
      }

      it('returns path amounts in', async () => {
        const calculatedPathAmountsIn = (await doSwapStatic()).pathAmountsIn;
        calculatedPathAmountsIn.map((pathAmountIn, i) =>
          expect(pathAmountIn).to.be.almostEqual(pathAmountsIn[i], 1e-8)
        );
      });

      it('returns tokens in', async () => {
        const calculatedTokensIn = (await doSwapStatic()).tokensIn;
        expect(calculatedTokensIn).to.be.deep.eq(
          await Promise.all(tokensIn.map(async (tokenIn) => await tokenIn.getAddress()))
        );
      });

      it('returns token amounts in', async () => {
        const calculatedAmountsIn = (await doSwapStatic()).amountsIn;
        calculatedAmountsIn.map((amountIn, i) => expect(amountIn).to.be.almostEqual(amountsIn[i], 1e-8));
      });

      it('returns same outputs as query', async () => {
        const realOutputs = await doSwapStatic();
        const queryOutputs = await runQuery();

        expect(realOutputs.pathAmountsIn).to.be.deep.eq(queryOutputs.pathAmountsIn);
        expect(realOutputs.amountsIn).to.be.deep.eq(queryOutputs.amountsIn);
        expect(realOutputs.tokensIn).to.be.deep.eq(queryOutputs.tokensIn);
      });
    }

    afterEach('clean up expected results and inputs', () => {
      tokensIn = undefined;
      tokenOut = undefined;
      totalAmountIn = undefined;
      totalAmountOut = undefined;
      pathAmountsIn = undefined;
      amountsIn = undefined;
      balanceChange = undefined;
      paths = undefined;
    });

    context('pure swaps with no nesting', () => {
      context('single path', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(2);

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountIn]; // 1 path, all tokens out
          amountsIn = [totalAmountIn]; // 1 path

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('single path, first - intermediate - final steps', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(2);

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountIn]; // 1 path, all tokens out
          amountsIn = [totalAmountIn]; // 1 path

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
                { pool: poolC, tokenOut: token0, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path, SISO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(2);

          totalAmountIn = pathExactAmountOut * 2n; // 2 paths
          totalAmountOut = pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsIn = [totalAmountOut]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: token0,
              steps: [{ pool: poolC, tokenOut: token2, isBuffer: false }],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path, MISO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0), tokens.get(1)];
          tokenOut = tokens.get(2);

          totalAmountIn = pathExactAmountOut * 2n; // 2 paths
          totalAmountOut = pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsIn = pathAmountsIn; // 2 paths, multiple token inputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -pathMaxAmountIn],
                [await tokensIn[1].symbol()]: ['equal', -pathMaxAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', pathMaxAmountIn],
                [await tokensIn[1].symbol()]: ['equal', pathMaxAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: token1,
              steps: [{ pool: poolB, tokenOut: token2, isBuffer: false }],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, true);
      });

      context('multi path, SIMO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(2);
          const secondPathTokenOut = tokens.get(1);

          totalAmountIn = pathExactAmountOut * 2n; // 2 paths
          totalAmountOut = pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsIn = [totalAmountIn]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', pathExactAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -pathExactAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: token0,
              steps: [{ pool: poolA, tokenOut: token1, isBuffer: false }],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(true, false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0), poolA];
          tokenOut = tokens.get(2);
          const secondPathTokenOut = poolC;

          totalAmountIn = pathExactAmountOut * 2n; // 2 paths
          totalAmountOut = pathMaxAmountIn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsIn = pathAmountsIn; // 2 paths, multiple token inputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -pathMaxAmountIn],
                [await tokensIn[1].symbol()]: ['equal', -pathMaxAmountIn],
                [await tokenOut.symbol()]: ['equal', pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', pathExactAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', pathMaxAmountIn],
                [await tokensIn[1].symbol()]: ['equal', pathMaxAmountIn],
                [await tokenOut.symbol()]: ['equal', -pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -pathExactAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: poolA,
              steps: [
                { pool: poolAB, tokenOut: poolB, isBuffer: false },
                { pool: poolBC, tokenOut: poolC, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, false);
      });

      context('multi path, circular inputs/outputs', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0), tokens.get(2)];
          tokenOut = tokens.get(2);
          const secondPathTokenOut = tokens.get(0);

          totalAmountIn = 0n; // 2 paths
          totalAmountOut = 0n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [pathMaxAmountIn, pathMaxAmountIn]; // 2 paths, half the output in each
          amountsIn = pathAmountsIn; // 2 paths, 2 circular inputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', 0],
                [await tokenOut.symbol()]: ['equal', 0],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', 0],
                [await secondPathTokenOut.symbol()]: ['equal', 0],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: token2,
              steps: [{ pool: poolC, tokenOut: token0, isBuffer: false }],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, false);
      });
    });

    context('joinswaps (add liquidity step)', () => {
      context('single path - first add liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = poolB;

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut]; // 1 path, all tokens out
          amountsIn = [totalAmountIn];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolAB, tokenOut: poolB, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path - first and intermediate add liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = poolB;

          totalAmountIn = pathMaxAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsIn = [totalAmountIn];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolAB, tokenOut: poolB, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: poolB, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        // The second step of the second path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        itTestsBatchSwap(true, false);
      });

      context('single path - final add liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = poolB;

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut]; // 1 path, all tokens out
          amountsIn = [totalAmountIn];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: poolB, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(true, false);

        it('mints amount out', async () => {
          await expect(doSwap()).to.emit(tokenOut, 'Transfer').withArgs(ZERO_ADDRESS, sender.address, totalAmountOut);
        });
      });
    });

    context('exitswaps (remove liquidity step)', () => {
      context('single path - first remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [poolA];
          tokenOut = tokens.get(2);

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut]; // 1 path, all tokens out
          amountsIn = [totalAmountIn];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: poolA,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn + unbalancedAddRoundingError,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, true);

        it('burns amount in', async () => {
          // Some operations have rounding error, and event arguments are precise. So we get the result from
          // the query to check the event arguments.
          const { amountsIn } = await runQuery();

          // Router is the one that burns the tokens, not sender.
          await expect(doSwap()).to.emit(tokensIn[0], 'Transfer').withArgs(router, ZERO_ADDRESS, amountsIn[0]);
        });
      });

      context('single path - intermediate remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [poolC];
          tokenOut = tokens.get(2);

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut]; // 1 path, all tokens out
          amountsIn = [totalAmountIn];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: poolC,
              steps: [
                { pool: poolAC, tokenOut: poolA, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn + unbalancedAddRoundingError,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(false, true);
      });

      context('single path - final remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [poolA];
          tokenOut = tokens.get(1);

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut]; // 1 path, all tokens out
          amountsIn = [totalAmountIn];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: poolA,
              steps: [
                { pool: poolAB, tokenOut: poolB, isBuffer: false },
                { pool: poolB, tokenOut: token1, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn + unbalancedAddRoundingError,
            },
          ];

          setUp();
        });

        // Rounding errors don't allow testing precise transfers for amount out.
        itTestsBatchSwap(true, false);
      });

      context('multi path - final remove liquidity step', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(1);

          totalAmountIn = pathMaxAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsIn = [totalAmountIn];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA, isBuffer: false },
                { pool: poolA, tokenOut: token1, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pct(pathMaxAmountIn, 1.001), // Rounding tolerance
            },
            {
              tokenIn: token0,
              steps: [
                { pool: poolC, tokenOut: poolC, isBuffer: false },
                { pool: poolBC, tokenOut: poolB, isBuffer: false },
                { pool: poolB, tokenOut: token1, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pct(pathMaxAmountIn, 1.001), // Rounding tolerance
            },
          ];

          setUp();
        });

        // The first step of both paths are an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount in as argument.
        // Rounding errors make the output inexact, so we skip the transfer checks.
        itTestsBatchSwap(false, false);
      });
    });
  });
});
