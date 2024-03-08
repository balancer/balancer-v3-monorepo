import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/WETHTestToken';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, ZERO_ADDRESS, ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import {
  PoolConfigStructOutput,
  TokenConfigStruct,
} from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { WeightedPoolFactory } from '../typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { TokenConfig, TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';

describe('WeightedPool', function () {
  const MAX_PROTOCOL_SWAP_FEE = fp(0.5);
  const MAX_PROTOCOL_YIELD_FEE = fp(0.2);
  const POOL_SWAP_FEE = fp(0.01);

  const TOKEN_AMOUNT = fp(100);
  const INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT, FP_ZERO];

  let vault: IVaultMock;
  let pool: PoolMock;
  let router: Router;
  let alice: SignerWithAddress;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;
  let poolTokens: string[];

  let tokenAAddress: string;
  let tokenBAddress: string;
  let tokenCAddress: string;

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    vault = await TypesConverter.toIVaultMock(await VaultDeployer.deployMock());

    const WETH: WETHTestToken = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('v3-vault/Router', { args: [vault, await WETH.getAddress()] });

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
    tokenC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();
    tokenCAddress = await tokenC.getAddress();

    poolTokens = sortAddresses([tokenAAddress, tokenBAddress, tokenCAddress]);

    pool = await deploy('v3-vault/PoolMock', {
      args: [vault, 'Pool', 'POOL', buildTokenConfig(poolTokens), true, 365 * 24 * 3600, ZERO_ADDRESS],
    });
  });

  describe('initialization', () => {
    context('uninitialized', () => {
      it('is registered, but not initialized on deployment', async () => {
        const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.false;
        expect(poolConfig.isBufferPool).to.be.false;
      });
    });

    context('initialized', () => {
      sharedBeforeEach('initialize pool', async () => {
        tokenA.mint(alice, TOKEN_AMOUNT);
        tokenB.mint(alice, TOKEN_AMOUNT);
        tokenC.mint(alice, TOKEN_AMOUNT);

        tokenA.connect(alice).approve(vault, MAX_UINT256);
        tokenB.connect(alice).approve(vault, MAX_UINT256);
        tokenC.connect(alice).approve(vault, MAX_UINT256);

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

  describe('protocol fee events on swap', () => {
    const WEIGHTS = [fp(0.5), fp(0.5)];
    const REAL_POOL_INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT];
    const SWAP_AMOUNT = fp(20);

    let factory: WeightedPoolFactory;
    let realPool: Contract;
    let realPoolAddress: string;

    sharedBeforeEach('create and initialize pool', async () => {
      factory = await deploy('WeightedPoolFactory', { args: [await vault.getAddress(), MONTH * 12] });
      const realPoolTokens = [tokenAAddress, tokenBAddress];
      const tokenConfig: TokenConfig[] = [
        { token: tokenAAddress, tokenType: TokenType.STANDARD, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
        { token: tokenBAddress, tokenType: TokenType.STANDARD, rateProvider: ZERO_ADDRESS, yieldFeeExempt: false },
      ];

      const tx = await factory.create('WeightedPool', 'Test', tokenConfig, WEIGHTS, ZERO_BYTES32);
      const receipt = await tx.wait();
      const event = expectEvent.inReceipt(receipt, 'PoolCreated');

      realPoolAddress = event.args.pool;

      realPool = await deployedAt('WeightedPool', realPoolAddress);

      tokenA.mint(alice, TOKEN_AMOUNT + SWAP_AMOUNT);
      tokenB.mint(alice, TOKEN_AMOUNT);

      tokenA.connect(alice).approve(vault, MAX_UINT256);
      tokenB.connect(alice).approve(vault, MAX_UINT256);

      await expect(
        await router
          .connect(alice)
          .initialize(realPool, realPoolTokens, REAL_POOL_INITIAL_BALANCES, FP_ZERO, false, '0x')
      )
        .to.emit(vault, 'PoolInitialized')
        .withArgs(realPoolAddress);
    });

    sharedBeforeEach('grant permission', async () => {
      const setSwapFeeAction = await actionId(vault, 'setProtocolSwapFeePercentage');
      const setYieldFeeAction = await actionId(vault, 'setProtocolYieldFeePercentage');
      const setPoolSwapFeeAction = await actionId(vault, 'setStaticSwapFeePercentage');

      const authorizerAddress = await vault.getAuthorizer();
      const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

      await authorizer.grantRole(setSwapFeeAction, alice.address);
      await authorizer.grantRole(setYieldFeeAction, alice.address);
      await authorizer.grantRole(setPoolSwapFeeAction, alice.address);

      await vault.connect(alice).setProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
      await vault.connect(alice).setProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
      await vault.connect(alice).setStaticSwapFeePercentage(realPoolAddress, POOL_SWAP_FEE);
    });

    it('pool and protocol fee preconditions', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(realPool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await vault.getProtocolSwapFeePercentage()).to.eq(MAX_PROTOCOL_SWAP_FEE);
      expect(await vault.getProtocolYieldFeePercentage()).to.eq(MAX_PROTOCOL_YIELD_FEE);
      expect(await vault.getStaticSwapFeePercentage(realPoolAddress)).to.eq(POOL_SWAP_FEE);
    });

    it('emits protocol swap fee event on swap', async () => {
      await expect(
        await router
          .connect(alice)
          .swapSingleTokenExactIn(
            realPoolAddress,
            tokenAAddress,
            tokenBAddress,
            SWAP_AMOUNT,
            0,
            MAX_UINT256,
            false,
            '0x'
          )
      ).to.emit(vault, 'ProtocolSwapFeeCharged');
    });
  });

  function buildTokenConfig(tokens: string[]): TokenConfigStruct[] {
    const result: TokenConfigStruct[] = [];

    tokens.map((token, i) => {
      result[i] = {
        token: token,
        tokenType: TokenType.STANDARD,
        rateProvider: ZERO_ADDRESS,
        yieldFeeExempt: false,
      };
    });

    return result;
  }
});
