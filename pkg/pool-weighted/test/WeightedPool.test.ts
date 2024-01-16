import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/WETHTestToken';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { Vault } from '@balancer-labs/v3-vault/typechain-types';
import { PoolConfigStructOutput } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';

describe('WeightedPool', function () {
  let vault: Vault;
  let pool: PoolMock;
  let router: Router;
  let alice: SignerWithAddress;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;
  let poolTokens: string[];

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    vault = await VaultDeployer.deploy();

    const WETH: WETHTestToken = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('v3-vault/Router', { args: [vault, await WETH.getAddress()] });

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
    tokenC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

    const tokenAAddress = await tokenA.getAddress();
    const tokenBAddress = await tokenB.getAddress();
    const tokenCAddress = await tokenC.getAddress();

    poolTokens = [tokenAAddress, tokenBAddress, tokenCAddress];
    const rateProviders = [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS];

    pool = await deploy('v3-vault/PoolMock', {
      args: [vault, 'Pool', 'POOL', poolTokens, rateProviders, true, 365 * 24 * 3600, ZERO_ADDRESS],
    });
  });

  describe('initialization', () => {
    const TOKEN_AMOUNT = fp(100);
    const INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT, FP_ZERO];

    context('uninitialized', () => {
      it('is registered, but not initialized on deployment', async () => {
        const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.false;
      });
    });

    context('initialized', () => {
      sharedBeforeEach('initialize pool', async () => {
        tokenA.mint(alice, TOKEN_AMOUNT);
        tokenB.mint(alice, TOKEN_AMOUNT);

        tokenA.connect(alice).approve(vault, MAX_UINT256);
        tokenB.connect(alice).approve(vault, MAX_UINT256);

        expect(await router.connect(alice).initialize(pool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x'))
          .to.emit(vault, 'PoolInitialized')
          .withArgs(pool);
      });

      it('is registered and initialized', async () => {
        const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;
        expect(poolConfig.isPoolPaused).to.be.false;
      });

      it('has the correct pool tokens and balances', async () => {
        const tokensFromPool = await pool.getPoolTokens();
        expect(tokensFromPool).to.deep.equal(poolTokens);

        const [tokensFromVault, , balancesFromVault] = await vault.getPoolTokenInfo(pool);
        expect(tokensFromVault).to.deep.equal(tokensFromPool);
        expect(balancesFromVault).to.deep.equal(INITIAL_BALANCES);
      });

      it('cannot be initialized twice', async () => {
        await expect(router.connect(alice).initialize(pool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x'))
          .to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized')
          .withArgs(await pool.getAddress());
      });
    });
  });
});
