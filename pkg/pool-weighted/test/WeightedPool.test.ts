import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import {
  MAX_UINT256,
  MAX_UINT160,
  MAX_UINT48,
  ZERO_BYTES32,
  ZERO_ADDRESS,
} from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { PoolConfigStructOutput } from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { WeightedPoolFactory } from '../typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { TokenConfig } from '@balancer-labs/v3-helpers/src/models/types/types';

describe('WeightedPool', function () {
  const POOL_SWAP_FEE = fp(0.01);

  const TOKEN_AMOUNT = fp(100);

  let permit2: IPermit2;
  let vault: IVaultMock;
  let pool: PoolMock;
  let router: Router;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;
  let poolTokens: string[];
  let initialBalances: bigint[];

  let tokenAAddress: string;
  let tokenBAddress: string;
  let tokenCAddress: string;

  before('setup signers', async () => {
    [, alice, bob] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    vault = await TypesConverter.toIVaultMock(await VaultDeployer.deployMock());

    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await deploy('v3-vault/Router', { args: [vault, WETH, permit2] });

    const factoryAddress = await vault.getPoolFactoryMock();
    const factory = await deployedAt('v3-vault/PoolFactoryMock', factoryAddress);

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
    tokenC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();
    tokenCAddress = await tokenC.getAddress();

    poolTokens = sortAddresses([tokenAAddress, tokenBAddress, tokenCAddress]);

    pool = await deploy('v3-vault/PoolMock', {
      args: [vault, 'Pool', 'POOL'],
    });

    await factory.registerTestPool(pool, buildTokenConfig(poolTokens));
  });

  describe('initialization', () => {
    context('uninitialized', () => {
      it('is registered, but not initialized on deployment', async () => {
        const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.false;
      });
    });

    context('initialized', () => {
      sharedBeforeEach('initialize pool', async () => {
        await tokenA.mint(alice, TOKEN_AMOUNT);
        await tokenB.mint(alice, TOKEN_AMOUNT);
        await tokenC.mint(alice, TOKEN_AMOUNT);

        await pool.connect(alice).approve(router, MAX_UINT256);
        for (const token of [tokenA, tokenB, tokenC]) {
          await token.connect(alice).approve(permit2, MAX_UINT256);
          await permit2.connect(alice).approve(token, router, MAX_UINT160, MAX_UINT48);
        }

        initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
        const idxTokenC = poolTokens.indexOf(tokenCAddress);
        initialBalances[idxTokenC] = 0n;

        expect(await router.connect(alice).initialize(pool, poolTokens, initialBalances, FP_ZERO, false, '0x'))
          .to.emit(vault, 'PoolInitialized')
          .withArgs(pool);
      });

      it('is registered and initialized', async () => {
        const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;
        expect(poolConfig.isPoolPaused).to.be.false;
      });

      it('cannot be initialized twice', async () => {
        await expect(router.connect(alice).initialize(pool, poolTokens, initialBalances, FP_ZERO, false, '0x'))
          .to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized')
          .withArgs(await pool.getAddress());
      });
    });
  });

  describe('protocol fee events on swap', () => {
    const FACTORY_VERSION = 'Weighted Factory v1';
    const POOL_VERSION = 'Weighted Pool v1';

    const WEIGHTS = [fp(0.5), fp(0.5)];
    const REAL_POOL_INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT];
    const SWAP_AMOUNT = fp(20);

    const SWAP_FEE = fp(0.01);

    let factory: WeightedPoolFactory;
    let realPool: Contract;
    let realPoolAddress: string;

    sharedBeforeEach('create and initialize pool', async () => {
      factory = await deploy('WeightedPoolFactory', {
        args: [await vault.getAddress(), MONTH * 12, FACTORY_VERSION, POOL_VERSION],
      });
      const realPoolTokens = sortAddresses([tokenAAddress, tokenBAddress]);

      const tokenConfig: TokenConfig[] = buildTokenConfig(realPoolTokens);

      const tx = await factory.create(
        'WeightedPool',
        'Test',
        tokenConfig,
        WEIGHTS,
        [ZERO_ADDRESS, ZERO_ADDRESS, ZERO_ADDRESS],
        SWAP_FEE,
        ZERO_ADDRESS,
        ZERO_BYTES32
      );
      const receipt = await tx.wait();
      const event = expectEvent.inReceipt(receipt, 'PoolCreated');

      realPoolAddress = event.args.pool;

      realPool = await deployedAt('WeightedPool', realPoolAddress);

      await tokenA.mint(bob, TOKEN_AMOUNT + SWAP_AMOUNT);
      await tokenB.mint(bob, TOKEN_AMOUNT);

      await realPool.connect(bob).approve(router, MAX_UINT256);
      for (const token of [tokenA, tokenB]) {
        await token.connect(bob).approve(permit2, MAX_UINT256);
        await permit2.connect(bob).approve(token, router, MAX_UINT160, MAX_UINT48);
      }

      await expect(
        await router.connect(bob).initialize(realPool, realPoolTokens, REAL_POOL_INITIAL_BALANCES, FP_ZERO, false, '0x')
      )
        .to.emit(vault, 'PoolInitialized')
        .withArgs(realPoolAddress);
    });

    sharedBeforeEach('grant permission', async () => {
      const setPoolSwapFeeAction = await actionId(vault, 'setStaticSwapFeePercentage');

      const authorizerAddress = await vault.getAuthorizer();
      const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

      await authorizer.grantRole(setPoolSwapFeeAction, bob.address);

      await vault.connect(bob).setStaticSwapFeePercentage(realPoolAddress, POOL_SWAP_FEE);
    });

    it('should have correct versions', async () => {
      expect(await factory.version()).to.eq(FACTORY_VERSION);
      expect(await factory.getPoolVersion()).to.eq(POOL_VERSION);
      expect(await realPool.version()).to.eq(POOL_VERSION);
    });

    it('pool and protocol fee preconditions', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(realPool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await vault.getStaticSwapFeePercentage(realPoolAddress)).to.eq(POOL_SWAP_FEE);
    });
  });
});
