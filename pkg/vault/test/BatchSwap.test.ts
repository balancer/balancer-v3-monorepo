import { ethers } from 'hardhat';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import { Router, Vault } from '../typechain-types';
import { expectBalanceChange } from '@balancer-labs/v3-helpers/src/test/tokenBalance';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';

describe('BatchSwap', function () {
  let vault: Vault;
  let poolA: PoolMock;
  let poolB: PoolMock;
  let poolC: PoolMock;
  let tokens: ERC20TokenList;
  let router: Router;

  let lp: SignerWithAddress, sender: SignerWithAddress;

  let poolATokens: string[];
  let poolBTokens: string[];
  let poolCTokens: string[];
  let token0: string;
  let token1: string;
  let token2: string;

  before('setup signers', async () => {
    [, lp, sender] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await VaultDeployer.deploy();
    const vaultAddress = await vault.getAddress();
    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('Router', { args: [vaultAddress, WETH] });

    tokens = await ERC20TokenList.create(3);
    token0 = await tokens.get(0).address();
    token1 = await tokens.get(1).address();
    token2 = await tokens.get(2).address();
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

  sharedBeforeEach('initialize pools', async () => {
    tokens.mint({ to: lp, amount: fp(1e12) });
    tokens.mint({ to: sender, amount: fp(1e12) });
    tokens.approve({ to: await vault.getAddress(), from: lp, amount: MAX_UINT256 });
    tokens.approve({ to: await vault.getAddress(), from: sender, amount: MAX_UINT256 });

    await router.connect(lp).initialize(poolA, poolATokens, Array(poolATokens.length).fill(fp(1000)), 0, false, '0x');
    await router.connect(lp).initialize(poolB, poolBTokens, Array(poolBTokens.length).fill(fp(1000)), 0, false, '0x');
    await router.connect(lp).initialize(poolC, poolCTokens, Array(poolCTokens.length).fill(fp(1000)), 0, false, '0x');
  });

  describe('batch swap given in', () => {
    let doSwap: () => Promise<unknown>;
    context('swaps with no nesting', () => {
      context('single path', () => {
        sharedBeforeEach(async () => {
          doSwap = async () =>
            router.connect(sender).swapExactIn(
              [
                {
                  tokenIn: token0,
                  steps: [
                    { pool: poolA, tokenOut: token1 },
                    { pool: poolB, tokenOut: token2 },
                  ],
                  exactAmountIn: fp(1),
                  minAmountOut: fp(1),
                },
              ],
              MAX_UINT256,
              false,
              '0x'
            );
        });

        it('performs swap', async () => {
          await expectBalanceChange(doSwap, tokens, [
            { account: sender, changes: { TK0: ['equal', fp(-1)], TK2: ['equal', fp(1)] } },
            { account: await vault.getAddress(), changes: { TK0: ['equal', fp(1)], TK2: ['equal', fp(-1)] } },
          ]);
        });
      });

      context('multi path', () => {
        sharedBeforeEach(async () => {
          doSwap = async () =>
            router.connect(sender).swapExactIn(
              [
                {
                  tokenIn: token0,
                  steps: [
                    { pool: poolA, tokenOut: token1 },
                    { pool: poolB, tokenOut: token2 },
                  ],
                  exactAmountIn: fp(1),
                  minAmountOut: fp(1),
                },
                {
                  tokenIn: token0,
                  steps: [{ pool: poolC, tokenOut: token2 }],
                  exactAmountIn: fp(1),
                  minAmountOut: fp(1),
                },
              ],
              MAX_UINT256,
              false,
              '0x'
            );
        });

        it('performs swap', async () => {
          await expectBalanceChange(doSwap, tokens, [
            { account: sender, changes: { TK0: ['equal', fp(-2)], TK2: ['equal', fp(2)] } },
            { account: await vault.getAddress(), changes: { TK0: ['equal', fp(2)], TK2: ['equal', fp(-2)] } },
          ]);
        });
      });
    });
  });
});
