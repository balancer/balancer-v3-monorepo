/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { saveSnap } from '@balancer-labs/v3-helpers/src/gas';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp, bn } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { PoolConfigStructOutput } from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { BatchRouter, IVault, ProtocolFeeController } from '@balancer-labs/v3-vault/typechain-types';
import { WeightedPoolFactory } from '@balancer-labs/v3-pool-weighted/typechain-types';
import {
  ERC20WithRateTestToken,
  ERC4626TestToken,
  WETHTestToken,
} from '@balancer-labs/v3-solidity-utils/typechain-types';
import { BaseContract } from 'ethers';
import { IERC20 } from '@balancer-labs/v3-interfaces/typechain-types';

export enum PoolType {
  Standard = 'Standard',
  ERC4626 = 'ERC4626',
  Nested = 'Nested',
}

export type PoolInfo = {
  tag: PoolType;
  pool: BaseContract;
  poolTokens: string[];
};

export class Benchmark {
  _testDirname: string;
  _poolType: string;
  vault!: IVault;
  tokenA!: ERC20WithRateTestToken;
  tokenB!: ERC20WithRateTestToken;
  tokenC!: ERC20WithRateTestToken;
  wTokenA!: ERC4626TestToken;
  wTokenB!: ERC4626TestToken;
  WETH!: WETHTestToken;
  factory!: WeightedPoolFactory;

  constructor(dirname: string, poolType: string) {
    this._testDirname = dirname;
    this._poolType = poolType;
  }

  async deployPool(tag: PoolType, poolTokens: string[], withRate: boolean): Promise<PoolInfo | null> {
    return null;
  }

