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
  BufferRouter,
} from '@balancer-labs/v3-vault/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { currentTimestamp, MONTH } from '@balancer-labs/v3-helpers/src/time';
import { ERC20TestToken, ERC4626TestToken, WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import {
  HooksConfigStructOutput,
  PoolConfigStructOutput,
  VaultMock,
} from '../typechain-types/contracts/test/VaultMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, bn, fp, pct } from '@balancer-labs/v3-helpers/src/numbers';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { deployPermit2 } from './Permit2Deployer';
import '@balancer-labs/v3-common/setupTests';
import { buildTokenConfig } from './poolSetup';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';

describe('ERC4626VaultPrimitive', function () {
  const BATCH_ROUTER_VERSION = 'BatchRouter v9';
  const ROUTER_VERSION = 'Router v9';

  const TOKEN_AMOUNT = fp(1000);
  const SWAP_AMOUNT = fp(100);
  const MIN_BPT = bn(1e6);

  // Donate to wrapped tokens to generate different rates.
  const daiToDonate = fp((Math.random() * 1000 + 10).toFixed(0));
  const usdcToDonate = fp((Math.random() * 1000 + 10).toFixed(0));

  let permit2: IPermit2;
  let vault: IVaultMock;
  let router: Router;
  let bufferRouter: BufferRouter;
  let batchRouter: BatchRouter;
  let factory: PoolFactoryMock;
  let pool: PoolMock;
  let wDAI: ERC4626TestToken;
  let DAI: ERC20TestToken;
  let wUSDC: ERC4626TestToken;
  let USDC: ERC20TestToken;
  let yieldBearingPoolTokens: string[];

  let lp: SignerWithAddress;
  let alice: SignerWithAddress;
  let zero: VoidSigner;

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, lp, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool factory', async function () {
    const vaultMock: VaultMock = await VaultDeployer.deployMock();
    vault = await TypesConverter.toIVaultMock(vaultMock);

    permit2 = await deployPermit2();
    const WETH: WETHTestToken = await deploy('v3-solidity-utils/WETHTestToken');
    batchRouter = await deploy('v3-vault/BatchRouter', {
      args: [vault, await WETH.getAddress(), permit2, BATCH_ROUTER_VERSION],
    });
    router = await deploy('v3-vault/Router', { args: [vault, await WETH.getAddress(), permit2, ROUTER_VERSION] });
    bufferRouter = await deploy('v3-vault/BufferRouter', {
      args: [vault, await WETH.getAddress(), permit2, ROUTER_VERSION],
    });

    DAI = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['DAI', 'DAI', 18] });
    wDAI = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [DAI, 'Wrapped DAI', 'wDAI', 18],
    });

    // Using USDC as 18 decimals for simplicity.
    USDC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['USDC', 'USDC', 18] });
    wUSDC = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [USDC, 'Wrapped USDC', 'wUSDC', 18],
    });

    await DAI.mint(alice, TOKEN_AMOUNT);
    await DAI.connect(alice).approve(permit2, MAX_UINT256);
    await permit2.connect(alice).approve(DAI, batchRouter, MAX_UINT160, MAX_UINT48);

    yieldBearingPoolTokens = sortAddresses([await wDAI.getAddress(), await wUSDC.getAddress()]);

    factory = await deploy('v3-vault/PoolFactoryMock', { args: [vault, 12 * MONTH] });
  });

  async function createYieldBearingPool(): Promise<PoolMock> {
    // Initialize assets and supply.
    await DAI.mint(lp, TOKEN_AMOUNT);
    await DAI.connect(lp).approve(wDAI, TOKEN_AMOUNT);
    await wDAI.connect(lp).deposit(TOKEN_AMOUNT, lp);

    await USDC.mint(lp, TOKEN_AMOUNT);
    await USDC.connect(lp).approve(wUSDC, TOKEN_AMOUNT);
    await wUSDC.connect(lp).deposit(TOKEN_AMOUNT, lp);

    pool = await deploy('v3-vault/PoolMock', {
      args: [await vault.getAddress(), 'Yield-bearing Pool DAI-USDC', 'BP-DAI_USDC'],
    });

    const rpwDAI: ERC4626RateProvider = await deploy('v3-vault/ERC4626RateProvider', {
      args: [await wDAI.getAddress()],
    });

    const rpwUSDC: ERC4626RateProvider = await deploy('v3-vault/ERC4626RateProvider', {
      args: [await wUSDC.getAddress()],
    });

    const rateProviders: string[] = [];
    rateProviders[yieldBearingPoolTokens.indexOf(await wDAI.getAddress())] = await rpwDAI.getAddress();
    rateProviders[yieldBearingPoolTokens.indexOf(await wUSDC.getAddress())] = await rpwUSDC.getAddress();

    await factory.connect(lp).registerTestPool(pool, buildTokenConfig(yieldBearingPoolTokens, rateProviders));

    return (await deployedAt('PoolMock', await pool.getAddress())) as unknown as PoolMock;
  }

  async function createAndInitializeYieldBearingPool(): Promise<PoolMock> {
    pool = await createYieldBearingPool();

    await pool.connect(lp).approve(router, MAX_UINT256);
    await setupTokenApprovals(lp);

    await router
      .connect(lp)
      .initialize(pool, yieldBearingPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');

    return pool;
  }

  async function setupTokenApprovals(signer: SignerWithAddress) {
    for (const token of [wDAI, wUSDC, DAI, USDC]) {
      await token.connect(signer).approve(permit2, MAX_UINT256);
      await permit2.connect(signer).approve(token, router, MAX_UINT160, MAX_UINT48);
      await permit2.connect(signer).approve(token, bufferRouter, MAX_UINT160, MAX_UINT48);
      await permit2.connect(signer).approve(token, batchRouter, MAX_UINT160, MAX_UINT48);
    }
  }

  describe('registration', () => {
    sharedBeforeEach('register factory and create pool', async () => {
      pool = await createYieldBearingPool();
    });

    it('pool has correct metadata', async () => {
      expect(await pool.name()).to.eq('Yield-bearing Pool DAI-USDC');
      expect(await pool.symbol()).to.eq('BP-DAI_USDC');
    });

    it('registers the pool', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.false;
    });

    it('has the correct tokens', async () => {
      const actualTokens = await vault.getPoolTokens(pool);

      expect(actualTokens).to.deep.equal(yieldBearingPoolTokens);
    });

    it('configures the pool correctly', async () => {
      const currentTime = await currentTimestamp();
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      const [paused] = await vault.getPoolPausedState(pool);
      expect(paused).to.be.false;

      expect(poolConfig.pauseWindowEndTime).to.gt(currentTime);
      expect(poolConfig.liquidityManagement.disableUnbalancedLiquidity).to.be.false;
      expect(poolConfig.liquidityManagement.enableAddLiquidityCustom).to.be.true;
      expect(poolConfig.liquidityManagement.enableRemoveLiquidityCustom).to.be.true;

      const hooksConfig: HooksConfigStructOutput = await vault.getHooksConfig(pool);
      expect(hooksConfig.shouldCallBeforeInitialize).to.be.false;
      expect(hooksConfig.shouldCallAfterInitialize).to.be.false;
      expect(hooksConfig.shouldCallBeforeAddLiquidity).to.be.false;
      expect(hooksConfig.shouldCallAfterAddLiquidity).to.be.false;
      expect(hooksConfig.shouldCallBeforeRemoveLiquidity).to.be.false;
      expect(hooksConfig.shouldCallAfterRemoveLiquidity).to.be.false;
      expect(hooksConfig.shouldCallBeforeSwap).to.be.false;
      expect(hooksConfig.shouldCallAfterSwap).to.be.false;
    });
  });

  describe('initialization', () => {
    sharedBeforeEach('create pool', async () => {
      pool = await createYieldBearingPool();

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
        await router
          .connect(lp)
          .initialize(pool, yieldBearingPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      )
        .to.emit(vault, 'PoolInitialized')
        .withArgs(pool);
    });

    it('updates the state', async () => {
      await router
        .connect(lp)
        .initialize(pool, yieldBearingPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');

      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await pool.balanceOf(lp)).to.eq(TOKEN_AMOUNT * 2n - MIN_BPT);
      expect(await wDAI.balanceOf(lp)).to.eq(0);
      expect(await wUSDC.balanceOf(lp)).to.eq(0);

      const [, tokenInfo, balances] = await vault.getPoolTokenInfo(pool);
      const tokenTypes = tokenInfo.map((config) => config.tokenType);

      const expectedTokenTypes = yieldBearingPoolTokens.map(() => TokenType.WITH_RATE);
      expect(tokenTypes).to.deep.equal(expectedTokenTypes);
      expect(balances).to.deep.equal([TOKEN_AMOUNT, TOKEN_AMOUNT]);
    });

    it('cannot be initialized twice', async () => {
      await router
        .connect(lp)
        .initialize(pool, yieldBearingPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');
      await expect(
        router.connect(lp).initialize(pool, yieldBearingPoolTokens, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      ).to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized');
    });
  });

  describe('queries', () => {
    const bufferInitAmount = fp(1);

    sharedBeforeEach('create and initialize pool', async () => {
      pool = await createAndInitializeYieldBearingPool();

      // Donate to wrapped tokens to generate different rates.
      await DAI.mint(lp, daiToDonate);
      await DAI.connect(lp).transfer(await wDAI.getAddress(), daiToDonate);
      await USDC.mint(lp, usdcToDonate);
      await USDC.connect(lp).transfer(await wUSDC.getAddress(), usdcToDonate);

      await DAI.mint(lp, bufferInitAmount);
      await USDC.mint(lp, bufferInitAmount);
      await bufferRouter.connect(lp).initializeBuffer(wDAI, bufferInitAmount, 0, 0);
      await bufferRouter.connect(lp).initializeBuffer(wUSDC, bufferInitAmount, 0, 0);
    });

    it('should not require tokens in advance to querySwapExactIn using buffer', async () => {
      // Check that vault does not have tokenIn balance (DAI).
      const reservesBefore = await vault.getReservesOf(await DAI.getAddress());
      expect(reservesBefore).to.be.eq(bufferInitAmount, 'DAI balance is wrong');

      const paths = [
        {
          tokenIn: DAI,
          steps: [
            { pool: wDAI, tokenOut: wDAI, isBuffer: true },
            { pool: pool, tokenOut: wUSDC, isBuffer: false },
            { pool: wUSDC, tokenOut: USDC, isBuffer: true },
          ],
          exactAmountIn: SWAP_AMOUNT,
          minAmountOut: 0,
        },
      ];

      const queryOutput = await batchRouter.connect(zero).querySwapExactIn.staticCall(paths, zero.address, '0x');
      expect(queryOutput.pathAmountsOut).to.have.length(1, 'Wrong query pathAmountsOut length');
      expect(queryOutput.amountsOut).to.have.length(1, 'Wrong query amountsOut length');
      expect(queryOutput.tokensOut).to.have.length(1, 'Wrong query tokensOut length');
      expect(queryOutput.tokensOut[0]).to.be.equal(await USDC.getAddress(), 'Wrong query tokensOut value');

      // Connect Alice since the real transaction requires user to have tokens.
      const staticActualOutput = await batchRouter
        .connect(alice)
        .swapExactIn.staticCall(paths, MAX_UINT256, false, '0x');
      expect(staticActualOutput.pathAmountsOut).to.have.length(1, 'Wrong actual pathAmountsOut length');
      expect(staticActualOutput.amountsOut).to.have.length(1, 'Wrong actual amountsOut length');
      expect(staticActualOutput.tokensOut).to.have.length(1, 'Wrong actual tokensOut length');
      expect(staticActualOutput.tokensOut[0]).to.be.equal(await USDC.getAddress(), 'Wrong actual tokensOut value');

      // Check if real transaction and query transaction are approx the same (tolerates an error when token is
      // wrapped/unwrapped and rate changes in the real operation).
      expect(staticActualOutput.pathAmountsOut[0]).to.be.almostEqual(
        queryOutput.pathAmountsOut[0],
        1e-10,
        'Wrong actual pathAmountsOut value'
      );
      expect(staticActualOutput.amountsOut[0]).to.be.almostEqual(
        queryOutput.amountsOut[0],
        1e-10,
        'Wrong actual amountsOut value'
      );

      // Connect Alice since the real transaction requires user to have tokens.
      const actualOutput = await batchRouter.connect(alice).swapExactIn(paths, MAX_UINT256, false, '0x');
      expect(actualOutput)
        .to.emit(await DAI.getAddress(), 'Transfer')
        .withArgs(await alice.getAddress(), await vault.getAddress(), SWAP_AMOUNT);
      expect(actualOutput)
        .to.emit(await USDC.getAddress(), 'Transfer')
        .withArgs(await vault.getAddress(), await alice.getAddress(), queryOutput.amountsOut[0]);
    });

    it('should not require tokens in advance to querySwapExactOut using buffer', async () => {
      // Check that vault does not have tokenIn balance (DAI).
      const reservesBefore = await vault.getReservesOf(await DAI.getAddress());
      expect(reservesBefore).to.be.eq(bufferInitAmount, 'DAI balance is wrong');

      const paths = [
        {
          tokenIn: DAI,
          steps: [
            { pool: wDAI, tokenOut: wDAI, isBuffer: true },
            { pool: pool, tokenOut: wUSDC, isBuffer: false },
            { pool: wUSDC, tokenOut: USDC, isBuffer: true },
          ],
          exactAmountOut: SWAP_AMOUNT,
          // max amount is twice the SWAP_AMOUNT.
          maxAmountIn: pct(SWAP_AMOUNT, 2),
        },
      ];

      const queryOutput = await batchRouter.connect(zero).querySwapExactOut.staticCall(paths, zero.address, '0x');
      expect(queryOutput.pathAmountsIn).to.have.length(1, 'Wrong query pathAmountsIn length');
      expect(queryOutput.amountsIn).to.have.length(1, 'Wrong query amountsIn length');
      expect(queryOutput.tokensIn).to.have.length(1, 'Wrong query tokensIn length');
      expect(queryOutput.tokensIn[0]).to.be.equal(await DAI.getAddress(), 'Wrong query tokensIn value');

      // Connect Alice since the real transaction requires user to have tokens.
      const staticActualOutput = await batchRouter
        .connect(alice)
        .swapExactOut.staticCall(paths, MAX_UINT256, false, '0x');
      expect(staticActualOutput.pathAmountsIn).to.have.length(1, 'Wrong actual pathAmountsIn length');
      expect(staticActualOutput.amountsIn).to.have.length(1, 'Wrong actual amountsIn length');
      expect(staticActualOutput.tokensIn).to.have.length(1, 'Wrong actual tokensIn length');
      expect(staticActualOutput.tokensIn[0]).to.be.equal(await DAI.getAddress(), 'Wrong actual tokensIn value');

      // Check if real transaction and query transaction are approx the same (tolerates an error when token is
      // wrapped/unwrapped and rate changes in the real operation).
      expect(staticActualOutput.pathAmountsIn[0]).to.be.almostEqual(
        queryOutput.pathAmountsIn[0],
        1e-10,
        'Wrong actual pathAmountsIn value'
      );
      expect(staticActualOutput.amountsIn[0]).to.be.almostEqual(
        queryOutput.amountsIn[0],
        1e-10,
        'Wrong actual amountsIn value'
      );

      // Connect Alice since the real transaction requires user to have tokens.
      const actualOutput = await batchRouter.connect(alice).swapExactOut(paths, MAX_UINT256, false, '0x');
      expect(actualOutput)
        .to.emit(await DAI.getAddress(), 'Transfer')
        .withArgs(await alice.getAddress(), await vault.getAddress(), queryOutput.amountsIn[0]);
      expect(actualOutput)
        .to.emit(await USDC.getAddress(), 'Transfer')
        .withArgs(await vault.getAddress(), await alice.getAddress(), SWAP_AMOUNT);
    });
  });
});
