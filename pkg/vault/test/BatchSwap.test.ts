import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import { IRouter, Router, Vault } from '../typechain-types';
import { BalanceChange, expectBalanceChange } from '@balancer-labs/v3-helpers/src/test/tokenBalance';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';

describe('BatchSwap', function () {
  let vault: Vault;
  let poolA: PoolMock, poolB: PoolMock, poolC: PoolMock;
  let poolAB: PoolMock, poolAC: PoolMock, poolBC: PoolMock;
  let tokens: ERC20TokenList;
  let router: Router;

  let lp: SignerWithAddress, sender: SignerWithAddress;

  let poolATokens: string[], poolBTokens: string[], poolCTokens: string[];
  let poolABTokens: string[], poolACTokens: string[], poolBCTokens: string[];
  let token0: string, token1: string, token2: string;
  let vaultAddress: string;

  before('setup signers', async () => {
    [, lp, sender] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await VaultDeployer.deploy();
    vaultAddress = await vault.getAddress();
    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('Router', { args: [vaultAddress, WETH] });

    tokens = await ERC20TokenList.create(3);
    token0 = await tokens.get(0).getAddress();
    token1 = await tokens.get(1).getAddress();
    token2 = await tokens.get(2).getAddress();
    poolATokens = [token0, token1];
    poolBTokens = [token1, token2];
    poolCTokens = [token0, token2];

    // Pool A has tokens 0 and 1.
    poolA = await deploy('v3-vault/PoolMock', {
      args: [
        vaultAddress,
        'Pool A',
        'POOLA',
        poolATokens,
        Array(poolATokens.length).fill(ZERO_ADDRESS),
        true,
        0,
        ZERO_ADDRESS,
      ],
    });

    // Pool A has tokens 1 and 2.
    poolB = await deploy('v3-vault/PoolMock', {
      args: [
        vaultAddress,
        'Pool B',
        'POOLB',
        poolBTokens,
        Array(poolBTokens.length).fill(ZERO_ADDRESS),
        true,
        0,
        ZERO_ADDRESS,
      ],
    });

    // Pool C has tokens 0 and 2.
    poolC = await deploy('v3-vault/PoolMock', {
      args: [
        vaultAddress,
        'Pool C',
        'POOLC',
        poolCTokens,
        Array(poolCTokens.length).fill(ZERO_ADDRESS),
        true,
        0,
        ZERO_ADDRESS,
      ],
    });
  });

  sharedBeforeEach('nested pools', async () => {
    poolABTokens = [await poolA.getAddress(), await poolB.getAddress()];
    poolAB = await deploy('v3-vault/PoolMock', {
      args: [
        vaultAddress,
        'Pool A-B',
        'POOL-AB',
        poolABTokens,
        Array(poolABTokens.length).fill(ZERO_ADDRESS),
        true,
        0,
        ZERO_ADDRESS,
      ],
    });

    poolACTokens = [await poolA.getAddress(), await poolC.getAddress()];
    poolAC = await deploy('v3-vault/PoolMock', {
      args: [
        vaultAddress,
        'Pool A-C',
        'POOL-AC',
        poolACTokens,
        Array(poolACTokens.length).fill(ZERO_ADDRESS),
        true,
        0,
        ZERO_ADDRESS,
      ],
    });

    poolBCTokens = [await poolB.getAddress(), await poolC.getAddress()];
    poolBC = await deploy('v3-vault/PoolMock', {
      args: [
        vaultAddress,
        'Pool B-C',
        'POOL-BC',
        poolBCTokens,
        Array(poolBCTokens.length).fill(ZERO_ADDRESS),
        true,
        0,
        ZERO_ADDRESS,
      ],
    });
  });

  sharedBeforeEach('initialize pools', async () => {
    tokens.mint({ to: lp, amount: fp(1e12) });
    tokens.mint({ to: sender, amount: fp(1e12) });
    tokens.approve({ to: await vault.getAddress(), from: lp, amount: MAX_UINT256 });
    tokens.approve({ to: await vault.getAddress(), from: sender, amount: MAX_UINT256 });

    await router.connect(lp).initialize(poolA, poolATokens, Array(poolATokens.length).fill(fp(10000)), 0, false, '0x');
    await router.connect(lp).initialize(poolB, poolBTokens, Array(poolBTokens.length).fill(fp(10000)), 0, false, '0x');
    await router.connect(lp).initialize(poolC, poolCTokens, Array(poolCTokens.length).fill(fp(10000)), 0, false, '0x');

    await router
      .connect(lp)
      .initialize(poolAB, poolABTokens, Array(poolABTokens.length).fill(fp(1000)), 0, false, '0x');
    await router
      .connect(lp)
      .initialize(poolAC, poolACTokens, Array(poolACTokens.length).fill(fp(1000)), 0, false, '0x');
    await router
      .connect(lp)
      .initialize(poolBC, poolBCTokens, Array(poolBCTokens.length).fill(fp(1000)), 0, false, '0x');
  });

  describe('batch swap given in', () => {
    let doSwap: () => Promise<unknown>;
    let doSwapStatic: () => Promise<unknown>;
    let tokenIn: ERC20TestToken | PoolMock;
    let tokenOut: ERC20TestToken | PoolMock;
    const pathExactAmountIn = fp(1);
    const pathMinAmountOut = fp(1);

    let totalAmountIn: bigint, totalAmountOut: bigint, pathAmountsOut: bigint[];
    let balanceChange: BalanceChange[];
    let paths: IRouter.SwapPathExactAmountInStruct[];

    function setUp() {
      const _doSwap = async (isStatic: boolean) =>
        (isStatic ? router.connect(sender).swapExactIn.staticCall : router.connect(sender).swapExactIn)(
          paths,
          MAX_UINT256,
          false,
          '0x'
        );
      doSwap = async () => _doSwap(false);
      doSwapStatic = async () => _doSwap(true);
    }

    function itTestsBatchSwap(singleTransferOut = true) {
      it('performs swap, transfers tokens', async () => {
        await expectBalanceChange(doSwap, tokens, balanceChange);
      });

      it('performs single transfer for token in', async () => {
        await expect(doSwap()).to.emit(tokenIn, 'Transfer').withArgs(sender.address, vaultAddress, totalAmountIn);
      });

      if (singleTransferOut) {
        it('performs single transfer for token out', async () => {
          await expect(doSwap()).to.emit(tokenOut, 'Transfer').withArgs(vaultAddress, sender.address, totalAmountOut);
        });
      }

      it('returns amounts out', async () => {
        const amountsOut = (await doSwapStatic()) as bigint[];
        amountsOut.map((pathAmountOut, i) => expect(pathAmountOut).to.be.almostEqual(pathAmountsOut[i], 1e-8));
      });
    }

    context('pure swaps with no nesting', () => {
      context('single path', () => {
        sharedBeforeEach(async () => {
          tokenIn = tokens.get(0);
          tokenOut = tokens.get(2);

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokenIn.symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokenIn.symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1 },
                { pool: poolB, tokenOut: token2 },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path', () => {
        sharedBeforeEach(async () => {
          tokenIn = tokens.get(0);
          tokenOut = tokens.get(2);

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokenIn.symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokenIn.symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];
          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1 },
                { pool: poolB, tokenOut: token2 },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: token0,
              steps: [{ pool: poolC, tokenOut: token2 }],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });
    });

    context('joinswaps (add liquidity step)', () => {
      context('single path - intermediate add liquidity step', () => {
        sharedBeforeEach(async () => {
          tokenIn = tokens.get(0);
          tokenOut = poolB;

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokenIn.symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokenIn.symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA },
                { pool: poolAB, tokenOut: poolB },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('multi path - intermediate and final add liquidity step', () => {
        sharedBeforeEach(async () => {
          tokenIn = tokens.get(0);
          tokenOut = poolB;

          totalAmountIn = pathExactAmountIn * 2n; // 2 paths
          totalAmountOut = pathMinAmountOut * 2n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 2n, totalAmountOut / 2n]; // 2 paths, half the output in each

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokenIn.symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokenIn.symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA },
                { pool: poolAB, tokenOut: poolB },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: token1 },
                { pool: poolB, tokenOut: poolB },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        // The second step of the second path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        itTestsBatchSwap(false);
      });
    });

    // TODO: this requires #246 to be solved
    context.skip('exitswaps (remove liquidity step)', () => {
      context('single path - intermediate remove liquidity step', () => {
        sharedBeforeEach(async () => {
          tokenIn = tokens.get(0);
          tokenOut = tokens.get(2);

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokenIn.symbol()]: ['equal', -totalAmountIn],
                [await tokenOut.symbol()]: ['equal', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokenIn.symbol()]: ['equal', totalAmountIn],
                [await tokenOut.symbol()]: ['equal', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA },
                { pool: poolA, tokenOut: token1 },
                { pool: poolB, tokenOut: token2 },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        itTestsBatchSwap();
      });

      context('single path - final remove liquidity step', () => {
        sharedBeforeEach(async () => {
          tokenIn = tokens.get(0);
          tokenOut = tokens.get(1);

          totalAmountIn = pathExactAmountIn; // 1 path
          totalAmountOut = pathMinAmountOut; // 1 path, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut]; // 1 path, all tokens out

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokenIn.symbol()]: ['very-near', -totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokenIn.symbol()]: ['very-near', totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA },
                { pool: poolA, tokenOut: token1 },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        // The first step of first path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        itTestsBatchSwap(false);
      });

      context('multi path - final remove liquidity step', () => {
        sharedBeforeEach(async () => {
          tokenIn = tokens.get(0);
          tokenOut = tokens.get(1);

          totalAmountIn = pathExactAmountIn * 1n; // 2 paths
          totalAmountOut = pathMinAmountOut * 1n; // 2 paths, 1:1 ratio between inputs and outputs
          pathAmountsOut = [totalAmountOut / 1n, totalAmountOut / 1n]; // 2 paths, half the output in each

          balanceChange = [
            {
              account: sender,
              changes: {
                [await tokenIn.symbol()]: ['very-near', -totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', totalAmountOut],
              },
            },
            {
              account: vaultAddress,
              changes: {
                [await tokenIn.symbol()]: ['very-near', totalAmountIn],
                [await tokenOut.symbol()]: ['very-near', -totalAmountOut],
              },
            },
          ];

          paths = [
            {
              tokenIn: token0,
              steps: [
                { pool: poolA, tokenOut: poolA },
                { pool: poolA, tokenOut: token1 },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
            {
              tokenIn: token0,
              steps: [
                { pool: poolC, tokenOut: poolC },
                { pool: poolBC, tokenOut: poolB },
                { pool: poolB, tokenOut: token1 },
              ],
              exactAmountIn: pathExactAmountIn,
              minAmountOut: pathMinAmountOut,
            },
          ];

          setUp();
        });

        // The first step of first path is an 'add liquidity' operation, which is settled instantly.
        // Therefore, the transfer event will not have the total amount out as argument.
        itTestsBatchSwap(false);
      });
    });
  });
});
