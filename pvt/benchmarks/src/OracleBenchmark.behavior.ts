/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { ethers } from 'hardhat';

import { BaseContract } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp, bn } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48, MAX_UINT128 } from '@balancer-labs/v3-helpers/src/constants';
import { saveSnap } from '@balancer-labs/v3-helpers/src/gas';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';

import {
  BatchRouter,
  BufferRouter,
  Router,
  IVault,
  ProtocolFeeController,
} from '@balancer-labs/v3-vault/typechain-types';
import {
  ERC20WithRateTestToken,
  ERC4626TestToken,
  WETHTestToken,
} from '@balancer-labs/v3-solidity-utils/typechain-types';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { AggregatorV3Interface } from '@balancer-labs/v3-interfaces/typechain-types';
import { LPOracleWrapper } from '@balancer-labs/v3-standalone-utils/typechain-types/contracts/test';

export type PoolInfo = {
  pool: BaseContract;
  poolTokens: string[];
};

export type OracleInfo = {
  oracle: AggregatorV3Interface;
};

export class LPOracleBenchmark {
  _testDirname: string;
  _oracleType: string;

  vault!: IVault;
  tokenA!: ERC20WithRateTestToken;
  tokenB!: ERC20WithRateTestToken;
  tokenC!: ERC20WithRateTestToken;
  tokenD!: ERC20WithRateTestToken;
  wTokenA!: ERC4626TestToken;
  wTokenB!: ERC4626TestToken;
  wTokenC!: ERC4626TestToken;
  WETH!: WETHTestToken;

  permit2!: IPermit2;
  feeCollector!: ProtocolFeeController;
  router!: Router;
  bufferRouter!: BufferRouter;
  batchRouter!: BatchRouter;
  alice!: SignerWithAddress;
  admin!: SignerWithAddress;

  constructor(dirname: string, poolType: string) {
    this._testDirname = dirname;
    this._oracleType = poolType;
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async deployPool(poolTokens: string[]): Promise<PoolInfo | null> {
    return null;
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async deployOracle(poolAddress: string): Promise<OracleInfo | null> {
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

    let tokenAAddress: string;
    let tokenBAddress: string;
    let tokenCAddress: string;
    let tokenDAddress: string;
    let wTokenAAddress: string;
    let wTokenBAddress: string;
    let wTokenCAddress: string;
    let wethAddress: string;

    before('setup signers', async () => {
      [, this.alice, this.admin] = await ethers.getSigners();
    });

    sharedBeforeEach('deploy vault, router, tokens', async () => {
      this.vault = await TypesConverter.toIVault(await VaultDeployer.deploy());
      this.feeCollector = (await deployedAt(
        'v3-vault/ProtocolFeeController',
        await this.vault.getProtocolFeeController()
      )) as unknown as ProtocolFeeController;
      this.WETH = await deploy('v3-solidity-utils/WETHTestToken');
      this.permit2 = await deployPermit2();
      this.router = await deploy('v3-vault/Router', { args: [this.vault, this.WETH, this.permit2, ROUTER_VERSION] });
      this.bufferRouter = await deploy('v3-vault/BufferRouter', {
        args: [this.vault, this.WETH, this.permit2, ROUTER_VERSION],
      });
      this.batchRouter = await deploy('v3-vault/BatchRouter', {
        args: [this.vault, this.WETH, this.permit2, BATCH_ROUTER_VERSION],
      });
      this.tokenA = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token A', 'TKNA', 18] });
      this.tokenB = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token B', 'TKNB', 18] });
      this.tokenC = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token C', 'TKNC', 18] });
      this.tokenD = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token D', 'TKND', 18] });

      tokenAAddress = await this.tokenA.getAddress();
      tokenBAddress = await this.tokenB.getAddress();
      tokenCAddress = await this.tokenC.getAddress();
      tokenDAddress = await this.tokenD.getAddress();
      wethAddress = await this.WETH.getAddress();

      this.wTokenA = await deploy('v3-solidity-utils/ERC4626TestToken', {
        args: [tokenAAddress, 'wTokenA', 'wTokenA', 18],
      });
      this.wTokenB = await deploy('v3-solidity-utils/ERC4626TestToken', {
        args: [tokenBAddress, 'wTokenB', 'wTokenB', 18],
      });
      this.wTokenC = await deploy('v3-solidity-utils/ERC4626TestToken', {
        args: [tokenCAddress, 'wTokenC', 'wTokenC', 18],
      });
      wTokenAAddress = await this.wTokenA.getAddress();
      wTokenBAddress = await this.wTokenB.getAddress();
      wTokenCAddress = await this.wTokenC.getAddress();
    });

    sharedBeforeEach('token setup', async () => {
      await this.tokenA.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.tokenB.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.tokenC.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.tokenD.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.WETH.connect(this.alice).deposit({ value: TOKEN_AMOUNT });

      for (const token of [
        this.tokenA,
        this.tokenB,
        this.tokenC,
        this.tokenD,
        this.WETH,
        this.wTokenA,
        this.wTokenB,
        this.wTokenC,
      ]) {
        await token.connect(this.alice).approve(this.permit2, MAX_UINT256);
        await this.permit2.connect(this.alice).approve(token, this.router, MAX_UINT160, MAX_UINT48);
        await this.permit2.connect(this.alice).approve(token, this.bufferRouter, MAX_UINT160, MAX_UINT48);
        await this.permit2.connect(this.alice).approve(token, this.batchRouter, MAX_UINT160, MAX_UINT48);
      }

      for (const token of [this.wTokenA, this.wTokenB, this.wTokenC]) {
        const underlying = (await deployedAt(
          'v3-solidity-utils/ERC20WithRateTestToken',
          await token.asset()
        )) as unknown as ERC20WithRateTestToken;
        await underlying.connect(this.alice).approve(await token.getAddress(), TOKEN_AMOUNT * 10n);
        await token.connect(this.alice).deposit(TOKEN_AMOUNT * 10n, await this.alice.getAddress());
      }
    });

    const deployOracle = async (poolTokens: string[]): Promise<OracleInfo | null> => {
      const poolInfo = await this.deployPool(poolTokens);
      const poolAddress = await poolInfo?.pool.getAddress();
      if (!poolAddress) {
        throw new Error('Pool was not deployed');
      }
      return this.deployOracle(poolAddress);
    };

    describe('measure gas 2 tokens', () => {
      let oracleContract: AggregatorV3Interface;

      sharedBeforeEach(`deploy pool`, async () => {
        const oracleInfo = await deployOracle(sortAddresses([tokenAAddress, tokenBAddress]));
        if (!oracleInfo) {
          throw new Error('Oracle was not deployed');
        }
        oracleContract = oracleInfo.oracle;
      });

      it('measures gas', async () => {
        const wrapper: LPOracleWrapper = await deploy('v3-standalone-utils/LPOracleWrapper', {
          args: [await oracleContract.getAddress()],
        });
        const tx = await wrapper.callLatestRoundData();
        const receipt = await tx.wait();
        await saveSnap(this._testDirname, `${this._oracleType}`, [receipt!]);
      });
    });
  };
}
