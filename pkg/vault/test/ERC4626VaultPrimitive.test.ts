import { ethers } from 'hardhat';
import { expect } from 'chai';
import { VoidSigner } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import {
  BatchRouter,
  ERC4626RateProvider,
  PoolMock,
  PoolFactoryMock,
  Router,
} from '@balancer-labs/v3-vault/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { currentTimestamp, MONTH } from '@balancer-labs/v3-helpers/src/time';
import { ERC20TestToken, ERC4626TestToken, WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { PoolConfigStructOutput, VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { deployPermit2 } from './Permit2Deployer';
import '@balancer-labs/v3-common/setupTests';
import { buildTokenConfig } from './poolSetup';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';

describe('ERC4626VaultPrimitive', function () {
  const TOKEN_AMOUNT = fp(1000);
  const SWAP_AMOUNT = fp(100);
  const MIN_BPT = bn(1e6);

  let permit2: IPermit2;
  let vault: IVaultMock;
  let router: Router;
  let batchRouter: BatchRouter;
  let factory: PoolFactoryMock;
  let pool: PoolMock;
  let wDAI: ERC4626TestToken;
  let DAI: ERC20TestToken;
  let wUSDC: ERC4626TestToken;
  let USDC: ERC20TestToken;
  let boostedPoolTokens: string[];

  let lp: SignerWithAddress;
  let zero: VoidSigner;

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, lp] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool factory', async function () {
    const vaultMock: VaultMock = await VaultDeployer.deployMock();
    vault = await TypesConverter.toIVaultMock(vaultMock);

    permit2 = await deployPermit2();
    const WETH: WETHTestToken = await deploy('v3-solidity-utils/WETHTestToken');
    batchRouter = await deploy('v3-vault/BatchRouter', { args: [vault, await WETH.getAddress(), permit2] });
    router = await deploy('v3-vault/Router', { args: [vault, await WETH.getAddress(), permit2] });

    DAI = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['DAI', 'DAI', 18] });
    wDAI = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [DAI, 'Wrapped DAI', 'wDAI', 18],
    });

    // Using USDC as 18 decimals for simplicity
    USDC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['USDC', 'USDC', 18] });
    wUSDC = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [USDC, 'Wrapped USDC', 'wUSDC', 18],
    });

    boostedPoolTokens = sortAddresses([await wDAI.getAddress(), await wUSDC.getAddress()]);

    factory = await deploy('v3-vault/PoolFactoryMock', { args: [vault, 12 * MONTH] });
  });

  async function createBoostedPool(): Promise<PoolMock> {
    // initialize assets and supply
    await DAI.mint(lp, TOKEN_AMOUNT);
    await DAI.connect(lp).approve(wDAI, TOKEN_AMOUNT);
    await wDAI.connect(lp).deposit(TOKEN_AMOUNT, lp);

    await USDC.mint(lp, TOKEN_AMOUNT);
    await USDC.connect(lp).approve(wUSDC, TOKEN_AMOUNT);
    await wUSDC.connect(lp).deposit(TOKEN_AMOUNT, lp);

    pool = await deploy('v3-vault/PoolMock', {
      args: [await vault.getAddress(), 'Boosted Pool DAI-USDC', 'BP-DAI_USDC'],
    });

    const rpwDAI: ERC4626RateProvider = await deploy('v3-vault/ERC4626RateProvider', {
      args: [await wDAI.getAddress()],
    });

    const rpwUSDC: ERC4626RateProvider = await deploy('v3-vault/ERC4626RateProvider', {
      args: [await wUSDC.getAddress()],
    });

    await factory
      .connect(lp)
      .registerTestPool(
        pool,
        buildTokenConfig(boostedPoolTokens, [await rpwDAI.getAddress(), await rpwUSDC.getAddress()]),
        ZERO_ADDRESS
      );

    return (await deployedAt('PoolMock', await pool.getAddress())) as unknown as PoolMock;
  }

  async function createAndInitializeBoostedPool(): Promise<PoolMock> {
    pool = await createBoostedPool();

    await pool.connect(lp).approve(router, MAX_UINT256);
    for (const token of [wDAI, wUSDC]) {
      await token.connect(lp).approve(permit2, MAX_UINT256);
      await permit2.connect(lp).approve(token, router, MAX_UINT160, MAX_UINT48);
      await permit2.connect(lp).approve(token, batchRouter, MAX_UINT160, MAX_UINT48);
    }

    await router.connect(lp).initialize(pool, boostedPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');

    return pool;
  }

  describe('registration', () => {
    sharedBeforeEach('register factory and create pool', async () => {
      pool = await createBoostedPool();
    });

    it('pool has correct metadata', async () => {
      expect(await pool.name()).to.eq('Boosted Pool DAI-USDC');
      expect(await pool.symbol()).to.eq('BP-DAI_USDC');
    });

    it('registers the pool', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.false;
    });

    it('has the correct tokens', async () => {
      const actualTokens = await vault.getPoolTokens(pool);

      expect(actualTokens).to.deep.equal(boostedPoolTokens);
    });

    it('configures the pool correctly', async () => {
      const currentTime = await currentTimestamp();
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      const [paused] = await vault.getPoolPausedState(pool);
      expect(paused).to.be.false;

      expect(poolConfig.pauseWindowEndTime).to.gt(currentTime);
      expect(poolConfig.hooks.shouldCallBeforeInitialize).to.be.false;
      expect(poolConfig.hooks.shouldCallAfterInitialize).to.be.false;
      expect(poolConfig.hooks.shouldCallBeforeAddLiquidity).to.be.false;
      expect(poolConfig.hooks.shouldCallAfterAddLiquidity).to.be.false;
      expect(poolConfig.hooks.shouldCallBeforeRemoveLiquidity).to.be.false;
      expect(poolConfig.hooks.shouldCallAfterRemoveLiquidity).to.be.false;
      expect(poolConfig.hooks.shouldCallBeforeSwap).to.be.false;
      expect(poolConfig.hooks.shouldCallAfterSwap).to.be.false;
      expect(poolConfig.liquidityManagement.disableUnbalancedLiquidity).to.be.false;
      expect(poolConfig.liquidityManagement.enableAddLiquidityCustom).to.be.true;
      expect(poolConfig.liquidityManagement.enableRemoveLiquidityCustom).to.be.true;
    });
  });

  describe('initialization', () => {
    sharedBeforeEach('create pool', async () => {
      pool = await createBoostedPool();

      await pool.connect(lp).approve(router, MAX_UINT256);
      for (const token of [wDAI, wUSDC]) {
        await token.connect(lp).approve(permit2, MAX_UINT256);
        await permit2.connect(lp).approve(token, router, MAX_UINT160, MAX_UINT48);
      }
    });

    it('satisfies preconditions', async () => {
      expect(await wDAI.balanceOf(lp)).to.eq(TOKEN_AMOUNT);
      expect(await wUSDC.balanceOf(lp)).to.eq(TOKEN_AMOUNT);
    });

    it('emits an event', async () => {
      expect(
        await router.connect(lp).initialize(pool, boostedPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      )
        .to.emit(vault, 'PoolInitialized')
        .withArgs(pool);
    });

    it('updates the state', async () => {
      await router.connect(lp).initialize(pool, boostedPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');

      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await pool.balanceOf(lp)).to.eq(TOKEN_AMOUNT * 2n - MIN_BPT);
      expect(await wDAI.balanceOf(lp)).to.eq(0);
      expect(await wUSDC.balanceOf(lp)).to.eq(0);

      const [tokenConfig, balances] = await vault.getPoolTokenInfo(pool);
      const tokenTypes = tokenConfig.map((config) => config.tokenType);

      const expectedTokenTypes = boostedPoolTokens.map(() => TokenType.WITH_RATE);
      expect(tokenTypes).to.deep.equal(expectedTokenTypes);
      expect(balances).to.deep.equal([TOKEN_AMOUNT, TOKEN_AMOUNT]);
    });

    it('cannot be initialized twice', async () => {
      await router.connect(lp).initialize(pool, boostedPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');
      await expect(
        router.connect(lp).initialize(pool, boostedPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      ).to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized');
    });
  });

  describe('queries', () => {
    sharedBeforeEach('create and initialize pool', async () => {
      pool = await createAndInitializeBoostedPool();
    });

    it('should not require tokens in advance to querySwapExactIn using buffer', async () => {
      // Check that vault does not have tokenIn balance (DAI)
      const reservesBefore = await vault.getReservesOf(await DAI.getAddress());
      expect(reservesBefore).to.be.eq(0, 'DAI balance is wrong');

      const paths = [
        {
          tokenIn: DAI,
          steps: [
            { pool: wDAI, tokenOut: wDAI, isBuffer: true },
            { pool: pool, tokenOut: wUSDC, isBuffer: false },
            { pool: wUSDC, tokenOut: USDC, isBuffer: true },
          ],
          exactAmountIn: SWAP_AMOUNT,
          minAmountOut: SWAP_AMOUNT,
        },
      ];

      const output = await batchRouter.connect(zero).querySwapExactIn.staticCall(paths, '0x');

      expect(output.pathAmountsOut).to.have.length(1, 'Wrong pathAmountsOut length');
      expect(output.pathAmountsOut[0]).to.be.equal(SWAP_AMOUNT, 'Wrong pathAmountsOut value');
      expect(output.amountsOut).to.have.length(1, 'Wrong amountsOut length');
      expect(output.amountsOut[0]).to.be.equal(SWAP_AMOUNT, 'Wrong amountsOut value');
      expect(output.tokensOut).to.have.length(1, 'Wrong tokensOut length');
      expect(output.tokensOut[0]).to.be.equal(await USDC.getAddress(), 'Wrong tokensOut value');
    });

    it('should not require tokens in advance to querySwapExactOut using buffer', async () => {
      // Check that vault does not have tokenIn balance (DAI)
      const reservesBefore = await vault.getReservesOf(await DAI.getAddress());
      expect(reservesBefore).to.be.eq(0, 'DAI balance is wrong');

      const paths = [
        {
          tokenIn: DAI,
          steps: [
            { pool: wDAI, tokenOut: wDAI, isBuffer: true },
            { pool: pool, tokenOut: wUSDC, isBuffer: false },
            { pool: wUSDC, tokenOut: USDC, isBuffer: true },
          ],
          exactAmountOut: SWAP_AMOUNT,
          maxAmountIn: SWAP_AMOUNT,
        },
      ];

      const output = await batchRouter.connect(zero).querySwapExactOut.staticCall(paths, '0x');

      expect(output.pathAmountsIn).to.have.length(1, 'Wrong pathAmountsIn length');
      expect(output.pathAmountsIn[0]).to.be.equal(SWAP_AMOUNT, 'Wrong pathAmountsIn value');
      expect(output.amountsIn).to.have.length(1, 'Wrong amountsIn length');
      expect(output.amountsIn[0]).to.be.equal(SWAP_AMOUNT, 'Wrong amountsIn value');
      expect(output.tokensIn).to.have.length(1, 'Wrong tokensIn length');
      expect(output.tokensIn[0]).to.be.equal(await DAI.getAddress(), 'Wrong tokensIn value');
    });
  });
});
