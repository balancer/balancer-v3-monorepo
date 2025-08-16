import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import {
  MAX_UINT256,
  MAX_UINT160,
  MAX_UINT48,
  ZERO_BYTES32,
  ZERO_ADDRESS,
  ONES_BYTES32,
} from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { Gyro2CLPPool, Gyro2CLPPoolFactory } from '../typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { PoolConfigStructOutput } from '@balancer-labs/v3-solidity-utils/typechain-types/@balancer-labs/v3-interfaces/contracts/vault/IVault';
import { TokenConfigStruct } from '../typechain-types/@balancer-labs/v3-interfaces/contracts/vault/IVault';

describe('2-CLP', function () {
  const FACTORY_VERSION = '2-CLP Factory v1';
  const POOL_VERSION = '2-CLP Pool v1';
  const ROUTER_VERSION = 'Router v11';

  const POOL_SWAP_FEE = fp(0.01);
  const TOKEN_AMOUNT = fp(100);

  const INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT];
  const SWAP_AMOUNT = fp(20);

  const SWAP_FEE = fp(0.01);

  const SQRT_ALPHA = fp(0.8);
  const SQRT_BETA = fp(0.9);

  let permit2: IPermit2;
  let vault: IVaultMock;
  let factory: Gyro2CLPPoolFactory;
  let pool: Gyro2CLPPool;
  let router: Router;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let poolTokens: string[];

  let tokenAAddress: string;
  let tokenBAddress: string;
  let tokenConfig: TokenConfigStruct[];

  before('setup signers', async () => {
    [, alice, bob] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    vault = await TypesConverter.toIVaultMock(await VaultDeployer.deployMock());

    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await deploy('v3-vault/Router', { args: [vault, WETH, permit2, ROUTER_VERSION] });

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });

    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();
  });

  sharedBeforeEach('create and initialize pool', async () => {
    factory = await deploy('Gyro2CLPPoolFactory', {
      args: [await vault.getAddress(), MONTH * 12, FACTORY_VERSION, POOL_VERSION],
    });
    poolTokens = sortAddresses([tokenAAddress, tokenBAddress]);

    tokenConfig = buildTokenConfig(poolTokens);

    const tx = await factory.create(
      '2-CLP',
      'Test',
      tokenConfig,
      SQRT_ALPHA,
      SQRT_BETA,
      { pauseManager: ZERO_ADDRESS, swapFeeManager: ZERO_ADDRESS, poolCreator: ZERO_ADDRESS },
      SWAP_FEE,
      ZERO_ADDRESS,
      false, // no donations
      false, // keep support to unbalanced add/remove liquidity
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    pool = (await deployedAt('Gyro2CLPPool', event.args.pool)) as unknown as Gyro2CLPPool;

    await tokenA.mint(bob, TOKEN_AMOUNT + SWAP_AMOUNT);
    await tokenB.mint(bob, TOKEN_AMOUNT);

    await pool.connect(bob).approve(router, MAX_UINT256);
    for (const token of [tokenA, tokenB]) {
      await token.connect(bob).approve(permit2, MAX_UINT256);
      await permit2.connect(bob).approve(token, router, MAX_UINT160, MAX_UINT48);
    }

    await expect(await router.connect(bob).initialize(pool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x'))
      .to.emit(vault, 'PoolInitialized')
      .withArgs(pool);
  });

  sharedBeforeEach('grant permission', async () => {
    const setPoolSwapFeeAction = await actionId(vault, 'setStaticSwapFeePercentage');

    const authorizerAddress = await vault.getAuthorizer();
    const authorizer = await deployedAt('v3-vault/BasicAuthorizerMock', authorizerAddress);

    await authorizer.grantRole(setPoolSwapFeeAction, bob.address);

    await vault.connect(bob).setStaticSwapFeePercentage(pool, POOL_SWAP_FEE);
  });

  it('should have correct versions', async () => {
    expect(await factory.version()).to.eq(FACTORY_VERSION);
    expect(await factory.getPoolVersion()).to.eq(POOL_VERSION);
    expect(await pool.version()).to.eq(POOL_VERSION);
  });

  it('pool and protocol fee preconditions', async () => {
    const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

    expect(poolConfig.isPoolRegistered).to.be.true;
    expect(poolConfig.isPoolInitialized).to.be.true;

    expect(await vault.getStaticSwapFeePercentage(pool)).to.eq(POOL_SWAP_FEE);
  });

  it('has the correct pool tokens and balances', async () => {
    const tokensFromPool = await pool.getTokens();
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

  it('returns immutable data', async () => {
    const { sqrtAlpha, sqrtBeta } = await pool.getGyro2CLPPoolImmutableData();
    expect(sqrtAlpha).to.be.eq(SQRT_ALPHA);
    expect(sqrtBeta).to.be.eq(SQRT_BETA);
  });

  it('is registered in the factory', async () => {
    expect(await factory.getPoolCount()).to.be.eq(1);
    expect(await factory.getPools()).to.be.deep.eq([await pool.getAddress()]);
  });

  describe('LM flags', () => {
    let newPool: Gyro2CLPPool;

    sharedBeforeEach('create new pool with donation and disabled unbalanced liquidity', async () => {
      const tx = await factory.create(
        '2-CLP',
        'Test',
        tokenConfig,
        SQRT_ALPHA,
        SQRT_BETA,
        { pauseManager: ZERO_ADDRESS, swapFeeManager: ZERO_ADDRESS, poolCreator: ZERO_ADDRESS },
        SWAP_FEE,
        ZERO_ADDRESS,
        true, // donations
        true, // disable support to unbalanced add/remove liquidity
        ONES_BYTES32
      );

      const receipt = await tx.wait();
      const event = expectEvent.inReceipt(receipt, 'PoolCreated');

      newPool = (await deployedAt('Gyro2CLPPool', event.args.pool)) as unknown as Gyro2CLPPool;
    });

    it('allows donation', async () => {
      const { liquidityManagement } = await vault.getPoolConfig(newPool);
      expect(liquidityManagement.enableDonation).to.be.true;
    });

    it('does not allow unbalanced liquidity', async () => {
      const { liquidityManagement } = await vault.getPoolConfig(newPool);
      expect(liquidityManagement.disableUnbalancedLiquidity).to.be.true;
    });
  });
});
