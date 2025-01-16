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
import { GyroECLPPool, GyroECLPPoolFactory } from '../typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { PoolConfigStructOutput } from '@balancer-labs/v3-solidity-utils/typechain-types/@balancer-labs/v3-interfaces/contracts/vault/IVault';
import { TokenConfigStruct } from '../typechain-types/@balancer-labs/v3-interfaces/contracts/vault/IVault';

describe('E-CLP', function () {
  const FACTORY_VERSION = 'ECLP Factory v1';
  const POOL_VERSION = 'ECLP Pool v1';
  const ROUTER_VERSION = 'Router v11';

  const POOL_SWAP_FEE = fp(0.01);
  const TOKEN_AMOUNT = fp(100);

  const INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT];
  const SWAP_AMOUNT = fp(20);

  const SWAP_FEE = fp(0.01);

  const SQRT_ALPHA = fp(0.8);
  const SQRT_BETA = fp(0.9);

  // Extracted from pool 0x2191df821c198600499aa1f0031b1a7514d7a7d9 on Mainnet.
  const PARAMS_ALPHA = 998502246630054917n;
  const PARAMS_BETA = 1000200040008001600n;
  const PARAMS_C = 707106781186547524n;
  const PARAMS_S = 707106781186547524n;
  const PARAMS_LAMBDA = 4000000000000000000000n;

  const TAU_ALPHA_X = -94861212813096057289512505574275160547n;
  const TAU_ALPHA_Y = 31644119574235279926451292677567331630n;
  const TAU_BETA_X = 37142269533113549537591131345643981951n;
  const TAU_BETA_Y = 92846388265400743995957747409218517601n;
  const U = 66001741173104803338721745994955553010n;
  const V = 62245253919818011890633399060291020887n;
  const W = 30601134345582732000058913853921008022n;
  const Z = -28859471639991253843240999485797747790n;
  const DSQ = 99999999999999999886624093342106115200n;

  let permit2: IPermit2;
  let vault: IVaultMock;
  let factory: GyroECLPPoolFactory;
  let pool: GyroECLPPool;
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
    factory = await deploy('GyroECLPPoolFactory', {
      args: [await vault.getAddress(), MONTH * 12, FACTORY_VERSION, POOL_VERSION],
    });
    poolTokens = sortAddresses([tokenAAddress, tokenBAddress]);

    tokenConfig = buildTokenConfig(poolTokens);

    const tx = await factory.create(
      'E-CLP',
      'Test',
      tokenConfig,
      { alpha: PARAMS_ALPHA, beta: PARAMS_BETA, c: PARAMS_C, s: PARAMS_S, lambda: PARAMS_LAMBDA },
      {
        tauAlpha: { x: TAU_ALPHA_X, y: TAU_ALPHA_Y },
        tauBeta: { x: TAU_BETA_X, y: TAU_BETA_Y },
        u: U,
        v: V,
        w: W,
        z: Z,
        dSq: DSQ,
      },
      { pauseManager: ZERO_ADDRESS, swapFeeManager: ZERO_ADDRESS, poolCreator: ZERO_ADDRESS },
      SWAP_FEE,
      ZERO_ADDRESS,
      false, // no donations
      false, // keep support to unbalanced add/remove liquidity
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    pool = (await deployedAt('GyroECLPPool', event.args.pool)) as unknown as GyroECLPPool;

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
    const {
      paramsAlpha,
      paramsBeta,
      paramsC,
      paramsS,
      paramsLambda,
      tauAlphaX,
      tauAlphaY,
      tauBetaX,
      tauBetaY,
      u,
      v,
      w,
      z,
      dSq,
    } = await pool.getGyroECLPPoolImmutableData();
    expect(paramsAlpha).to.be.eq(PARAMS_ALPHA);
    expect(paramsBeta).to.be.eq(PARAMS_BETA);
    expect(paramsC).to.be.eq(PARAMS_C);
    expect(paramsS).to.be.eq(PARAMS_S);
    expect(paramsLambda).to.be.eq(PARAMS_LAMBDA);
    expect(tauAlphaX).to.be.eq(TAU_ALPHA_X);
    expect(tauAlphaY).to.be.eq(TAU_ALPHA_Y);
    expect(tauBetaX).to.be.eq(TAU_BETA_X);
    expect(tauBetaY).to.be.eq(TAU_BETA_Y);
    expect(u).to.be.eq(U);
    expect(v).to.be.eq(V);
    expect(w).to.be.eq(W);
    expect(z).to.be.eq(Z);
    expect(dSq).to.be.eq(DSQ);
  });

  describe('LM flags', () => {
    let newPool: GyroECLPPool;

    sharedBeforeEach('create new pool with donation and disabled unbalanced liquidity', async () => {
      const tx = await factory.create(
        'E-CLP',
        'Test',
        tokenConfig,
        { alpha: PARAMS_ALPHA, beta: PARAMS_BETA, c: PARAMS_C, s: PARAMS_S, lambda: PARAMS_LAMBDA },
        {
          tauAlpha: { x: TAU_ALPHA_X, y: TAU_ALPHA_Y },
          tauBeta: { x: TAU_BETA_X, y: TAU_BETA_Y },
          u: U,
          v: V,
          w: W,
          z: Z,
          dSq: DSQ,
        },
        { pauseManager: ZERO_ADDRESS, swapFeeManager: ZERO_ADDRESS, poolCreator: ZERO_ADDRESS },
        SWAP_FEE,
        ZERO_ADDRESS,
        true, // donations
        true, // disable support to unbalanced add/remove liquidity
        ONES_BYTES32
      );

      const receipt = await tx.wait();
      const event = expectEvent.inReceipt(receipt, 'PoolCreated');

      newPool = (await deployedAt('GyroECLPPool', event.args.pool)) as unknown as GyroECLPPool;
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