  itBenchmarks = () => {
    const BATCH_ROUTER_VERSION = 'BatchRouter v9';
    const ROUTER_VERSION = 'Router v9';

    const MAX_PROTOCOL_SWAP_FEE = fp(0.5);
    const MAX_PROTOCOL_YIELD_FEE = fp(0.2);

    const TOKEN_AMOUNT = fp(100);
    const BUFFER_INITIALIZE_AMOUNT = bn(1e4);

    const SWAP_AMOUNT = fp(20);
    const SWAP_FEE = fp(0.01);

    let permit2: IPermit2;
    let feeCollector: ProtocolFeeController;
    let router: Router;
    let batchRouter: BatchRouter;
    let alice: SignerWithAddress;
    let admin: SignerWithAddress;

    let tokenAAddress: string;
    let tokenBAddress: string;
    let tokenCAddress: string;
    let wTokenAAddress: string;
    let wTokenBAddress: string;
    let wethAddress: string;

    before('setup signers', async () => {
      [, alice, admin] = await ethers.getSigners();
    });

    sharedBeforeEach('deploy vault, router, tokens', async () => {
      this.vault = await TypesConverter.toIVault(await VaultDeployer.deploy());
      feeCollector = (await deployedAt(
        'v3-vault/ProtocolFeeController',
        await this.vault.getProtocolFeeController()
      )) as unknown as ProtocolFeeController;
      this.WETH = await deploy('v3-solidity-utils/WETHTestToken');
      permit2 = await deployPermit2();
      router = await deploy('v3-vault/Router', { args: [this.vault, this.WETH, permit2, ROUTER_VERSION] });
      batchRouter = await deploy('v3-vault/BatchRouter', {
        args: [this.vault, this.WETH, permit2, BATCH_ROUTER_VERSION],
      });
      this.tokenA = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token A', 'TKNA', 18] });
      this.tokenB = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token B', 'TKNB', 18] });
      this.tokenC = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token C', 'TKNC', 18] });

      tokenAAddress = await this.tokenA.getAddress();
      tokenBAddress = await this.tokenB.getAddress();
      tokenCAddress = await this.tokenC.getAddress();
      wethAddress = await this.WETH.getAddress();

      this.wTokenA = await deploy('v3-solidity-utils/ERC4626TestToken', {
        args: [tokenAAddress, 'wTokenA', 'wTokenA', 18],
      });
      this.wTokenB = await deploy('v3-solidity-utils/ERC4626TestToken', {
        args: [tokenBAddress, 'wTokenB', 'wTokenB', 18],
      });
      wTokenAAddress = await this.wTokenA.getAddress();
      wTokenBAddress = await this.wTokenB.getAddress();
    });

    sharedBeforeEach('protocol fees configuration', async () => {
      const setSwapFeeAction = await actionId(feeCollector, 'setGlobalProtocolSwapFeePercentage');
      const setYieldFeeAction = await actionId(feeCollector, 'setGlobalProtocolYieldFeePercentage');
      const authorizerAddress = await this.vault.getAuthorizer();
      const authorizer = await deployedAt('v3-vault/BasicAuthorizerMock', authorizerAddress);

      await authorizer.grantRole(setSwapFeeAction, admin.address);
      await authorizer.grantRole(setYieldFeeAction, admin.address);

      await feeCollector.connect(admin).setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
      await feeCollector.connect(admin).setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
    });

    sharedBeforeEach('token setup', async () => {
      await this.tokenA.mint(alice, TOKEN_AMOUNT * 20n);
      await this.tokenB.mint(alice, TOKEN_AMOUNT * 20n);
      await this.tokenC.mint(alice, TOKEN_AMOUNT * 20n);
      await this.WETH.connect(alice).deposit({ value: TOKEN_AMOUNT });

      for (const token of [this.tokenA, this.tokenB, this.tokenC, this.WETH, this.wTokenA, this.wTokenB]) {
        await token.connect(alice).approve(permit2, MAX_UINT256);
        await permit2.connect(alice).approve(token, router, MAX_UINT160, MAX_UINT48);
        await permit2.connect(alice).approve(token, batchRouter, MAX_UINT160, MAX_UINT48);
      }

      for (const token of [this.wTokenA, this.wTokenB]) {
        const underlying = (await deployedAt(
          'v3-solidity-utils/ERC20WithRateTestToken',
          await token.asset()
        )) as unknown as ERC20WithRateTestToken;
        await underlying.connect(alice).approve(await token.getAddress(), TOKEN_AMOUNT * 10n);
        await token.connect(alice).deposit(TOKEN_AMOUNT * 10n, await alice.getAddress());
      }
    });

    const itTestsInitialize = async (
      useEth: boolean,
      poolTag: PoolType,
      poolTokens: string[],
      withRate: boolean
    ): Promise<void> => {
      const ethStatus = useEth ? 'with ETH' : 'without ETH';

      let poolInfo: PoolInfo;
      beforeEach(`deploy pool (${poolTag})`, async () => {
        poolInfo = (await this.deployPool(poolTag, poolTokens, withRate))!;
      });

      it(`measures initialization gas ${ethStatus} (${poolTag})`, async () => {
        const initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);

        // Measure gas on initialization.
        const value = useEth ? TOKEN_AMOUNT : 0;
        const tx = await router
          .connect(alice)
          .initialize(poolInfo.pool, poolTokens, initialBalances, FP_ZERO, useEth, '0x', { value });

        const receipt = await tx.wait();

        await saveSnap(this._testDirname, `[${this._poolType} - ${poolTag}] initialize ${ethStatus}`, receipt);
      });
    };

