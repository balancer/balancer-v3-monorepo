/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { saveSnap } from '@balancer-labs/v3-helpers/src/gas';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48, MAX_UINT128 } from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import {
  PoolConfigStructOutput,
  TokenConfigStruct,
} from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { IVault, ProtocolFeeController } from '@balancer-labs/v3-vault/typechain-types';
import { WeightedPoolFactory } from '@balancer-labs/v3-pool-weighted/typechain-types';
import { ERC20WithRateTestToken, WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { BaseContract } from 'ethers';
import { IERC20 } from '@balancer-labs/v3-interfaces/typechain-types';

export class Benchmark {
  _testDirname: string;
  _poolType: string;
  vault!: IVault;
  tokenA!: ERC20WithRateTestToken;
  tokenB!: ERC20WithRateTestToken;
  WETH!: WETHTestToken;
  factory!: WeightedPoolFactory;
  pool!: BaseContract;
  tokenConfig!: TokenConfigStruct[];

  constructor(dirname: string, poolType: string) {
    this._testDirname = dirname;
    this._poolType = poolType;
  }

  async deployPool(): Promise<BaseContract | null> {
    return null;
  }

  itBenchmarksSwap = () => {
    const MAX_PROTOCOL_SWAP_FEE = fp(0.5);
    const MAX_PROTOCOL_YIELD_FEE = fp(0.2);

    const TOKEN_AMOUNT = fp(100);

    const SWAP_AMOUNT = fp(20);
    const SWAP_FEE = fp(0.01);

    let permit2: IPermit2;
    let feeCollector: ProtocolFeeController;
    let router: Router;
    let alice: SignerWithAddress;
    let admin: SignerWithAddress;
    let initialBalances: bigint[];

    let tokenAAddress: string;
    let tokenBAddress: string;
    let wethAddress: string;

    let poolTokens: string[];

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
      router = await deploy('v3-vault/Router', { args: [this.vault, this.WETH, permit2] });
      this.tokenA = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token C', 'TKNC', 18] });
      this.tokenB = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token D', 'TKND', 18] });

      tokenAAddress = await this.tokenA.getAddress();
      tokenBAddress = await this.tokenB.getAddress();
      wethAddress = await this.WETH.getAddress();
    });

    sharedBeforeEach('protocol fees configuration', async () => {
      const setSwapFeeAction = await actionId(feeCollector, 'setGlobalProtocolSwapFeePercentage');
      const setYieldFeeAction = await actionId(feeCollector, 'setGlobalProtocolYieldFeePercentage');

      const authorizerAddress = await this.vault.getAuthorizer();
      const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

      await authorizer.grantRole(setSwapFeeAction, admin.address);
      await authorizer.grantRole(setYieldFeeAction, admin.address);

      await feeCollector.connect(admin).setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
      await feeCollector.connect(admin).setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
    });

    sharedBeforeEach('token setup', async () => {
      await this.tokenA.mint(alice, TOKEN_AMOUNT * 10n);
      await this.tokenB.mint(alice, TOKEN_AMOUNT * 10n);
      await this.WETH.connect(alice).deposit({ value: TOKEN_AMOUNT });

      for (const token of [this.tokenA, this.tokenB, this.WETH]) {
        await token.connect(alice).approve(permit2, MAX_UINT256);
        await permit2.connect(alice).approve(token, router, MAX_UINT160, MAX_UINT48);
      }
    });

    const itTestsInitialize = (useEth: boolean) => {
      const ethStatus = useEth ? 'with ETH' : 'without ETH';

      sharedBeforeEach('deploy pool', async () => {
        this.pool = (await this.deployPool())!;
      });

      it(`measures initialization gas ${ethStatus}`, async () => {
        initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);

        // Measure
        const value = useEth ? TOKEN_AMOUNT : 0;
        const tx = await router
          .connect(alice)
          .initialize(this.pool, poolTokens, initialBalances, FP_ZERO, useEth, '0x', { value });

        const receipt = await tx.wait();

        await saveSnap(this._testDirname, `[${this._poolType}] initialize ${ethStatus}`, receipt);
      });
    };

    const itTestsSwap = (
      gasTag: string,
      actionAfterInit: () => Promise<void>,
      actionAfterFirstTx: () => Promise<void>
    ) => {
      sharedBeforeEach('deploy pool', async () => {
        this.pool = (await this.deployPool())!;
      });

      sharedBeforeEach('set pool fee', async () => {
        const setPoolSwapFeeAction = await actionId(this.vault, 'setStaticSwapFeePercentage');

        const authorizerAddress = await this.vault.getAuthorizer();
        const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

        await authorizer.grantRole(setPoolSwapFeeAction, admin.address);

        await this.vault.connect(admin).setStaticSwapFeePercentage(this.pool, SWAP_FEE);
      });

      sharedBeforeEach('initialize pool', async () => {
        initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
        await router.connect(alice).initialize(this.pool, poolTokens, initialBalances, FP_ZERO, false, '0x');
        await actionAfterInit();
      });

      it('pool and protocol fee preconditions', async () => {
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(this.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;

        expect(await this.vault.getStaticSwapFeePercentage(this.pool)).to.eq(SWAP_FEE);
      });

      it('measures gas', async () => {
        // Warm up
        let tx = await router
          .connect(alice)
          .swapSingleTokenExactIn(this.pool, poolTokens[0], poolTokens[1], SWAP_AMOUNT, 0, MAX_UINT256, false, '0x');

        let receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag}] swap single token exact in with fees - cold slots`,
          receipt
        );

        await actionAfterFirstTx();

        // Measure
        tx = await router
          .connect(alice)
          .swapSingleTokenExactOut(
            this.pool,
            poolTokens[1],
            poolTokens[0],
            SWAP_AMOUNT,
            MAX_UINT128,
            MAX_UINT256,
            false,
            '0x'
          );
        receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag}] swap single token exact in with fees - warm slots`,
          receipt
        );
      });
    };

    const itTestsDonation = () => {
      sharedBeforeEach('deploy pool', async () => {
        this.pool = (await this.deployPool())!;
      });

      sharedBeforeEach('initialize pool', async () => {
        initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
        await router.connect(alice).initialize(this.pool, poolTokens, initialBalances, FP_ZERO, false, '0x');
      });

      it('pool preconditions', async () => {
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(this.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;
        expect(poolConfig.liquidityManagement.enableDonation).to.be.true;
      });

      it('measures gas', async () => {
        // Warm up
        const tx = await router.connect(alice).donate(this.pool, [SWAP_AMOUNT, SWAP_AMOUNT], false, '0x');
        const receipt = await tx.wait();
        await saveSnap(this._testDirname, `[${this._poolType}] donation`, receipt);
      });
    };

    const itTestsRemoveLiquidity = (
      gasTag: string,
      actionAfterInit: () => Promise<void>,
      actionAfterFirstTx: () => Promise<void>
    ) => {
      sharedBeforeEach('deploy pool', async () => {
        this.pool = (await this.deployPool())!;
      });

      sharedBeforeEach('set pool fee', async () => {
        const setPoolSwapFeeAction = await actionId(this.vault, 'setStaticSwapFeePercentage');

        const authorizerAddress = await this.vault.getAuthorizer();
        const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

        await authorizer.grantRole(setPoolSwapFeeAction, admin.address);

        await this.vault.connect(admin).setStaticSwapFeePercentage(this.pool, SWAP_FEE);
      });

      sharedBeforeEach('initialize pool', async () => {
        initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
        await router.connect(alice).initialize(this.pool, poolTokens, initialBalances, FP_ZERO, false, '0x');
        await actionAfterInit();
      });

      sharedBeforeEach('approve router to spend BPT', async () => {
        const bpt: IERC20 = await TypesConverter.toIERC20(this.pool);
        await bpt.connect(alice).approve(router, MAX_UINT256);
      });

      it('pool and protocol fee preconditions', async () => {
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(this.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;

        expect(await this.vault.getStaticSwapFeePercentage(this.pool)).to.eq(SWAP_FEE);
      });

      it('measures gas (proportional)', async () => {
        const bptBalance = await this.vault.balanceOf(this.pool, alice);
        const tx = await router
          .connect(alice)
          .removeLiquidityProportional(this.pool, bptBalance / 2n, Array(poolTokens.length).fill(0n), false, '0x');

        const receipt = await tx.wait();
        await saveSnap(this._testDirname, `[${this._poolType} - ${gasTag}] remove liquidity proportional`, receipt);
      });

      it('measures gas (single token exact in)', async () => {
        const bptBalance = await this.vault.balanceOf(this.pool, alice);
        // Warm up
        await router
          .connect(alice)
          .removeLiquiditySingleTokenExactIn(this.pool, bptBalance / 10n, poolTokens[0], 1, false, '0x');

        await actionAfterFirstTx();

        // Measure
        const tx = await router
          .connect(alice)
          .removeLiquiditySingleTokenExactIn(this.pool, bptBalance / 10n, poolTokens[1], 1, false, '0x');
        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag}] remove liquidity single token exact in - warm slots`,
          receipt
        );
      });

      it('measures gas (single token exact out)', async () => {
        const bptBalance = await this.vault.balanceOf(this.pool, alice);
        // Warm up
        await router
          .connect(alice)
          .removeLiquiditySingleTokenExactOut(
            this.pool,
            bptBalance / 2n,
            poolTokens[0],
            TOKEN_AMOUNT / 1000n,
            false,
            '0x'
          );

        await actionAfterFirstTx();

        // Measure
        const tx = await router
          .connect(alice)
          .removeLiquiditySingleTokenExactOut(
            this.pool,
            bptBalance / 2n,
            poolTokens[1],
            TOKEN_AMOUNT / 1000n,
            false,
            '0x'
          );
        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag}] remove liquidity single token exact out - warm slots`,
          receipt
        );
      });
    };

    const itTestsAddLiquidity = (
      gasTag: string,
      actionAfterInit: () => Promise<void>,
      actionAfterFirstTx: () => Promise<void>
    ) => {
      sharedBeforeEach('deploy pool', async () => {
        this.pool = (await this.deployPool())!;
      });

      sharedBeforeEach('set pool fee', async () => {
        const setPoolSwapFeeAction = await actionId(this.vault, 'setStaticSwapFeePercentage');

        const authorizerAddress = await this.vault.getAuthorizer();
        const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

        await authorizer.grantRole(setPoolSwapFeeAction, admin.address);

        await this.vault.connect(admin).setStaticSwapFeePercentage(this.pool, SWAP_FEE);
      });

      sharedBeforeEach('initialize pool', async () => {
        initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
        await router.connect(alice).initialize(this.pool, poolTokens, initialBalances, FP_ZERO, false, '0x');
        await actionAfterInit();
      });

      it('pool and protocol fee preconditions', async () => {
        const poolConfig: PoolConfigStructOutput = await this.vault.getPoolConfig(this.pool);

        expect(poolConfig.isPoolRegistered).to.be.true;
        expect(poolConfig.isPoolInitialized).to.be.true;

        expect(await this.vault.getStaticSwapFeePercentage(this.pool)).to.eq(SWAP_FEE);
      });

      it('measures gas (proportional)', async () => {
        const bptBalance = await this.vault.balanceOf(this.pool, alice);
        const tx = await router
          .connect(alice)
          .addLiquidityProportional(this.pool, Array(poolTokens.length).fill(TOKEN_AMOUNT), bptBalance, false, '0x');

        const receipt = await tx.wait();
        await saveSnap(this._testDirname, `[${this._poolType} - ${gasTag}] add liquidity proportional`, receipt);
      });

      it('measures gas (unbalanced)', async () => {
        const exactAmountsIn = Array(poolTokens.length)
          .fill(TOKEN_AMOUNT)
          .map((amount, index) => BigInt(amount / BigInt(index + 1)));

        // Warm up
        await router.connect(alice).addLiquidityUnbalanced(this.pool, exactAmountsIn, 0, false, '0x');

        await actionAfterFirstTx();

        // Measure
        const tx = await router.connect(alice).addLiquidityUnbalanced(this.pool, exactAmountsIn, 0, false, '0x');
        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag}] add liquidity unbalanced - warm slots`,
          receipt
        );
      });

      it('measures gas (single token exact out)', async () => {
        const bptBalance = await this.vault.balanceOf(this.pool, alice);
        // Warm up
        await router
          .connect(alice)
          .addLiquiditySingleTokenExactOut(this.pool, poolTokens[0], TOKEN_AMOUNT, bptBalance / 1000n, false, '0x');

        await actionAfterFirstTx();

        // Measure
        const tx = await router
          .connect(alice)
          .addLiquiditySingleTokenExactOut(this.pool, poolTokens[1], TOKEN_AMOUNT, bptBalance / 1000n, false, '0x');

        const receipt = await tx.wait();
        await saveSnap(
          this._testDirname,
          `[${this._poolType} - ${gasTag}] add liquidity single token exact out - warm slots`,
          receipt
        );
      });
    };

    describe('test standard pool', () => {
      sharedBeforeEach(async () => {
        poolTokens = sortAddresses([tokenAAddress, tokenBAddress]);
        this.tokenConfig = buildTokenConfig(poolTokens, false);
      });

      context('swap', () => {
        itTestsSwap(
          'Standard',
          async () => {
            return;
          },
          async () => {
            return;
          }
        );
      });

      context('remove liquidity', () => {
        itTestsRemoveLiquidity(
          'Standard',
          async () => {
            return;
          },
          async () => {
            return;
          }
        );
      });

      context('add liquidity', () => {
        itTestsRemoveLiquidity(
          'Standard',
          async () => {
            return;
          },
          async () => {
            return;
          }
        );
      });
    });

    describe('initialization', () => {
      sharedBeforeEach(async () => {
        poolTokens = sortAddresses([tokenAAddress, wethAddress]);
        this.tokenConfig = buildTokenConfig(poolTokens, false);
      });

      itTestsInitialize(false);
      itTestsInitialize(true);
    });

    describe('test yield pool', () => {
      sharedBeforeEach(async () => {
        poolTokens = sortAddresses([tokenAAddress, tokenBAddress]);
        this.tokenConfig = buildTokenConfig(poolTokens, true);
      });

      context('swap', () => {
        itTestsSwap(
          'With rate',
          async () => {
            await this.tokenA.setRate(fp(1.1));
            await this.tokenB.setRate(fp(1.1));
          },
          async () => {
            await this.tokenA.setRate(fp(1.2));
            await this.tokenB.setRate(fp(1.2));
          }
        );
      });

      context('remove liquidity', async () => {
        itTestsRemoveLiquidity(
          'With rate',
          async () => {
            await this.tokenA.setRate(fp(1.1));
            await this.tokenB.setRate(fp(1.1));
          },
          async () => {
            await this.tokenA.setRate(fp(1.2));
            await this.tokenB.setRate(fp(1.2));
          }
        );
      });

      context('add liquidity', async () => {
        itTestsAddLiquidity(
          'With rate',
          async () => {
            await this.tokenA.setRate(fp(1.1));
            await this.tokenB.setRate(fp(1.1));
          },
          async () => {
            await this.tokenA.setRate(fp(1.2));
            await this.tokenB.setRate(fp(1.2));
          }
        );
      });
    });

    describe('test donation', () => {
      itTestsDonation();
    });
  };
}
