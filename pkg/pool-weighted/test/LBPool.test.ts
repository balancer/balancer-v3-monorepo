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
import { LBPool, LBPoolFactory } from '../typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH, MINUTE, currentTimestamp, advanceToTimestamp, DAY } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { PoolConfigStructOutput } from '@balancer-labs/v3-solidity-utils/typechain-types/@balancer-labs/v3-interfaces/contracts/vault/IVault';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { LBPParamsStruct } from '../typechain-types/contracts/lbp/LBPool';

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
  let projectToken: ERC20TestToken;
  let reserveToken: ERC20TestToken;
  const poolTokens: string[] = [];

  let projectTokenIdx: number;
  let reserveTokenIdx: number;

  let projectTokenAddress: string;
  let reserveTokenAddress: string;

  let startWeights: bigint[] = [];
  let endWeights: bigint[] = [];

  const FACTORY_VERSION = 'LBPool Factory v1';
  const POOL_VERSION = 'LBPool v1';
  const ROUTER_VERSION = 'Router v11';

  const HIGH_WEIGHT = fp(0.9);
  const LOW_WEIGHT = fp(0.1);

  const INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT];
  const SWAP_AMOUNT = fp(20);

  const SWAP_FEE = fp(0.01);

  async function deployPool(
    startTime: bigint,
    endTime: bigint,
    startWeights: bigint[],
    endWeights: bigint[],
    projectToken: string,
    reserveToken: string,
    enableProjectTokenSwapsIn: boolean
  ): Promise<LBPool> {
    const tx = await deployPoolTx(
      startTime,
      endTime,
      projectToken,
      reserveToken,
      startWeights,
      endWeights,
      enableProjectTokenSwapsIn
    );

    const receipt = await tx.wait();
    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    return (await deployedAt('LBPool', event.args.pool)) as unknown as LBPool;
  }

  async function deployPoolTx(
    startTime: bigint,
    endTime: bigint,
    projectToken: string,
    reserveToken: string,
    startWeights: bigint[],
    endWeights: bigint[],
    enableProjectTokenSwapsIn: boolean
  ): Promise<ContractTransactionResponse> {
    const lbpParams: LBPParamsStruct = {
      owner: admin.address,
      projectToken: projectToken,
      reserveToken: reserveToken,
      projectTokenStartWeight: startWeights[projectTokenIdx],
      reserveTokenStartWeight: startWeights[reserveTokenIdx],
      projectTokenEndWeight: endWeights[projectTokenIdx],
      reserveTokenEndWeight: endWeights[reserveTokenIdx],
      startTime: startTime,
      endTime: endTime,
      enableProjectTokenSwapsIn: enableProjectTokenSwapsIn,
    };

    return factory.createAndInitialize('LBPool', 'Test', lbpParams, SWAP_FEE, INITIAL_BALANCES, ONES_BYTES32);
  }

  before('setup signers', async () => {
    [, alice, bob, admin] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    vault = await TypesConverter.toIVaultMock(await VaultDeployer.deployMock());

    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await deploy('v3-vault/Router', { args: [vault, WETH, permit2, ROUTER_VERSION] });

    projectToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Project', 'PRJ', 18] });
    reserveToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Reserve', 'RES', 6] });

    projectTokenAddress = await projectToken.getAddress();
    reserveTokenAddress = await reserveToken.getAddress();

    projectTokenIdx = projectTokenAddress < reserveTokenAddress ? 0 : 1;
    reserveTokenIdx = projectTokenAddress < reserveTokenAddress ? 1 : 0;

    poolTokens[projectTokenIdx] = projectTokenAddress;
    poolTokens[reserveTokenIdx] = reserveTokenAddress;
  });

  sharedBeforeEach('create pool and grant approvals', async () => {
    factory = await deploy('LBPoolFactory', {
      args: [await vault.getAddress(), bn(MONTH) * 12n, FACTORY_VERSION, POOL_VERSION, router, permit2],
    });

    // Leave a gap to test operations before start time.
    globalPoolStartTime = (await currentTimestamp()) + bn(MONTH);
    globalPoolEndTime = globalPoolStartTime + bn(MONTH);

    startWeights[projectTokenIdx] = HIGH_WEIGHT;
    startWeights[reserveTokenIdx] = LOW_WEIGHT;

    startWeights[projectTokenIdx] = LOW_WEIGHT;
    startWeights[reserveTokenIdx] = HIGH_WEIGHT;

    globalPool = await deployPool(
      globalPoolStartTime,
      globalPoolEndTime,
      startWeights,
      endWeights,
      projectTokenAddress,
      reserveTokenAddress,
      true
    );

    for (const user of [alice, bob, admin]) {
      await projectToken.mint(user, TOKEN_AMOUNT + SWAP_AMOUNT);
      await reserveToken.mint(user, TOKEN_AMOUNT);

      await globalPool.connect(user).approve(router, MAX_UINT256);
      for (const token of [projectToken, reserveToken]) {
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
    expect(weights).to.be.deep.eq(startWeights);
  });

  context('with initialized pool', () => {
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

        const tx = await deployPoolTx(
          startTime,
          endTime,
          startWeights,
          endWeights,
          projectTokenAddress,
          reserveTokenAddress,
          true
        );
        const receipt = await tx.wait();
        const event = expectEvent.inReceipt(receipt, 'PoolCreated');

        const pool = (await deployedAt('LBPool', event.args.pool)) as unknown as LBPool;

        const actualStartTime = await currentTimestamp();

        await expect(tx)
          .to.emit(pool, 'GradualWeightUpdateScheduled')
          .withArgs(actualStartTime, endTime, startWeights, endWeights);
      });

      it('should only allow owner to be the LP', async () => {
        await advanceToTimestamp(globalPoolStartTime - bn(MINUTE));

        const amounts: bigint[] = [FP_ZERO, FP_ZERO];
        amounts[projectTokenIdx] = SWAP_AMOUNT;

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

        const pool = await deployPool(
          startTime,
          endTime,
          startWeights,
          endWeights,
          projectTokenAddress,
          reserveTokenAddress,
          true
        );

        // Check weights at start
        expect(await pool.getNormalizedWeights()).to.deep.equal(startWeights);

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
          deployPoolTx(
            startTime,
            endTime,
            [fp(0.009), fp(0.991)],
            endWeights,
            projectTokenAddress,
            reserveTokenAddress,
            true
          )
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Try to set start weight above 99%
        await expect(
          deployPoolTx(
            startTime,
            endTime,
            [fp(0.991), fp(0.009)],
            endWeights,
            projectTokenAddress,
            reserveTokenAddress,
            true
          )
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Try to set end weight below 1%
        await expect(
          deployPoolTx(
            startTime,
            endTime,
            startWeights,
            [fp(0.009), fp(0.991)],
            projectTokenAddress,
            reserveTokenAddress,
            true
          )
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Try to set end weight above 99%
        await expect(
          deployPoolTx(
            startTime,
            endTime,
            startWeights,
            [fp(0.991), fp(0.009)],
            projectTokenAddress,
            reserveTokenAddress,
            true
          )
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Valid weight update
        await expect(
          deployPoolTx(
            startTime,
            endTime,
            startWeights,
            [fp(0.01), fp(0.99)],
            projectTokenAddress,
            reserveTokenAddress,
            true
          )
        ).to.not.be.reverted;
      });

      it('should not allow endTime before startTime', async () => {
        const startTime = await currentTimestamp();
        const endTime = startTime - bn(MONTH);

        // Try to set endTime before startTime
        await expect(
          deployPoolTx(
            startTime,
            endTime,
            startWeights,
            [fp(0.4), fp(0.6)],
            projectTokenAddress,
            reserveTokenAddress,
            true
          )
        ).to.be.revertedWithCustomError(factory, 'Create2FailedDeployment');

        // Valid time update
        await expect(
          deployPoolTx(
            startTime,
            startTime + bn(MONTH),
            startWeights,
            [fp(0.4), fp(0.6)],
            projectTokenAddress,
            reserveTokenAddress,
            true
          )
        ).to.not.be.reverted;
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
        const pool = await deployPool(
          startTime,
          endTime,
          startWeights,
          endWeights,
          projectTokenAddress,
          reserveTokenAddress,
          true
        );

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

        const pool = await deployPool(
          startTime,
          endTime,
          startWeights,
          endWeights,
          projectTokenAddress,
          reserveTokenAddress,
          true
        );
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
                poolTokens[projectTokenIdx],
                poolTokens[reserveTokenIdx],
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
                poolTokens[projectTokenIdx],
                poolTokens[reserveTokenIdx],
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
                poolTokens[projectTokenIdx],
                poolTokens[reserveTokenIdx],
                SWAP_AMOUNT,
                0,
                MAX_UINT256,
                false,
                '0x'
              )
          ).to.be.revertedWithCustomError(globalPool, 'SwapsDisabled');
        });
      });
    });
  });
});