    const itTestsSwap = (gasTag: string, poolInfo: PoolInfo, actionAfterFirstTx: () => Promise<void>) => {
      it(`pool and protocol fee preconditions (${poolInfo.tag})`, async () => {
        console.log('poolInfo.pool', poolInfo.pool);
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(poolInfo.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;

        expect(await this.vault.getStaticSwapFeePercentage(poolInfo.pool)).to.eq(SWAP_FEE);
      });

      it(`measures gas (Router) (${poolInfo.tag})`, async () => {
        // Warm up.
        let tx = await router
          .connect(alice)
          .swapSingleTokenExactIn(
            poolInfo.pool,
            poolInfo.poolTokens[0],
            poolInfo.poolTokens[1],
            SWAP_AMOUNT,
            0,
            MAX_UINT256,
            false,
            '0x'
          );

        let receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] swap single token exact in with fees - cold slots`,
          receipt
        );

        await actionAfterFirstTx();

        // Measure gas for the swap.
        tx = await router
          .connect(alice)
          .swapSingleTokenExactIn(
            poolInfo.pool,
            poolInfo.poolTokens[0],
            poolInfo.poolTokens[1],
            SWAP_AMOUNT,
            0,
            MAX_UINT256,
            false,
            '0x'
          );
        receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] swap single token exact in with fees - warm slots`,
          receipt
        );
      });

