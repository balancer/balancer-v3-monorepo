import { ethers } from 'hardhat';
import { VoidSigner } from 'ethers';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import { fp, fpDivDown, fpDivUp } from '@balancer-labs/v3-helpers/src/numbers';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';

import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import { BatchRouter, Router, PoolFactoryMock, Vault } from '../typechain-types';
import { BalanceChange, expectBalanceChange } from '@balancer-labs/v3-helpers/src/test/tokenBalance';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import {
  ERC20TestToken,
  ERC20TestToken__factory,
  ERC4626TestToken,
} from '@balancer-labs/v3-solidity-utils/typechain-types';
import { buildTokenConfig } from './poolSetup';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from './Permit2Deployer';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { IBatchRouter } from '@balancer-labs/v3-interfaces/typechain-types';
import { BufferRouter } from '@balancer-labs/v3-pool-weighted/typechain-types';

describe('AggregatorBatchSwap', function () {
  const TOKEN_AMOUNT = fp(1e12);
  const WRAPPED_TOKEN_AMOUNT = fp(1e6);

  const BATCH_ROUTER_VERSION = 'AggregatorBatchRouter v9';
  const ROUTER_VERSION = 'Router v9';

  let permit2: IPermit2;
  let vault: Vault;
  let factory: PoolFactoryMock;

  let router: BatchRouter, basicRouter: Router, bufferRouter: BufferRouter;
  let poolA: PoolMock, poolB: PoolMock, poolC: PoolMock, poolWA: PoolMock, poolWB: PoolMock;
  let poolAB: PoolMock, poolAC: PoolMock, poolBC: PoolMock;
  let pools: PoolMock[];
  let tokens: ERC20TokenList;

  let wToken0: ERC4626TestToken, wToken2: ERC4626TestToken;
  let wToken0Address: string, wToken2Address: string;

  let lp: SignerWithAddress, sender: SignerWithAddress, zero: VoidSigner;

  let poolATokens: string[],
    poolBTokens: string[],
    poolCTokens: string[],
    poolWATokens: string[],
    poolWBTokens: string[];
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
    router = await deploy('AggregatorBatchRouter', {
      args: [vaultAddress, BATCH_ROUTER_VERSION],
    });
    basicRouter = await deploy('Router', { args: [vaultAddress, WETH, permit2, ROUTER_VERSION] });
    bufferRouter = await deploy('v3-vault/BufferRouter', {
      args: [vault, await WETH, permit2, ROUTER_VERSION],
    });

    factory = await deploy('PoolFactoryMock', { args: [vaultAddress, 12 * MONTH] });

    tokens = await ERC20TokenList.create(3, { sorted: true });
    token0 = await tokens.get(0).getAddress();
    token1 = await tokens.get(1).getAddress();
    token2 = await tokens.get(2).getAddress();

    wToken0 = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [token0, 'Wrapped TK0', 'wTK0', 18],
    });
    wToken2 = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [token2, 'Wrapped TK2', 'wTK2', 18],
    });

    wToken0Address = await wToken0.getAddress();
    wToken2Address = await wToken2.getAddress();

    poolATokens = sortAddresses([token0, token1]);
    poolBTokens = sortAddresses([token1, token2]);
    poolCTokens = sortAddresses([token0, token2]);
    poolWATokens = sortAddresses([wToken0Address, token1]);
    poolWBTokens = sortAddresses([token1, wToken2Address]);

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

    // Pool A has wrapped token 0 and token 1.
    poolWA = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Wrapped Token 0 - Pool A', 'WPOOL-A'],
    });

    // Pool B has wrapped token 2 and token 1.
    poolWB = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Wrapped Token 2 - Pool B', 'WPOOL-B'],
    });

    await factory.registerTestPool(poolA, buildTokenConfig(poolATokens));
    await factory.registerTestPool(poolB, buildTokenConfig(poolBTokens));
    await factory.registerTestPool(poolC, buildTokenConfig(poolCTokens));
    await factory.registerTestPool(poolWA, buildTokenConfig(poolWATokens));
    await factory.registerTestPool(poolWB, buildTokenConfig(poolWBTokens));
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
    pools = [poolA, poolB, poolC, poolAB, poolAC, poolBC, poolWA, poolWB];

    for (const user of [lp, sender]) {
      await tokens.mint({ to: user, amount: TOKEN_AMOUNT });

      await tokens
        .get(0)
        .connect(lp)
        .mint(user, WRAPPED_TOKEN_AMOUNT * 2n);
      await tokens.get(0).connect(user).approve(wToken0, WRAPPED_TOKEN_AMOUNT);
      await wToken0.connect(user).deposit(WRAPPED_TOKEN_AMOUNT, user);

      await tokens
        .get(2)
        .connect(user)
        .mint(user, WRAPPED_TOKEN_AMOUNT * 2n);
      await tokens.get(2).connect(user).approve(wToken2, WRAPPED_TOKEN_AMOUNT);
      await wToken2.connect(user).deposit(WRAPPED_TOKEN_AMOUNT, user);
    }

    tokens.push(ERC20TestToken__factory.connect(wToken0Address, sender));
    tokens.push(ERC20TestToken__factory.connect(wToken2Address, sender));

    for (const pool of pools) {
      await pool.connect(lp).approve(router, MAX_UINT256);
      await pool.connect(lp).approve(basicRouter, MAX_UINT256);
    }

    for (const token of [...tokens.tokens, wToken0, wToken2, poolA, poolB, poolC, poolAB, poolAC, poolBC]) {
      for (const from of [lp, sender]) {
        await token.connect(from).approve(permit2, MAX_UINT256);
        for (const to of [basicRouter, bufferRouter]) {
          await permit2.connect(from).approve(token, to, MAX_UINT160, MAX_UINT48);
        }
      }
    }

    await bufferRouter.connect(lp).initializeBuffer(wToken0, WRAPPED_TOKEN_AMOUNT, 0, 0);
    await bufferRouter.connect(lp).initializeBuffer(wToken2, WRAPPED_TOKEN_AMOUNT, 0, 0);
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

    await basicRouter
      .connect(lp)
      .initialize(poolWA, poolWATokens, Array(poolWATokens.length).fill(fp(10000)), 0, false, '0x');

    await basicRouter
      .connect(lp)
      .initialize(poolWB, poolWBTokens, Array(poolWBTokens.length).fill(fp(10000)), 0, false, '0x');

    await poolA.connect(lp).transfer(sender, fp(100));
    await poolB.connect(lp).transfer(sender, fp(100));
    await poolC.connect(lp).transfer(sender, fp(100));
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

    let tokensOut: (ERC20TestToken | PoolMock)[];
    const pathExactAmountIn = fp(1);
    const pathMinAmountOut = fp(1);
    const roundingError = 2n;

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

    function itTestsBatchSwap(singleTransferOut = true) {
      it('performs swap, transfers tokens', async () => {
        await expectBalanceChange(doSwap, tokens, balanceChange);
      });

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
      tokensOut = undefined;
      totalAmountIn = undefined;
      totalAmountOut = undefined;
      pathAmountsOut = undefined;
      amountsOut = undefined;
      balanceChange = undefined;
      paths = undefined;
    });

    context('pure swaps with no nesting', () => {
      context('should revert if path is inccorrect', () => {
        it('should revert if the step.pool is tokenIn', async () => {
          expect(
            router.connect(sender).swapExactIn(
              [
                {
                  tokenIn: token0,
                  steps: [{ pool: token0, tokenOut: token1, isBuffer: false }],
                  exactAmountIn: pathExactAmountIn,
                  minAmountOut: pathMinAmountOut,
                },
              ],
              MAX_UINT256,
              false,
              '0x'
            )
          ).to.be.revertedWithCustomError(router, 'OperationNotSupported');
        });
        it('should revert if the step.pool is tokenOut', async () => {
          expect(
            router.connect(sender).swapExactIn(
              [
                {
                  tokenIn: token0,
                  steps: [{ pool: token1, tokenOut: token0, isBuffer: false }],
                  exactAmountIn: pathExactAmountIn,
                  minAmountOut: pathMinAmountOut,
                },
              ],
              MAX_UINT256,
              false,
              '0x'
            )
          ).to.be.revertedWithCustomError(router, 'OperationNotSupported');
        });
      });
      context('single path', () => {
        beforeEach(async () => {
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = pathAmountsOut; // 1 path, 1 token out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, totalAmountIn)).wait();
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - roundingError,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('single path, first - intermediate - final steps', () => {
        beforeEach(async () => {
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out
          amountsOut = pathAmountsOut; // 1 path, 1 token out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, totalAmountIn)).wait();
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
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut]; // 2 paths, single token output

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, totalAmountIn)).wait();
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
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut]; // 2 paths, single token output

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, pathExactAmountIn)).wait();
          await (await ERC20TestToken__factory.connect(token1, sender).transfer(vault, pathExactAmountIn)).wait();
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

        itTestsBatchSwap(true);
      });

      context('multi path, SIMO', () => {
        beforeEach(async () => {
          tokensOut = [tokens.get(2), tokens.get(1)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = pathAmountsOut; // 2 paths, 2 outputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', pathMinAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', -pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', -pathMinAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, totalAmountIn)).wait();
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

        itTestsBatchSwap(false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          tokensOut = [tokens.get(2), poolC];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = pathAmountsOut; // 2 paths, 2 outputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', pathMinAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensOut[0].symbol()]: ['equal', -pathMinAmountOut],
                [await tokensOut[1].symbol()]: ['equal', -pathMinAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, pathExactAmountIn)).wait();
          await (
            await ERC20TestToken__factory.connect(await poolA.getAddress(), sender).transfer(vault, pathExactAmountIn)
          ).wait();
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

        itTestsBatchSwap(false);
      });

      context('unwrap first, SISO', () => {
        beforeEach(async () => {
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut]; // 2 paths, single token output

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensOut[0].symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(wToken0Address, sender).transfer(vault, totalAmountIn)).wait();
          paths = [
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - roundingError,
            },
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - roundingError,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(true);
      });

      context('unwrap first - wrap end, SISO', () => {
        beforeEach(async () => {
          tokensOut = [ERC20TestToken__factory.connect(wToken2Address, sender)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokens.get(2).symbol()]: ['very-near', -1n * fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
                [await tokensOut[0].symbol()]: ['very-near', fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
            {
              account: wToken2Address,
              changes: {
                [await tokens.get(2).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(wToken0Address, sender).transfer(vault, totalAmountIn)).wait();
          paths = [
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
                { pool: wToken2, tokenOut: wToken2, isBuffer: true },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - roundingError * 2n,
            },
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
                { pool: wToken2, tokenOut: wToken2, isBuffer: true },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - roundingError * 2n,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(true);
      });

      context('wrap first - unwrap end, SISO', () => {
        beforeEach(async () => {
          tokensOut = [tokens.get(2)];

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each
          amountsOut = [totalAmountOut];

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensOut[0].symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokens.get(2).symbol()]: ['very-near', -totalAmountOut],
                [await tokens.get(0).symbol()]: ['very-near', -1n * fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
                [await wToken0.symbol()]: ['very-near', fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
            {
              account: wToken0Address,
              changes: {
                [await tokens.get(0).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, totalAmountIn)).wait();
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: wToken0, tokenOut: wToken0, isBuffer: true },
                { pool: poolWA, tokenOut: token1, isBuffer: false },
                { pool: poolWB, tokenOut: wToken2, isBuffer: false },
                { pool: wToken2, tokenOut: token2, isBuffer: true },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - roundingError * 2n,
            },
            {
              tokenIn: token0,
              steps: [
                { pool: wToken0, tokenOut: wToken0, isBuffer: true },
                { pool: poolWA, tokenOut: token1, isBuffer: false },
                { pool: poolWB, tokenOut: wToken2, isBuffer: false },
                { pool: wToken2, tokenOut: token2, isBuffer: true },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut - roundingError * 2n,
            },
          ];

          setUp();
        });

        itTestsBatchSwap(true);
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
    const pathMaxAmountIn = fp(2);
    const expectedAmountToReturn = pathMaxAmountIn - pathExactAmountOut;
    const expectedAmountIn = pathMaxAmountIn - expectedAmountToReturn;

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

    function itTestsBatchSwap(singleTransferOut = true) {
      it('performs swap, transfers tokens', async () => {
        await expectBalanceChange(doSwap, tokens, balanceChange);
      });

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
      it('should revert if the step.pool is tokenIn', async () => {
        expect(
          router.connect(sender).swapExactOut(
            [
              {
                tokenIn: token0,
                steps: [{ pool: token0, tokenOut: token1, isBuffer: false }],
                exactAmountOut: pathExactAmountOut,
                maxAmountIn: pathMaxAmountIn,
              },
            ],
            MAX_UINT256,
            false,
            '0x'
          )
        ).to.be.revertedWithCustomError(router, 'OperationNotSupported');
      });
      it('should revert if the step.pool is tokenOut', async () => {
        expect(
          router.connect(sender).swapExactOut(
            [
              {
                tokenIn: token0,
                steps: [{ pool: token1, tokenOut: token0, isBuffer: false }],
                exactAmountOut: pathExactAmountOut,
                maxAmountIn: pathMaxAmountIn,
              },
            ],
            MAX_UINT256,
            false,
            '0x'
          )
        ).to.be.revertedWithCustomError(router, 'OperationNotSupported');
      });

      context('single path', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(2);

          totalAmountIn = pathMaxAmountIn; // 1 path
          totalAmountOut = pathExactAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn]; // 1 path, all tokens out
          amountsIn = [expectedAmountIn]; // 1 path

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, pathMaxAmountIn)).wait();
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
          pathAmountsIn = [expectedAmountIn]; // 1 path, all tokens out
          amountsIn = [expectedAmountIn]; // 1 path

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, pathMaxAmountIn)).wait();
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

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          const maxAmountIn = pathMaxAmountIn * 2n;
          totalAmountIn = expectedAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = [totalAmountOut]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, maxAmountIn)).wait();
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

          totalAmountIn = expectedAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = pathAmountsIn; // 2 paths, multiple token inputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await tokensIn[1].symbol()]: ['equal', expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await tokensIn[1].symbol()]: ['equal', -expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, pathMaxAmountIn)).wait();
          await (await ERC20TestToken__factory.connect(token1, sender).transfer(vault, pathMaxAmountIn)).wait();
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

        itTestsBatchSwap(true);
      });

      context('multi path, SIMO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(2);
          const secondPathTokenOut = tokens.get(1);

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          const maxAmountIn = pathMaxAmountIn * 2n;

          totalAmountIn = expectedAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = [totalAmountIn]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', pathExactAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', -pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -pathExactAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, maxAmountIn)).wait();
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

        itTestsBatchSwap(false);
      });

      context('multi path, MIMO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0), poolA];
          tokenOut = tokens.get(2);
          const secondPathTokenOut = poolC;

          totalAmountIn = expectedAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await poolA.symbol()]: ['equal', expectedAmountToReturn],
                [await tokensIn[0].symbol()]: ['equal', expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', pathExactAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await poolA.symbol()]: ['equal', -expectedAmountToReturn],
                [await tokensIn[0].symbol()]: ['equal', -expectedAmountToReturn],
                [await tokenOut.symbol()]: ['equal', -pathExactAmountOut],
                [await secondPathTokenOut.symbol()]: ['equal', -pathExactAmountOut],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, pathMaxAmountIn)).wait();
          await (
            await ERC20TestToken__factory.connect(await poolA.getAddress(), sender).transfer(vault, pathMaxAmountIn)
          ).wait();
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

        itTestsBatchSwap(false);
      });

      context('unwrap first, SISO', () => {
        beforeEach(async () => {
          tokensIn = [ERC20TestToken__factory.connect(wToken0Address, sender)];
          tokenOut = tokens.get(2);

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          const maxAmountIn = pathMaxAmountIn * 2n;
          totalAmountIn = expectedAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = [totalAmountOut]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          await (await tokensIn[0].transfer(vault, maxAmountIn)).wait();
          paths = [
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
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

      context('unwrap first - wrap end, SISO', () => {
        beforeEach(async () => {
          tokensIn = [ERC20TestToken__factory.connect(wToken0Address, sender)];
          tokenOut = ERC20TestToken__factory.connect(wToken2Address, sender);

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          const maxAmountIn = pathMaxAmountIn * 2n;
          totalAmountIn = expectedAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = [totalAmountOut]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', -totalAmountToReturn],
                [await tokens.get(2).symbol()]: ['very-near', -1n * fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
                [await tokenOut.symbol()]: ['very-near', fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2)) - totalAmountOut], // Rebalancing
              },
            },
            {
              account: wToken2Address,
              changes: {
                [await tokens.get(2).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (await tokensIn[0].transfer(vault, maxAmountIn)).wait();
          paths = [
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
                { pool: wToken2, tokenOut: wToken2, isBuffer: true },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: wToken0,
              steps: [
                { pool: wToken0, tokenOut: token0, isBuffer: true },
                { pool: poolA, tokenOut: token1, isBuffer: false },
                { pool: poolB, tokenOut: token2, isBuffer: false },
                { pool: wToken2, tokenOut: wToken2, isBuffer: true },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('wrap first - unwrap end, SISO', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0)];
          tokenOut = tokens.get(2);

          const totalAmountToReturn = expectedAmountToReturn * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          const maxAmountIn = pathMaxAmountIn * 2n;
          totalAmountIn = expectedAmountIn * 2n; // 2 paths
          totalAmountOut = pathExactAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = [totalAmountOut]; // 2 paths, single token input

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['very-near', totalAmountToReturn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokens.get(2).symbol()]: ['equal', -totalAmountOut],
                [await tokensIn[0].symbol()]: [
                  'very-near',
                  -1n * fpDivDown(WRAPPED_TOKEN_AMOUNT, fp(2)) - totalAmountToReturn,
                ], // Rebalancing
                [await wToken0.symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
            {
              account: wToken0Address,
              changes: {
                [await tokens.get(0).symbol()]: ['very-near', fpDivUp(WRAPPED_TOKEN_AMOUNT, fp(2))], // Rebalancing
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, maxAmountIn)).wait();
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: wToken0, tokenOut: wToken0, isBuffer: true },
                { pool: poolWA, tokenOut: token1, isBuffer: false },
                { pool: poolWB, tokenOut: wToken2, isBuffer: false },
                { pool: wToken2, tokenOut: token2, isBuffer: true },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
            {
              tokenIn: token0,
              steps: [
                { pool: wToken0, tokenOut: wToken0, isBuffer: true },
                { pool: poolWA, tokenOut: token1, isBuffer: false },
                { pool: poolWB, tokenOut: wToken2, isBuffer: false },
                { pool: wToken2, tokenOut: token2, isBuffer: true },
              ],
              exactAmountOut: pathExactAmountOut,
              maxAmountIn: pathMaxAmountIn,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path, circular inputs/outputs', () => {
        beforeEach(async () => {
          tokensIn = [tokens.get(0), tokens.get(2)];
          tokenOut = tokens.get(2);

          totalAmountIn = 0n; // 2 paths
          totalAmountOut = 0n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsIn = [expectedAmountIn, expectedAmountIn]; // 2 paths, half the output in each
          amountsIn = pathAmountsIn; // 2 paths, 2 circular inputs

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', pathMaxAmountIn],
                [await tokenOut.symbol()]: ['equal', pathMaxAmountIn],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokensIn[0].symbol()]: ['equal', -pathMaxAmountIn],
                [await tokenOut.symbol()]: ['equal', -pathMaxAmountIn],
              },
            },
          ];

          await (await ERC20TestToken__factory.connect(token0, sender).transfer(vault, pathMaxAmountIn)).wait();
          await (await ERC20TestToken__factory.connect(token2, sender).transfer(vault, pathMaxAmountIn)).wait();
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

        itTestsBatchSwap(false);
      });
    });
  });
});
