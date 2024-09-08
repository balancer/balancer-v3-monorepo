import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { FP_ZERO, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/WETHTestToken';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { StablePoolFactory } from '../typechain-types';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import {
  PoolConfigStructOutput,
  TokenConfigStruct,
} from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';

describe('StablePool', () => {
  const FACTORY_VERSION = 'Stable Factory v1';
  const POOL_VERSION = 'Stable Pool v1';

  const MAX_STABLE_TOKENS = 5;
  const TOKEN_AMOUNT = fp(1000);
  const MIN_SWAP_FEE = 1e12;

  let permit2: IPermit2;
  let vault: IVaultMock;
  let router: Router;
  let alice: SignerWithAddress;
  let tokens: ERC20TokenList;
  let factory: StablePoolFactory;
  let pool: Contract;
  let poolTokens: string[];

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, factory, and tokens', async function () {
    vault = await TypesConverter.toIVaultMock(await VaultDeployer.deployMock());

    const WETH: WETHTestToken = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await deploy('v3-vault/Router', { args: [vault, WETH, permit2] });

    factory = await deploy('StablePoolFactory', {
      args: [await vault.getAddress(), MONTH * 12, FACTORY_VERSION, POOL_VERSION],
    });

    tokens = await ERC20TokenList.create(MAX_STABLE_TOKENS, { sorted: true });
    poolTokens = await tokens.addresses;

    // mint and approve tokens
    for (const token of tokens.tokens) {
      await token.mint(alice, TOKEN_AMOUNT);
      await token.connect(alice).approve(permit2, MAX_UINT256);
      await permit2.connect(alice).approve(token, router, MAX_UINT160, MAX_UINT48);
    }
  });

  for (let i = 2; i <= MAX_STABLE_TOKENS; i++) {
    itDeploysAStablePool(i);
  }

  async function deployPool(numTokens: number) {
    const tokenConfig: TokenConfigStruct[] = buildTokenConfig(poolTokens.slice(0, numTokens));

    const tx = await factory.create(
      'Stable Pool',
      `STABLE-${numTokens}`,
      tokenConfig,
      200n,
      { pauseManager: ZERO_ADDRESS, swapFeeManager: ZERO_ADDRESS, poolCreator: ZERO_ADDRESS },
      MIN_SWAP_FEE,
      ZERO_ADDRESS,
      false, // no donations
      false, // do not disable add liquidity unbalanced
      false, // do not disable remove liquidity unbalanced
      TypesConverter.toBytes32(bn(numTokens))
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const poolAddress = event.args.pool;

    pool = await deployedAt('StablePool', poolAddress);
    await pool.connect(alice).approve(router, MAX_UINT256);
  }

  function itDeploysAStablePool(numTokens: number) {
    it(`${numTokens} token pool was deployed correctly`, async () => {
      await deployPool(numTokens);

      expect(await pool.name()).to.equal('Stable Pool');
      expect(await pool.symbol()).to.equal(`STABLE-${numTokens}`);
    });

    it('should have correct versions', async () => {
      expect(await factory.version()).to.eq(FACTORY_VERSION);
      expect(await factory.getPoolVersion()).to.eq(POOL_VERSION);

      await deployPool(numTokens);

      expect(await pool.version()).to.eq(POOL_VERSION);
    });

    describe(`initialization with ${numTokens} tokens`, () => {
      let initialBalances: bigint[];

      context('uninitialized', () => {
        it('is registered, but not initialized on deployment', async () => {
          await deployPool(numTokens);

          const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

          expect(poolConfig.isPoolRegistered).to.be.true;
          expect(poolConfig.isPoolInitialized).to.be.false;
        });
      });

      context('initialized', () => {
        sharedBeforeEach('initialize pool', async () => {
          await deployPool(numTokens);
          initialBalances = Array(numTokens).fill(TOKEN_AMOUNT);

          expect(
            await router
              .connect(alice)
              .initialize(pool, poolTokens.slice(0, numTokens), initialBalances, FP_ZERO, false, '0x')
          )
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
          const tokensFromPool = await pool.getTokens();
          expect(tokensFromPool).to.deep.equal(poolTokens.slice(0, numTokens));

          const [tokensFromVault, , balancesFromVault] = await vault.getPoolTokenInfo(pool);

          expect(tokensFromVault).to.deep.equal(tokensFromPool);
          expect(balancesFromVault).to.deep.equal(initialBalances);
        });

        it('cannot be initialized twice', async () => {
          await expect(router.connect(alice).initialize(pool, poolTokens, initialBalances, FP_ZERO, false, '0x'))
            .to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized')
            .withArgs(await pool.getAddress());
        });
      });
    });
  }
});
