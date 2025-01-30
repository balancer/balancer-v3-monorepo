import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48, ONES_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { LBPool, LBPoolFactory } from '../typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH, MINUTE, currentTimestamp, advanceToTimestamp, DAY } from '@balancer-labs/v3-helpers/src/time';
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
  // Most parameters are immutable so we'll need to deploy the pool several times during the test.
  // However, we will run liquidity tests on the global one to save unnecessary initialization steps every time.
  let globalPool: LBPool;
  let globalPoolStartTime: bigint;
  let globalPoolEndTime: bigint;

  let router: Router;
  let alice: SignerWithAddress, bob: SignerWithAddress, admin: SignerWithAddress;
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

  async function deployPool(
    startTime: bigint,
    endTime: bigint,
    startWeights: bigint[],
    endWeights: bigint[],
    projectToken: string,
    enableProjectTokenSwapsIn: boolean
  ): Promise<LBPool> {
    const tx = await deployPoolTx(
      startTime,
      endTime,
      startWeights,
      endWeights,
      projectToken,
      enableProjectTokenSwapsIn
    );

    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    return (await deployedAt('LBPool', event.args.pool)) as unknown as LBPool;
  }

  async function deployPoolTx(
    startTime: bigint,
    endTime: bigint,
    startWeights: bigint[],
    endWeights: bigint[],
    projectToken: string,
    enableProjectTokenSwapsIn: boolean
  ): Promise<ContractTransactionResponse> {
    const tokenConfig: TokenConfigStruct[] = buildTokenConfig(poolTokens);

    const lbpParams: LBPool.LBPParamsStruct = {
      owner: admin.address,
      startTime,
      endTime,
      startWeights,
      endWeights,
      projectToken,
      enableProjectTokenSwapsIn,
    };

    return factory.create('LBPool', 'Test', tokenConfig, SWAP_FEE, lbpParams, ONES_BYTES32);
  }

  before('setup signers', async () => {
    [, alice, bob, admin] = await ethers.getSigners();
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
      args: [await vault.getAddress(), bn(MONTH) * 12n, FACTORY_VERSION, POOL_VERSION, router],
    });
    poolTokens = sortAddresses([tokenAAddress, tokenBAddress]);

    // Leave a gap to test operations before start time.
    globalPoolStartTime = (await currentTimestamp()) + bn(MONTH);
    globalPoolEndTime = globalPoolStartTime + bn(MONTH);

    globalPool = await deployPool(globalPoolStartTime, globalPoolEndTime, WEIGHTS, WEIGHTS, tokenAAddress, true);

    for (const user of [alice, bob, admin]) {
      await tokenA.mint(user, TOKEN_AMOUNT + SWAP_AMOUNT);
      await tokenB.mint(user, TOKEN_AMOUNT);

      await globalPool.connect(user).approve(router, MAX_UINT256);
      for (const token of [tokenA, tokenB]) {
        await token.connect(user).approve(permit2, MAX_UINT256);
        await permit2.connect(user).approve(token, router, MAX_UINT160, MAX_UINT48);
      }
    }
  });

  sharedBeforeEach('grant permission', async () => {
    const setPoolSwapFeeAction = await actionId(vault, 'setStaticSwapFeePercentage');

    const authorizerAddress = await vault.getAuthorizer();
    const authorizer = await deployedAt('v3-vault/BasicAuthorizerMock', authorizerAddress);

    await authorizer.grantRole(setPoolSwapFeeAction, admin.address);

    await vault.connect(admin).setStaticSwapFeePercentage(globalPool, POOL_SWAP_FEE);
  });

  it('should have correct versions', async () => {
    expect(await factory.version()).to.eq(FACTORY_VERSION);
    expect(await factory.getPoolVersion()).to.eq(POOL_VERSION);
    expect(await globalPool.version()).to.eq(POOL_VERSION);
  });

  it('returns starting weights', async () => {
    const weights = await globalPool.getNormalizedWeights();
    expect(weights).to.be.deep.eq(WEIGHTS);
  });

  it('cannot be initialized by non-owners', async () => {
    await expect(
      router.connect(alice).initialize(globalPool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x')
    ).to.be.revertedWithCustomError(vault, 'BeforeInitializeHookFailed');
  });

  it('can be initialized by the owner', async () => {
    await expect(await router.connect(admin).initialize(globalPool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x'))
      .to.emit(vault, 'PoolInitialized')
      .withArgs(globalPool);
  });

  context('with initialized pool', () => {
    sharedBeforeEach(async () => {
      await router.connect(admin).initialize(globalPool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x');
    });

    it('pool and protocol fee preconditions', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(globalPool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await vault.getStaticSwapFeePercentage(globalPool)).to.eq(POOL_SWAP_FEE);
    });

    it('has the correct pool tokens and balances', async () => {
      const tokensFromPool = await globalPool.getTokens();
      expect(tokensFromPool).to.deep.equal(poolTokens);

      const [tokensFromVault, , balancesFromVault] = await vault.getPoolTokenInfo(globalPool);

      expect(tokensFromVault).to.deep.equal(tokensFromPool);
      expect(balancesFromVault).to.deep.equal(INITIAL_BALANCES);
    });

    it('cannot be initialized twice', async () => {
      await expect(router.connect(alice).initialize(globalPool, poolTokens, INITIAL_BALANCES, FP_ZERO, false, '0x'))
        .to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized')
        .withArgs(await globalPool.getAddress());
    });

    describe('Owner operations and events', () => {
      it('should emit GradualWeightUpdateScheduled event on deployment', async () => {
        const startTime = await currentTimestamp();
        const endTime = startTime + bn(bn(MONTH));
        const endWeights = [fp(0.7), fp(0.3)];

        const tx = await deployPoolTx(startTime, endTime, WEIGHTS, endWeights, tokenAAddress, true);
        const receipt = await tx.wait();
        const event = expectEvent.inReceipt(receipt, 'PoolCreated');

        const pool = (await deployedAt('LBPool', event.args.pool)) as unknown as LBPool;

        const actualStartTime = await currentTimestamp();

        await expect(tx)
          .to.emit(pool, 'GradualWeightUpdateScheduled')
          .withArgs(actualStartTime, endTime, WEIGHTS, endWeights);
      });

      it('should only allow owner to be the LP', async () => {
        await advanceToTimestamp(globalPoolStartTime - bn(MINUTE));

        const amounts: bigint[] = [FP_ZERO, FP_ZERO];
        amounts[tokenAIdx] = SWAP_AMOUNT;

        await expect(
          router.addLiquidityUnbalanced(globalPool, amounts, FP_ZERO, false, '0x')
        ).to.be.revertedWithCustomError(vault, 'BeforeAddLiquidityHookFailed');

        await router.connect(admin).addLiquidityUnbalanced(globalPool, amounts, FP_ZERO, false, '0x');
      });
    });

    describe('Weight update on deployment', () => {
      it('should update weights gradually', async () => {
        const startTime = await currentTimestamp();
        const endTime = startTime + bn(MONTH);
        const endWeights = [fp(0.7), fp(0.3)];

        const pool = await deployPool(startTime, endTime, WEIGHTS, endWeights, tokenAAddress, true);

        // Check weights at start
        expect(await pool.getNormalizedWeights()).to.deep.equal(WEIGHTS);

        // Check weights halfway through
        await advanceToTimestamp(startTime + bn(MONTH) / 2n);
        const midWeights = await pool.getNormalizedWeights();
        expect(midWeights[0]).to.be.closeTo(fp(0.6), fp(1e-6));
        expect(midWeights[1]).to.be.closeTo(fp(0.4), fp(1e-6));

        // Check weights at end
        await advanceToTimestamp(endTime);
        expect(await pool.getNormalizedWeights()).to.deep.equal(endWeights);
      });

      it('should constrain weights to [1%, 99%]', async () => {
        const startTime = await currentTimestamp();
        const endTime = startTime + bn(MONTH);

        // Try to set start weight below 1%
        await expect(
          deployPoolTx(startTime, endTime, [fp(0.009), fp(0.991)], WEIGHTS, tokenAAddress, true)
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Try to set start weight above 99%
        await expect(
          deployPoolTx(startTime, endTime, [fp(0.991), fp(0.009)], WEIGHTS, tokenAAddress, true)
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Try to set end weight below 1%
        await expect(
          deployPoolTx(startTime, endTime, WEIGHTS, [fp(0.009), fp(0.991)], tokenAAddress, true)
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Try to set end weight above 99%
        await expect(
          deployPoolTx(startTime, endTime, WEIGHTS, [fp(0.991), fp(0.009)], tokenAAddress, true)
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Valid weight update
        await expect(deployPoolTx(startTime, endTime, WEIGHTS, [fp(0.01), fp(0.99)], tokenAAddress, true)).to.not.be
          .reverted;
      });

      it('should not allow endTime before startTime', async () => {
        const startTime = await currentTimestamp();
        const endTime = startTime - bn(MONTH);

        // Try to set endTime before startTime
        await expect(
          deployPoolTx(startTime, endTime, WEIGHTS, [fp(0.4), fp(0.6)], tokenAAddress, true)
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Valid time update
        await expect(deployPoolTx(startTime, startTime + bn(MONTH), WEIGHTS, [fp(0.4), fp(0.6)], tokenAAddress, true))
          .to.not.be.reverted;
      });

      it('should always sum weights to 1', async () => {
        const currentTime = await currentTimestamp();
        const startTime = currentTime + bn(MINUTE); // Set startTime 1 min in the future
        const endTime = startTime + bn(MONTH);
        const startWeights = [fp(0.5), fp(0.5)];
        const endWeights = [fp(0.7), fp(0.3)];

        // Move time to just before startTime
        await advanceToTimestamp(startTime - 1n);

        // Start at 50/50, schedule gradual shift to 70/30
        const pool = await deployPool(startTime, endTime, startWeights, endWeights, tokenAAddress, true);

        // Check weights at various points during the transition
        for (let i = 0; i <= 100; i++) {
          const checkTime = startTime + (bn(i) * bn(MONTH)) / 100n;

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
      it('should get gradual weight update params', async () => {
        const startTime = await currentTimestamp();
        const endTime = startTime + bn(MONTH);
        const endWeights = [fp(0.7), fp(0.3)];

        const pool = await deployPool(startTime, endTime, WEIGHTS, endWeights, tokenAAddress, true);
        const actualStartTime = await currentTimestamp();

        const params = await pool.getGradualWeightUpdateParams();
        expect(params.startTime).to.equal(actualStartTime);
        expect(params.endTime).to.equal(endTime);
        expect(params.endWeights).to.deep.equal(endWeights);
      });
    });

    describe('Swap restrictions', () => {
      context('without project token restrictions', () => {
        it('should allow swaps after init time and before end time', async () => {
          await advanceToTimestamp((globalPoolStartTime + globalPoolEndTime) / 2n);

          await expect(
            router
              .connect(alice)
              .swapSingleTokenExactIn(
                globalPool,
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

        it('should not allow swaps before start time', async () => {
          await advanceToTimestamp(globalPoolStartTime - bn(MINUTE));

          await expect(
            router
              .connect(bob)
              .swapSingleTokenExactIn(
                globalPool,
                poolTokens[tokenAIdx],
                poolTokens[tokenBIdx],
                SWAP_AMOUNT,
                0,
                MAX_UINT256,
                false,
                '0x'
              )
          ).to.be.revertedWithCustomError(globalPool, 'SwapsDisabled');
        });

        it('should allow swaps after end time', async () => {
          await advanceToTimestamp(globalPoolEndTime + bn(DAY));

          await expect(
            router
              .connect(bob)
              .swapSingleTokenExactIn(
                globalPool,
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
      });
    });
  });
});
