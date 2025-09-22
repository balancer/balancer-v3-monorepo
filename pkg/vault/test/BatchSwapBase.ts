import { ethers } from 'hardhat';
import { VoidSigner } from 'ethers';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';

import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import {
  BatchRouter,
  Router,
  PoolFactoryMock,
  Vault,
  ISenderGuard__factory,
  IVaultErrors__factory,
} from '../typechain-types';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { buildTokenConfig } from './poolSetup';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from './Permit2Deployer';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import {
  ERC20TestToken,
  ERC20TestToken__factory,
  ERC4626TestToken,
} from '@balancer-labs/v3-solidity-utils/typechain-types';
import { BalanceChange, expectBalanceChange } from '@balancer-labs/v3-helpers/src/test/tokenBalance';
import { BufferRouter } from '@balancer-labs/v3-pool-weighted/typechain-types';
import {
  SwapPathExactAmountInStruct,
  SwapPathExactAmountOutStruct,
} from '../typechain-types/contracts/AggregatorBatchHooks';

const BATCH_ROUTER_VERSION = 'BatchRouter v9';
const AGGREGATOR_BATCH_ROUTER_VERSION = 'AggregatorBatchRouter v9';
const ROUTER_VERSION = 'Router v9';

const TOKEN_AMOUNT = fp(1e12);
export const WRAPPED_TOKEN_AMOUNT = fp(1e6);

export class BatchSwapBaseTest {
  // BaseTest config
  isPrepaid: boolean;

  // Main contracts
  permit2!: IPermit2;
  vault!: Vault;
  vaultAddress!: string;
  factory!: PoolFactoryMock;

  bufferRouter!: BufferRouter;
  basicRouter!: Router;
  router!: BatchRouter;
  aggregatorRouter!: BatchRouter;

  // Pools
  pools!: PoolMock[];
  poolA!: PoolMock;
  poolB!: PoolMock;
  poolC!: PoolMock;
  poolWA!: PoolMock;
  poolWB!: PoolMock;
  poolAB!: PoolMock;
  poolAC!: PoolMock;
  poolBC!: PoolMock;
  poolATokens!: string[];
  poolBTokens!: string[];
  poolCTokens!: string[];
  poolWATokens!: string[];
  poolWBTokens!: string[];
  poolABTokens!: string[];
  poolACTokens!: string[];
  poolBCTokens!: string[];

  // Tokens
  tokens!: ERC20TokenList;
  token0!: string;
  token1!: string;
  token2!: string;
  wToken0!: ERC4626TestToken;
  wToken2!: ERC4626TestToken;
  wToken0Address!: string;
  wToken2Address!: string;

  // Signers
  lp!: SignerWithAddress;
  sender!: SignerWithAddress;
  zero!: VoidSigner;

  // Setup config (can be overridden in tests)
  pathExactAmountIn: bigint = fp(1);
  pathExactAmountOut: bigint = fp(1);
  pathMinAmountOut: bigint = fp(1);
  pathMaxAmountIn: bigint = fp(1);
  roundingError = 2n;

  // Test variables
  tokensIn!: (ERC20TestToken | PoolMock)[];
  tokensOut!: (ERC20TestToken | PoolMock)[];

  totalAmountIn!: bigint;
  totalAmountOut!: bigint;

  balanceChange!: BalanceChange[];

  // ExactIn Swap
  pathAmountsOut!: bigint[];
  amountsOut!: bigint[];
  pathsExactIn!: SwapPathExactAmountInStruct[];

  // ExactOut Swap
  pathAmountsIn!: bigint[];
  amountsIn!: bigint[];
  pathsExactOut!: SwapPathExactAmountOutStruct[];

  constructor(isPrepaid: boolean) {
    this.isPrepaid = isPrepaid;
  }