      it(`measures gas (BatchRouter) (${poolInfo.tag})`, async () => {
        // Warm up.
        let tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: poolInfo.poolTokens[0],
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.poolTokens[1],
                  isBuffer: false,
                },
              ],
              exactAmountIn: SWAP_AMOUNT,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );
        let receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag} - BatchRouter] swap exact in with one token and fees - cold slots`,
          receipt
        );

        await actionAfterFirstTx();

        // Measure gas for the swap.
        tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: poolInfo.poolTokens[0],
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.poolTokens[1],
                  isBuffer: false,
                },
              ],
              exactAmountIn: SWAP_AMOUNT,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag} - BatchRouter] swap exact in with one token and fees - warm slots`,
          receipt
        );
      });
    };

    const itTestsDonation = (poolTag: PoolType, poolTokens: string[], withRate: boolean) => {
      let poolInfo: PoolInfo;
      sharedBeforeEach(`deploy pool (${poolTag})`, async () => {
        poolInfo = (await this.deployPool(poolTag, poolTokens, withRate))!;
      });

      sharedBeforeEach(`initialize pool (${poolTag})`, async () => {
        const initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
        await router.connect(alice).initialize(poolInfo.pool, poolTokens, initialBalances, FP_ZERO, false, '0x');
      });

      it(`pool preconditions (${poolTag})`, async () => {
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(poolInfo.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;
        expect(poolConfig.liquidityManagement.enableDonation).to.be.true;
      });

      it(`measures gas (${poolTag})`, async () => {
        // Warm up.
        const tx = await router.connect(alice).donate(poolInfo.pool, [SWAP_AMOUNT, SWAP_AMOUNT], false, '0x');
        const receipt = await tx.wait();
        await saveSnap(this._testDirname, `[${this._poolType} - ${poolTag}] donation`, receipt);
      });
    };

    const itTestsRemoveLiquidity = (gasTag: string, poolInfo: PoolInfo, actionAfterFirstTx: () => Promise<void>) => {
      sharedBeforeEach(`approve router to spend BPT (${poolInfo.tag})`, async () => {
        const bpt: IERC20 = await TypesConverter.toIERC20(poolInfo.pool);
        await bpt.connect(alice).approve(router, MAX_UINT256);
        await bpt.connect(alice).approve(permit2, MAX_UINT256);
        await permit2.connect(alice).approve(bpt, batchRouter, MAX_UINT160, MAX_UINT48);
      });

      it(`pool and protocol fee preconditions (${poolInfo.tag})`, async () => {
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(poolInfo.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;

        expect(await this.vault.getStaticSwapFeePercentage(poolInfo.pool)).to.eq(SWAP_FEE);
      });

      it(`measures gas (proportional) (${poolInfo.tag})`, async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);
        const tx = await router
          .connect(alice)
          .removeLiquidityProportional(
            poolInfo.pool,
            bptBalance / 2n,
            Array(poolInfo.poolTokens.length).fill(0n),
            false,
            '0x'
          );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] remove liquidity proportional`,
          receipt
        );
      });

      it(`measures gas (single token exact in) (${poolInfo.tag})`, async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);
        // Warm up.
        await router
          .connect(alice)
          .removeLiquiditySingleTokenExactIn(poolInfo.pool, bptBalance / 10n, poolInfo.poolTokens[0], 1, false, '0x');

        await actionAfterFirstTx();

        // Measure remove liquidity gas.
        const tx = await router
          .connect(alice)
          .removeLiquiditySingleTokenExactIn(poolInfo.pool, bptBalance / 10n, poolInfo.poolTokens[0], 1, false, '0x');
        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] remove liquidity single token exact in - warm slots`,
          receipt
        );
      });

      it(`measures gas (single token exact in - BatchRouter) (${poolInfo.tag})`, async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);
        // Warm up.
        let tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: poolInfo.pool,
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.poolTokens[0],
                  isBuffer: false,
                },
              ],
              exactAmountIn: bptBalance / 10n,
              minAmountOut: 1,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        await actionAfterFirstTx();

        // Measure gas for the swap.
        tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: poolInfo.pool,
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.poolTokens[0],
                  isBuffer: false,
                },
              ],
              exactAmountIn: bptBalance / 10n,
              minAmountOut: 1,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag} - BatchRouter] remove liquidity using swapExactIn - warm slots`,
          receipt
        );
      });

      it(`measures gas (single token exact out) (${poolInfo.tag})`, async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);
        // Warm up.
        await router
          .connect(alice)
          .removeLiquiditySingleTokenExactOut(
            poolInfo.pool,
            bptBalance / 2n,
            poolInfo.poolTokens[0],
            TOKEN_AMOUNT / 1000n,
            false,
            '0x'
          );

        await actionAfterFirstTx();

        // Measure remove liquidity gas.
        const tx = await router
          .connect(alice)
          .removeLiquiditySingleTokenExactOut(
            poolInfo.pool,
            bptBalance / 2n,
            poolInfo.poolTokens[0],
            TOKEN_AMOUNT / 1000n,
            false,
            '0x'
          );
        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] remove liquidity single token exact out - warm slots`,
          receipt
        );
      });

      it(`measures gas (single token exact out - BatchRouter) (${poolInfo.tag})`, async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);
        // Warm up.
        let tx = await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: poolInfo.pool,
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.poolTokens[0],
                  isBuffer: false,
                },
              ],
              exactAmountOut: TOKEN_AMOUNT / 1000n,
              maxAmountIn: bptBalance / 2n,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        await actionAfterFirstTx();

        // Measure gas for the swap.
        tx = await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: poolInfo.pool,
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.poolTokens[0],
                  isBuffer: false,
                },
              ],
              exactAmountOut: TOKEN_AMOUNT / 1000n,
              maxAmountIn: bptBalance / 2n,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag} - BatchRouter] remove liquidity using swapExactOut - warm slots`,
          receipt
        );
      });
    };

    const itTestsAddLiquidity = (gasTag: string, poolInfo: PoolInfo, actionAfterFirstTx: () => Promise<void>) => {
      it(`pool and protocol fee preconditions (${poolInfo.tag})`, async () => {
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(poolInfo.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;

        expect(await this.vault.getStaticSwapFeePercentage(poolInfo.pool)).to.eq(SWAP_FEE);
      });

      it('measures gas (proportional)', async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);
        const tx = await router
          .connect(alice)
          .addLiquidityProportional(
            poolInfo.pool,
            Array(poolInfo.poolTokens.length).fill(TOKEN_AMOUNT),
            bptBalance,
            false,
            '0x'
          );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] add liquidity proportional`,
          receipt
        );
      });

      it(`åmeasures gas (unbalanced) (${poolInfo.tag})`, async () => {
        const exactAmountsIn = Array(poolInfo.poolTokens.length)
          .fill(TOKEN_AMOUNT)
          .map((amount, index) => BigInt(amount / BigInt(index + 1)));

        // Warm up.
        await router.connect(alice).addLiquidityUnbalanced(poolInfo.pool, exactAmountsIn, 0, false, '0x');

        await actionAfterFirstTx();

        // Measure add liquidity gas.
        const tx = await router.connect(alice).addLiquidityUnbalanced(poolInfo.pool, exactAmountsIn, 0, false, '0x');
        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] add liquidity unbalanced - warm slots`,
          receipt
        );
      });

      it(`measures gas (unbalanced - BatchRouter) (${poolInfo.tag})`, async () => {
        // Warm up.
        let tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: poolInfo.poolTokens[0],
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.pool,
                  isBuffer: false,
                },
              ],
              exactAmountIn: TOKEN_AMOUNT,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        await actionAfterFirstTx();

        // Measure gas for the swap.
        tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: poolInfo.poolTokens[0],
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.pool,
                  isBuffer: false,
                },
              ],
              exactAmountIn: TOKEN_AMOUNT,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag} - BatchRouter] add liquidity unbalanced using swapExactIn - warm slots`,
          receipt
        );
      });

      it(`measures gas (single token exact out) (${poolInfo.tag})`, async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);

        // Warm up.
        await router
          .connect(alice)
          .addLiquiditySingleTokenExactOut(
            poolInfo.pool,
            poolInfo.poolTokens[0],
            TOKEN_AMOUNT,
            bptBalance / 1000n,
            false,
            '0x'
          );

        await actionAfterFirstTx();

        // Measure add liquidity gas.
        const tx = await router
          .connect(alice)
          .addLiquiditySingleTokenExactOut(
            poolInfo.pool,
            poolInfo.poolTokens[0],
            TOKEN_AMOUNT,
            bptBalance / 1000n,
            false,
            '0x'
          );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag}] add liquidity single token exact out - warm slots`,
          receipt
        );
      });

      it(`measures gas (single token exact out - BatchRouter) (${poolInfo.tag})`, async () => {
        const bptBalance = await this.vault.balanceOf(poolInfo.pool, alice);

        // Warm up.
        let tx = await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: poolInfo.poolTokens[0],
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.pool,
                  isBuffer: false,
                },
              ],
              exactAmountOut: bptBalance / 1000n,
              maxAmountIn: TOKEN_AMOUNT,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        await actionAfterFirstTx();

        // Measure gas for the swap.
        tx = await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: poolInfo.poolTokens[0],
              steps: [
                {
                  pool: poolInfo.pool,
                  tokenOut: poolInfo.pool,
                  isBuffer: false,
                },
              ],
              exactAmountOut: bptBalance / 1000n,
              maxAmountIn: TOKEN_AMOUNT,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag} - ${poolInfo.tag} - BatchRouter] add liquidity using swapExactOur - warm slots`,
          receipt
        );
      });
    };

    const setStaticSwapFeePercentage = async (pool: BaseContract, swapFee: bigint) => {
      const setPoolSwapFeeAction = await actionId(this.vault, 'setStaticSwapFeePercentage');
      const authorizerAddress = await this.vault.getAuthorizer();
      const authorizer = await deployedAt('v3-vault/BasicAuthorizerMock', authorizerAddress);
      await authorizer.grantRole(setPoolSwapFeeAction, admin.address);
      await this.vault.connect(admin).setStaticSwapFeePercentage(pool, swapFee);
    };

    const deployAndInitializePool = async (
      tag: PoolType,
      poolTokens: string[],
      withRate: boolean
    ): Promise<PoolInfo> => {
      const poolInfo: PoolInfo = (await this.deployPool(tag, poolTokens, withRate))!;

      await setStaticSwapFeePercentage(poolInfo.pool, SWAP_FEE);

      const initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
      await router.connect(alice).initialize(poolInfo.pool, poolTokens, initialBalances, FP_ZERO, false, '0x');

      return poolInfo;
    };

    describe('test standard pool', async () => {
      let poolInfo: PoolInfo;
      sharedBeforeEach('deploy and initialize pool', async () => {
        poolInfo = await deployAndInitializePool(
          PoolType.Standard,
          sortAddresses([tokenAAddress, tokenBAddress]),
          false
        );
      });

      context('swap', () => {
        itTestsSwap('Standard', poolInfo, async () => {
          return;
        });
      });

      context('remove liquidity', () => {
        itTestsRemoveLiquidity('Standard', poolInfo, async () => {
          return;
        });
      });

      context('add liquidity', () => {
        itTestsAddLiquidity('Standard', poolInfo, async () => {
          return;
        });
      });
    });

    describe('initialization', () => {
      it('without ETH', async () => {
        await itTestsInitialize(false, PoolType.Standard, sortAddresses([tokenAAddress, wethAddress]), false);
      });

      it('with ETH', async () => {
        await itTestsInitialize(true, PoolType.Standard, sortAddresses([tokenAAddress, wethAddress]), false);
      });
    });

    describe('test yield pool', async () => {
      let poolInfo: PoolInfo;
      sharedBeforeEach(async () => {
        poolInfo = await deployAndInitializePool(
          PoolType.Standard,
          sortAddresses([tokenAAddress, tokenBAddress]),
          false
        );
        await this.tokenA.setRate(fp(1.1));
        await this.tokenB.setRate(fp(1.1));
      });

      context('swap', () => {
        itTestsSwap('With rate', poolInfo, async () => {
          await this.tokenA.setRate(fp(1.2));
          await this.tokenB.setRate(fp(1.2));
        });
      });

      context('remove liquidity', async () => {
        itTestsRemoveLiquidity('With rate', poolInfo, async () => {
          await this.tokenA.setRate(fp(1.2));
          await this.tokenB.setRate(fp(1.2));
        });
      });

      context('add liquidity', async () => {
        itTestsAddLiquidity('With rate', poolInfo, async () => {
          await this.tokenA.setRate(fp(1.2));
          await this.tokenB.setRate(fp(1.2));
        });
      });
    });

    describe('test donation', () => {
      it('standard pool', async () => {
        await itTestsDonation(PoolType.Standard, sortAddresses([tokenAAddress, tokenBAddress]), false);
      });
    });

    describe('test ERC4626 pool', async () => {
      let poolInfo: PoolInfo;

      const amountToTrade = TOKEN_AMOUNT / 10n;

      sharedBeforeEach('Deploy and Initialize pool', async () => {
        poolInfo = await deployAndInitializePool(
          PoolType.ERC4626,
          sortAddresses([wTokenAAddress, wTokenBAddress]),
          true
        );
        await this.wTokenA.mockRate(fp(1.1));
        await this.wTokenB.mockRate(fp(1.1));
      });

      sharedBeforeEach('Initialize buffers', async () => {
        await router
          .connect(alice)
          .initializeBuffer(wTokenAAddress, BUFFER_INITIALIZE_AMOUNT, BUFFER_INITIALIZE_AMOUNT);
        await router
          .connect(alice)
          .initializeBuffer(wTokenBAddress, BUFFER_INITIALIZE_AMOUNT, BUFFER_INITIALIZE_AMOUNT);
      });

      it('measures gas (buffers without liquidity exact in - BatchRouter)', async () => {
        // Warm up.
        await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: tokenAAddress,
              steps: [
                {
                  pool: wTokenAAddress,
                  tokenOut: wTokenAAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenBAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenBAddress,
                  tokenOut: tokenBAddress,
                  isBuffer: true,
                },
              ],
              exactAmountIn: amountToTrade,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        // Measure gas for the swap.
        const tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: tokenBAddress,
              steps: [
                {
                  pool: wTokenBAddress,
                  tokenOut: wTokenBAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenAAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenAAddress,
                  tokenOut: tokenAAddress,
                  isBuffer: true,
                },
              ],
              exactAmountIn: amountToTrade,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ERC4626 - BatchRouter] swapExactIn - no buffer liquidity - warm slots`,
          receipt
        );
      });

      it('measures gas (buffers without liquidity exact out - BatchRouter)', async () => {
        // Warm up.
        await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: tokenAAddress,
              steps: [
                {
                  pool: wTokenAAddress,
                  tokenOut: wTokenAAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenBAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenBAddress,
                  tokenOut: tokenBAddress,
                  isBuffer: true,
                },
              ],
              exactAmountOut: amountToTrade,
              maxAmountIn: TOKEN_AMOUNT,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        // Measure gas for the swap.
        const tx = await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: tokenBAddress,
              steps: [
                {
                  pool: wTokenBAddress,
                  tokenOut: wTokenBAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenAAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenAAddress,
                  tokenOut: tokenAAddress,
                  isBuffer: true,
                },
              ],
              exactAmountOut: amountToTrade,
              maxAmountIn: TOKEN_AMOUNT,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ERC4626 - BatchRouter] swapExactOut - no buffer liquidity - warm slots`,
          receipt
        );
      });

      it('measures gas (buffers with liquidity exact in - BatchRouter)', async () => {
        // Add liquidity to buffers.
        await router.connect(alice).addLiquidityToBuffer(wTokenAAddress, 2n * TOKEN_AMOUNT);
        await router.connect(alice).addLiquidityToBuffer(wTokenBAddress, 2n * TOKEN_AMOUNT);

        // Warm up.
        await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: tokenAAddress,
              steps: [
                {
                  pool: wTokenAAddress,
                  tokenOut: wTokenAAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenBAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenBAddress,
                  tokenOut: tokenBAddress,
                  isBuffer: true,
                },
              ],
              exactAmountIn: amountToTrade,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        // Measure gas for the swap.
        const tx = await batchRouter.connect(alice).swapExactIn(
          [
            {
              tokenIn: tokenBAddress,
              steps: [
                {
                  pool: wTokenBAddress,
                  tokenOut: wTokenBAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenAAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenAAddress,
                  tokenOut: tokenAAddress,
                  isBuffer: true,
                },
              ],
              exactAmountIn: amountToTrade,
              minAmountOut: 0,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ERC4626 - BatchRouter] swapExactIn - with buffer liquidity - warm slots`,
          receipt
        );
      });

      it('measures gas (buffers with liquidity exact out - BatchRouter)', async () => {
        // Add liquidity to buffers.
        await router.connect(alice).addLiquidityToBuffer(wTokenAAddress, 2n * TOKEN_AMOUNT);
        await router.connect(alice).addLiquidityToBuffer(wTokenBAddress, 2n * TOKEN_AMOUNT);

        // Warm up.
        await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: tokenAAddress,
              steps: [
                {
                  pool: wTokenAAddress,
                  tokenOut: wTokenAAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenBAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenBAddress,
                  tokenOut: tokenBAddress,
                  isBuffer: true,
                },
              ],
              exactAmountOut: amountToTrade,
              maxAmountIn: TOKEN_AMOUNT,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        // Measure gas for the swap.
        const tx = await batchRouter.connect(alice).swapExactOut(
          [
            {
              tokenIn: tokenBAddress,
              steps: [
                {
                  pool: wTokenBAddress,
                  tokenOut: wTokenBAddress,
                  isBuffer: true,
                },
                {
                  pool: poolInfo.pool,
                  tokenOut: wTokenAAddress,
                  isBuffer: false,
                },
                {
                  pool: wTokenAAddress,
                  tokenOut: tokenAAddress,
                  isBuffer: true,
                },
              ],
              exactAmountOut: amountToTrade,
              maxAmountIn: TOKEN_AMOUNT,
            },
          ],
          MAX_UINT256,
          false,
          '0x'
        );

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ERC4626 - BatchRouter] swapExactOut - with buffer liquidity - warm slots`,
          receipt
        );
      });
    });
  };
}
