import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48, ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { LBPool, LBPoolFactory } from '../typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH, MINUTE } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { PoolConfigStructOutput } from '@balancer-labs/v3-solidity-utils/typechain-types/@balancer-labs/v3-interfaces/contracts/vault/IVault';
import { TokenConfigStruct } from '../typechain-types/@balancer-labs/v3-interfaces/contracts/vault/IVault';
import { time } from '@nomicfoundation/hardhat-network-helpers';

describe('LBPool', function () {
  const POOL_SWAP_FEE = fp(0.01);

  const TOKEN_AMOUNT = fp(100);

  let permit2: IPermit2;
  let vault: IVaultMock;
  let factory: LBPoolFactory;
  let pool: LBPool;
  let router: Router;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let poolTokens: string[];

  let tokenAIdx: number;
  let tokenBIdx: number;

  let tokenAAddress: string;
  let tokenBAddress: string;

  const FACTORY_VERSION = 'LBPool Factory v1';
  const POOL_VERSION = 'LBPool v1';
  const ROUTER_VERSION = 'Router v11';

  const WEIGHTS = [fp(0.5), fp(0.5)];
  const INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT];
  const SWAP_AMOUNT = fp(20);

  const SWAP_FEE = fp(0.01);

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

    tokenAIdx = tokenAAddress < tokenBAddress ? 0 : 1;
    tokenBIdx = tokenAAddress < tokenBAddress ? 1 : 0;
  });

  sharedBeforeEach('create pool and grant approvals', async () => {
    factory = await deploy('LBPoolFactory', {
      args: [await vault.getAddress(), MONTH * 12, FACTORY_VERSION, POOL_VERSION, router],
    });
    poolTokens = sortAddresses([tokenAAddress, tokenBAddress]);

    const tokenConfig: TokenConfigStruct[] = buildTokenConfig(poolTokens);

    const tx = await factory.create(
      'LBPool',
      'Test',
      tokenConfig,
      WEIGHTS,
      SWAP_FEE,
      bob.address, // owner
      true, // swapEnabledOnStart
      ZERO_BYTES32
    );
    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    pool = (await deployedAt('LBPool', event.args.pool)) as unknown as LBPool;

    await tokenA.mint(bob, TOKEN_AMOUNT + SWAP_AMOUNT);
    await tokenB.mint(bob, TOKEN_AMOUNT);

    await pool.connect(bob).approve(router, MAX_UINT256);
    for (const token of [tokenA, tokenB]) {
      await token.connect(bob).approve(permit2, MAX_UINT256);
      await permit2.connect(bob).approve(token, router, MAX_UINT160, MAX_UINT48);
    }
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

  it('returns weights', async () => {
    const weights = await pool.getNormalizedWeights();
    expect(weights).to.be.deep.eq(WEIGHTS);
  });

  it('cannot be initialized by non-owners', async () => {
    await expect(
      router.connect(alice).initialize(pool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x')
    ).to.be.revertedWithCustomError(vault, 'BeforeInitializeHookFailed');
  });

  it('can be initialized by the owner', async () => {
    await expect(await router.connect(bob).initialize(pool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x'))
      .to.emit(vault, 'PoolInitialized')
      .withArgs(pool);
  });

  context('with initialized pool', () => {
    sharedBeforeEach(async () => {
      await router.connect(bob).initialize(pool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x');
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

    describe('Owner operations and events', () => {
      it('should emit SwapEnabledSet event when setSwapEnabled is called', async () => {
        await expect(pool.connect(bob).setSwapEnabled(false)).to.emit(pool, 'SwapEnabledSet').withArgs(false);

        await expect(pool.connect(bob).setSwapEnabled(true)).to.emit(pool, 'SwapEnabledSet').withArgs(true);
      });

      it('should emit GradualWeightUpdateScheduled event when updateWeightsGradually is called', async () => {
        const startTime = await time.latest();
        const endTime = startTime + MONTH;
        const endWeights = [fp(0.7), fp(0.3)];

        const tx = await pool.connect(bob).updateWeightsGradually(startTime, endTime, endWeights);
        const actualStartTime = await time.latest();

        await expect(tx)
          .to.emit(pool, 'GradualWeightUpdateScheduled')
          .withArgs(actualStartTime, endTime, WEIGHTS, endWeights);
      });

      it('should only allow owner to be the LP', async () => {
        const amounts: bigint[] = [FP_ZERO, FP_ZERO];
        amounts[tokenAIdx] = SWAP_AMOUNT;

        await expect(router.addLiquidityUnbalanced(pool, amounts, FP_ZERO, false, '0x')).to.be.revertedWithCustomError(
          vault,
          'BeforeAddLiquidityHookFailed'
        );

        await router.connect(bob).addLiquidityUnbalanced(pool, amounts, FP_ZERO, false, '0x');
      });

      it('should only allow owner to update weights', async () => {
        const startTime = await time.latest();
        const endTime = startTime + MONTH;
        const endWeights = [fp(0.7), fp(0.3)];

        await expect(
          pool.connect(alice).updateWeightsGradually(startTime, endTime, endWeights)
        ).to.be.revertedWithCustomError(pool, 'OwnableUnauthorizedAccount');

        await expect(pool.connect(bob).updateWeightsGradually(startTime, endTime, endWeights)).to.not.be.reverted;
      });
    });

    describe('Weight updates', () => {
      it('should update weights gradually', async () => {
        const startTime = await time.latest();
        const endTime = startTime + MONTH;
        const endWeights = [fp(0.7), fp(0.3)];

        await pool.connect(bob).updateWeightsGradually(startTime, endTime, endWeights);

        // Check weights at start
        expect(await pool.getNormalizedWeights()).to.deep.equal(WEIGHTS);

        // Check weights halfway through
        await time.increaseTo(startTime + MONTH / 2);
        const midWeights = await pool.getNormalizedWeights();
        expect(midWeights[0]).to.be.closeTo(fp(0.6), fp(1e-6));
        expect(midWeights[1]).to.be.closeTo(fp(0.4), fp(1e-6));

        // Check weights at end
        await time.increaseTo(endTime);
        expect(await pool.getNormalizedWeights()).to.deep.equal(endWeights);
      });

      it('should constrain weights to [1%, 99%]', async () => {
        const startTime = await time.latest();
        const endTime = startTime + MONTH;

        // Try to set weight below 1%
        await expect(
          pool.connect(bob).updateWeightsGradually(startTime, endTime, [fp(0.009), fp(0.991)])
        ).to.be.revertedWithCustomError(pool, 'MinWeight');

        // Try to set weight above 99%
        await expect(
          pool.connect(bob).updateWeightsGradually(startTime, endTime, [fp(0.991), fp(0.009)])
        ).to.be.revertedWithCustomError(pool, 'MinWeight');

        // Valid weight update
        await expect(pool.connect(bob).updateWeightsGradually(startTime, endTime, [fp(0.01), fp(0.99)])).to.not.be
          .reverted;
      });

      it('should not allow endTime before startTime', async () => {
        const startTime = await time.latest();
        const endTime = startTime - MONTH;

        // Try to set endTime before startTime
        await expect(
          pool.connect(bob).updateWeightsGradually(startTime, endTime, [fp(0.4), fp(0.6)])
        ).to.be.revertedWithCustomError(pool, 'GradualUpdateTimeTravel');

        // Valid time update
        await expect(pool.connect(bob).updateWeightsGradually(startTime, startTime + MONTH, [fp(0.01), fp(0.99)])).to
          .not.be.reverted;
      });

      it('should always sum weights to 1', async () => {
        const currentTime = await time.latest();
        const startTime = currentTime + MINUTE; // Set startTime 1 min in the future
        const endTime = startTime + MONTH;
        const startWeights = [fp(0.5), fp(0.5)];
        const endWeights = [fp(0.7), fp(0.3)];

        // Move time to just before startTime
        await time.increaseTo(startTime - 1);

        // Set weights to 50/50 instantaneously
        const tx1 = await pool.connect(bob).updateWeightsGradually(startTime, startTime, startWeights);
        await tx1.wait();

        // Schedule gradual shift to 70/30
        const tx2 = await pool.connect(bob).updateWeightsGradually(startTime, endTime, endWeights);
        await tx2.wait();

        // Check weights at various points during the transition
        for (let i = 0; i <= 100; i++) {
          const checkTime = startTime + (i * MONTH) / 100;

          // Only increase time if it's greater than the current time
          const currentBlockTime = await time.latest();
          if (checkTime > currentBlockTime) {
            await time.increaseTo(checkTime);
          }

          const weights = await pool.getNormalizedWeights();
          const sum = (BigInt(weights[0].toString()) + BigInt(weights[1].toString())).toString();

          // Assert exact equality
          expect(sum).to.equal(fp(1));
        }
      });
    });

    describe('Setters and Getters', () => {
      it('should set and get swap enabled status', async () => {
        await pool.connect(bob).setSwapEnabled(false);
        expect(await pool.getSwapEnabled()).to.be.false;

        await pool.connect(bob).setSwapEnabled(true);
        expect(await pool.getSwapEnabled()).to.be.true;
      });

      it('should get gradual weight update params', async () => {
        const startTime = await time.latest();
        const endTime = startTime + MONTH;
        const endWeights = [fp(0.7), fp(0.3)];

        const tx = await pool.connect(bob).updateWeightsGradually(startTime, endTime, endWeights);
        await tx.wait();
        const actualStartTime = await time.latest();

        const params = await pool.getGradualWeightUpdateParams();
        expect(params.startTime).to.equal(actualStartTime);
        expect(params.endTime).to.equal(endTime);
        expect(params.endWeights).to.deep.equal(endWeights);
      });
    });

    describe('Swap restrictions', () => {
      it('should allow swaps when enabled', async () => {
        await expect(
          router
            .connect(bob)
            .swapSingleTokenExactIn(
              pool,
              poolTokens[tokenAIdx],
              poolTokens[tokenBIdx],
              SWAP_AMOUNT,
              0,
              MAX_UINT256,
              false,
              '0x'
            )
        ).to.not.be.reverted;
      });

      it('should not allow swaps when disabled', async () => {
        await expect(await pool.connect(bob).setSwapEnabled(false))
          .to.emit(pool, 'SwapEnabledSet')
          .withArgs(false);

        await expect(
          router
            .connect(bob)
            .swapSingleTokenExactIn(
              pool,
              poolTokens[tokenAIdx],
              poolTokens[tokenBIdx],
              SWAP_AMOUNT,
              0,
              MAX_UINT256,
              false,
              '0x'
            )
        ).to.be.reverted;
      });
    });
  });
});