  async setUpSigners() {
    this.zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, this.lp, this.sender] = await ethers.getSigners();
  }

  async deployContracts() {
    const WETH = await deploy('v3-solidity-utils/WETHTestToken');

    this.vault = await VaultDeployer.deploy();
    this.vaultAddress = await this.vault.getAddress();
    this.permit2 = await deployPermit2();

    this.bufferRouter = await deploy('v3-vault/BufferRouter', {
      args: [this.vaultAddress, await WETH, this.permit2, ROUTER_VERSION],
    });
    this.basicRouter = await deploy('Router', {
      args: [this.vaultAddress, WETH, this.permit2, ROUTER_VERSION],
    });
    this.router = await deploy('BatchRouter', {
      args: [this.vaultAddress, WETH, this.permit2, BATCH_ROUTER_VERSION],
    });
    this.aggregatorRouter = await deploy('BatchRouter', {
      args: [this.vaultAddress, WETH, ethers.ZeroAddress, AGGREGATOR_BATCH_ROUTER_VERSION],
    });

    this.factory = await deploy('PoolFactoryMock', { args: [this.vaultAddress, 12 * MONTH] });

    this.tokens = await ERC20TokenList.create(3, { sorted: true });
    this.token0 = await this.tokens.get(0).getAddress();
    this.token1 = await this.tokens.get(1).getAddress();
    this.token2 = await this.tokens.get(2).getAddress();
    this.wToken0 = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [this.token0, 'Wrapped TK0', 'wTK0', 18],
    });
    this.wToken2 = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [this.token2, 'Wrapped TK2', 'wTK2', 18],
    });
    this.wToken0Address = await this.wToken0.getAddress();
    this.wToken2Address = await this.wToken2.getAddress();

    this.poolATokens = sortAddresses([this.token0, this.token1]);
    this.poolBTokens = sortAddresses([this.token1, this.token2]);
    this.poolCTokens = sortAddresses([this.token0, this.token2]);
    this.poolWATokens = sortAddresses([this.wToken0Address, this.token1]);
    this.poolWBTokens = sortAddresses([this.token1, this.wToken2Address]);

    // Pool A has tokens 0 and 1.
    this.poolA = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Pool A', 'POOL-A'],
    });
    // Pool A has tokens 1 and 2.
    this.poolB = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Pool B', 'POOL-B'],
    });
    // Pool C has tokens 0 and 2.
    this.poolC = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Pool C', 'POOL-C'],
    });
    // Pool A has wrapped token 0 and token 1.
    this.poolWA = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Wrapped Token 0 - Pool A', 'WPOOL-A'],
    });
    // Pool B has wrapped token 2 and token 1.
    this.poolWB = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Wrapped Token 2 - Pool B', 'WPOOL-B'],
    });

    await this.factory.registerTestPool(this.poolA, buildTokenConfig(this.poolATokens));
    await this.factory.registerTestPool(this.poolB, buildTokenConfig(this.poolBTokens));
    await this.factory.registerTestPool(this.poolC, buildTokenConfig(this.poolCTokens));
    await this.factory.registerTestPool(this.poolWA, buildTokenConfig(this.poolWATokens));
    await this.factory.registerTestPool(this.poolWB, buildTokenConfig(this.poolWBTokens));
  }

  async setUpNestedPools() {
    this.poolABTokens = sortAddresses([await this.poolA.getAddress(), await this.poolB.getAddress()]);
    this.poolAB = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Pool A-B', 'POOL-AB'],
    });

    this.poolACTokens = sortAddresses([await this.poolA.getAddress(), await this.poolC.getAddress()]);
    this.poolAC = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Pool A-C', 'POOL-AC'],
    });

    this.poolBCTokens = sortAddresses([await this.poolB.getAddress(), await this.poolC.getAddress()]);
    this.poolBC = await deploy('v3-vault/PoolMock', {
      args: [this.vaultAddress, 'Pool B-C', 'POOL-BC'],
    });

    await this.factory.registerTestPool(this.poolAB, buildTokenConfig(this.poolABTokens));
    await this.factory.registerTestPool(this.poolAC, buildTokenConfig(this.poolACTokens));
    await this.factory.registerTestPool(this.poolBC, buildTokenConfig(this.poolBCTokens));
  }

  async setUpAllowances() {
    this.pools = [this.poolA, this.poolB, this.poolC, this.poolAB, this.poolAC, this.poolBC, this.poolWA, this.poolWB];

    for (const user of [this.lp, this.sender]) {
      await this.tokens.mint({ to: user, amount: TOKEN_AMOUNT });

      await this.tokens
        .get(0)
        .connect(this.lp)
        .mint(user, WRAPPED_TOKEN_AMOUNT * 2n);
      await this.tokens.get(0).connect(user).approve(this.wToken0, WRAPPED_TOKEN_AMOUNT);
      await this.wToken0.connect(user).deposit(WRAPPED_TOKEN_AMOUNT, user);

      await this.tokens
        .get(2)
        .connect(user)
        .mint(user, WRAPPED_TOKEN_AMOUNT * 2n);
      await this.tokens.get(2).connect(user).approve(this.wToken2, WRAPPED_TOKEN_AMOUNT);
      await this.wToken2.connect(user).deposit(WRAPPED_TOKEN_AMOUNT, user);
    }

    await this.tokens.push(ERC20TestToken__factory.connect(this.wToken0Address, this.sender));
    await this.tokens.push(ERC20TestToken__factory.connect(this.wToken2Address, this.sender));

    for (const pool of this.pools) {
      await pool.connect(this.lp).approve(this.router, MAX_UINT256);
      await pool.connect(this.lp).approve(this.basicRouter, MAX_UINT256);
    }

    for (const token of [...this.tokens.tokens, ...this.pools]) {
      for (const from of [this.lp, this.sender]) {
        await token.connect(from).approve(this.permit2, MAX_UINT256);
        for (const to of [this.router, this.basicRouter, this.bufferRouter]) {
          await this.permit2.connect(from).approve(token, to, MAX_UINT160, MAX_UINT48);
        }
      }
    }

    await this.bufferRouter.connect(this.lp).initializeBuffer(this.wToken0, WRAPPED_TOKEN_AMOUNT, 0, 0);
    await this.bufferRouter.connect(this.lp).initializeBuffer(this.wToken2, WRAPPED_TOKEN_AMOUNT, 0, 0);
  }

  async initPools() {
    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolA, this.poolATokens, Array(this.poolATokens.length).fill(fp(10000)), 0, false, '0x');
    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolB, this.poolBTokens, Array(this.poolBTokens.length).fill(fp(10000)), 0, false, '0x');
    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolC, this.poolCTokens, Array(this.poolCTokens.length).fill(fp(10000)), 0, false, '0x');

    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolAB, this.poolABTokens, Array(this.poolABTokens.length).fill(fp(1000)), 0, false, '0x');
    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolAC, this.poolACTokens, Array(this.poolACTokens.length).fill(fp(1000)), 0, false, '0x');
    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolBC, this.poolBCTokens, Array(this.poolBCTokens.length).fill(fp(1000)), 0, false, '0x');

    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolWA, this.poolWATokens, Array(this.poolWATokens.length).fill(fp(10000)), 0, false, '0x');
    await this.basicRouter
      .connect(this.lp)
      .initialize(this.poolWB, this.poolWBTokens, Array(this.poolWBTokens.length).fill(fp(10000)), 0, false, '0x');

    await this.poolA.connect(this.lp).transfer(this.sender, fp(100));
    await this.poolB.connect(this.lp).transfer(this.sender, fp(100));
    await this.poolC.connect(this.lp).transfer(this.sender, fp(100));
  }

  cleanVariables() {
    this.tokensIn = [];
    this.tokensOut = [];
    this.totalAmountIn = 0n;
    this.totalAmountOut = 0n;
    this.pathAmountsIn = [];
    this.pathAmountsOut = [];
    this.amountsIn = [];
    this.amountsOut = [];
    this.balanceChange = [];
    this.pathsExactIn = [];
    this.pathAmountsOut = [];
  }

  async doSwapExactIn(): Promise<unknown> {
    return this._doSwapExactIn(false);
  }

  async doSwapExactInStatic(): Promise<{
    pathAmountsOut: bigint[];
    tokensOut: string[];
    amountsOut: bigint[];
  }> {
    return this._doSwapExactIn(true) as unknown as {
      pathAmountsOut: bigint[];
      tokensOut: string[];
      amountsOut: bigint[];
    };
  }

  private async _doSwapExactIn(isStatic: boolean, deadline = MAX_UINT256): Promise<unknown> {
    if (this.isPrepaid) {
      return (
        isStatic
          ? this.aggregatorRouter.connect(this.sender).swapExactIn.staticCall
          : this.aggregatorRouter.connect(this.sender).swapExactIn
      )(this.pathsExactIn, deadline, false, '0x');
    } else {
      return (
        isStatic
          ? this.router.connect(this.sender).swapExactIn.staticCall
          : this.router.connect(this.sender).swapExactIn
      )(this.pathsExactIn, deadline, false, '0x');
    }
  }

  async runQueryExactIn(): Promise<{
    pathAmountsOut: bigint[];
    tokensOut: string[];
    amountsOut: bigint[];
  }> {
    if (this.isPrepaid) {
      return this.aggregatorRouter
        .connect(this.zero)
        .querySwapExactIn.staticCall(this.pathsExactIn, this.zero.address, '0x');
    } else {
      return this.router.connect(this.zero).querySwapExactIn.staticCall(this.pathsExactIn, this.zero.address, '0x');
    }
  }

  itCommonTests() {
    it('reverts doSwapExactIn if deadline is in the past', async () => {
      this.pathsExactIn = [];

      const block = await ethers.provider.getBlock('latest');
      if (!block) throw new Error('Block not found');

      const deadline = BigInt(block.timestamp - 1);
      await expect(this._doSwapExactIn(false, deadline)).to.be.revertedWithCustomError(
        {
          interface: ISenderGuard__factory.createInterface(),
        },
        'SwapDeadline'
      );
    });

    it('reverts doSwapExactOut if deadline is in the past', async () => {
      this.pathsExactOut = [];
      const block = await ethers.provider.getBlock('latest');
      if (!block) throw new Error('Block not found');

      const deadline = BigInt(block.timestamp - 1);
      await expect(this._doSwapExactOut(false, deadline)).to.be.revertedWithCustomError(
        {
          interface: ISenderGuard__factory.createInterface(),
        },
        'SwapDeadline'
      );
    });

    it('reverts doSwapExactIn if amount out < min amount out', async () => {
      this.pathsExactIn = [
        {
          tokenIn: this.token0,
          steps: [{ pool: this.poolA, tokenOut: this.token1, isBuffer: false }],
          exactAmountIn: this.pathExactAmountIn,
          minAmountOut: MAX_UINT256,
        },
      ];

      if (this.isPrepaid) {
        await (
          await ERC20TestToken__factory.connect(this.token0, this.sender).transfer(this.vault, this.pathExactAmountIn)
        ).wait();
      }

      await expect(this._doSwapExactIn(false)).to.be.revertedWithCustomError(
        {
          interface: IVaultErrors__factory.createInterface(),
        },
        'SwapLimit'
      );
    });

    it('reverts doSwapExactOut if amount in > max amount in', async () => {
      this.pathsExactOut = [
        {
          tokenIn: this.token0,
          steps: [{ pool: this.poolA, tokenOut: this.token1, isBuffer: false }],
          exactAmountOut: this.pathExactAmountOut,
          maxAmountIn: 0n,
        },
      ];

      await expect(this._doSwapExactOut(false)).to.be.revertedWithCustomError(
        {
          interface: IVaultErrors__factory.createInterface(),
        },
        'SwapLimit'
      );
    });
  }

  itTestsBatchSwapExactIn(singleTransferIn = true, singleTransferOut = true) {
    it('performs swap, transfers tokens', async () => {
      await expectBalanceChange(this.doSwapExactIn.bind(this), this.tokens, this.balanceChange);
    });

    if (singleTransferIn) {
      it('performs single transfer for token in', async () => {
        await expect(this.doSwapExactIn())
          .to.emit(this.tokensIn[0], 'Transfer')
          .withArgs(this.sender.address, this.vaultAddress, this.totalAmountIn);
      });
    }

    if (singleTransferOut) {
      it('performs single transfer for token out', async () => {
        // Some operations have rounding error, and event arguments are precise. So we get the result from
        // the query to check the event arguments.
        const { amountsOut } = await this.runQueryExactIn();
        await expect(this.doSwapExactIn())
          .to.emit(this.tokensOut[0], 'Transfer')
          .withArgs(this.vaultAddress, this.sender.address, amountsOut[0]);
      });
    }

    it('returns path amounts out', async () => {
      const calculatedPathAmountsOut = (await this.doSwapExactInStatic()).pathAmountsOut;
      calculatedPathAmountsOut.map((pathAmountOut, i) =>
        expect(pathAmountOut).to.be.almostEqual(this.pathAmountsOut[i], 1e-8)
      );
    });

    it('returns tokens out', async () => {
      const calculatedTokensOut = (await this.doSwapExactInStatic()).tokensOut;
      expect(calculatedTokensOut).to.be.deep.eq(
        await Promise.all(this.tokensOut.map(async (tokenOut) => await tokenOut.getAddress()))
      );
    });

    it('returns token amounts out', async () => {
      const calculatedAmountsOut = (await this.doSwapExactInStatic()).amountsOut;
      calculatedAmountsOut.map((amountOut, i) => expect(amountOut).to.be.almostEqual(this.amountsOut[i], 1e-8));
    });

    it('returns same outputs as query', async () => {
      const realOutputs = await this.doSwapExactInStatic();
      const queryOutputs = await this.runQueryExactIn();

      expect(realOutputs.pathAmountsOut).to.be.deep.eq(queryOutputs.pathAmountsOut);
      expect(realOutputs.amountsOut).to.be.deep.eq(queryOutputs.amountsOut);
      expect(realOutputs.tokensOut).to.be.deep.eq(queryOutputs.tokensOut);
    });
  }

  async doSwapExactOut(): Promise<unknown> {
    return this._doSwapExactOut(false);
  }

  async doSwapExactOutStatic(): Promise<{
    pathAmountsIn: bigint[];
    tokensIn: string[];
    amountsIn: bigint[];
  }> {
    return this._doSwapExactOut(true) as unknown as {
      pathAmountsIn: bigint[];
      tokensIn: string[];
      amountsIn: bigint[];
    };
  }

  async runQueryExactOut(): Promise<{
    pathAmountsIn: bigint[];
    tokensIn: string[];
    amountsIn: bigint[];
  }> {
    if (this.isPrepaid) {
      return this.aggregatorRouter
        .connect(this.zero)
        .querySwapExactOut.staticCall(this.pathsExactOut, this.zero.address, '0x');
    } else
      return this.router.connect(this.zero).querySwapExactOut.staticCall(this.pathsExactOut, this.zero.address, '0x');
  }

  private async _doSwapExactOut(isStatic: boolean, deadline = MAX_UINT256): Promise<unknown> {
    if (this.isPrepaid) {
      return (
        isStatic
          ? this.aggregatorRouter.connect(this.sender).swapExactOut.staticCall
          : this.aggregatorRouter.connect(this.sender).swapExactOut
      )(this.pathsExactOut, deadline, false, '0x');
    } else {
      return (
        isStatic
          ? this.router.connect(this.sender).swapExactOut.staticCall
          : this.router.connect(this.sender).swapExactOut
      )(this.pathsExactOut, deadline, false, '0x');
    }
  }

  itTestsBatchSwapExactOut(singleTransferIn = true, singleTransferOut = true) {
    it('performs swap, transfers tokens', async () => {
      await expectBalanceChange(this.doSwapExactOut.bind(this), this.tokens, this.balanceChange);
    });

    if (singleTransferIn) {
      it('performs single transfer for token in', async () => {
        // Some operations have rounding error, and event arguments are precise. So we get the result from
        // the query to check the event arguments.
        const { amountsIn } = await this.runQueryExactOut();

        await expect(this.doSwapExactOut())
          .to.emit(this.tokensIn[0], 'Transfer')
          .withArgs(this.sender.address, this.vaultAddress, amountsIn[0]);
      });
    }

    if (singleTransferOut) {
      it('performs single transfer for token out', async () => {
        await expect(this.doSwapExactOut())
          .to.emit(this.tokensOut[0], 'Transfer')
          .withArgs(this.vaultAddress, this.sender.address, this.totalAmountOut);
      });
    }

    it('returns path amounts in', async () => {
      const calculatedPathAmountsIn = (await this.doSwapExactOutStatic()).pathAmountsIn;
      calculatedPathAmountsIn.map((pathAmountIn, i) =>
        expect(pathAmountIn).to.be.almostEqual(this.pathAmountsIn[i], 1e-8)
      );
    });

    it('returns tokens in', async () => {
      const calculatedTokensIn = (await this.doSwapExactOutStatic()).tokensIn;
      expect(calculatedTokensIn).to.be.deep.eq(
        await Promise.all(this.tokensIn.map(async (tokenIn) => await tokenIn.getAddress()))
      );
    });

    it('returns token amounts in', async () => {
      const calculatedAmountsIn = (await this.doSwapExactOutStatic()).amountsIn;
      calculatedAmountsIn.map((amountIn, i) => expect(amountIn).to.be.almostEqual(this.amountsIn[i], 1e-8));
    });

    it('returns same outputs as query', async () => {
      const realOutputs = await this.doSwapExactOutStatic();
      const queryOutputs = await this.runQueryExactOut();

      expect(realOutputs.pathAmountsIn).to.be.deep.eq(queryOutputs.pathAmountsIn);
      expect(realOutputs.amountsIn).to.be.deep.eq(queryOutputs.amountsIn);
      expect(realOutputs.tokensIn).to.be.deep.eq(queryOutputs.tokensIn);
    });
  }
}
