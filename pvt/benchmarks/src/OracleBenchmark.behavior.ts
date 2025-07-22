/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { ethers } from 'hardhat';

import { BaseContract, ContractTransactionReceipt } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import { saveMinMaxAvgSnap } from '@balancer-labs/v3-helpers/src/gas';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';

import { Router, IVault } from '@balancer-labs/v3-vault/typechain-types';
import { ERC20WithRateTestToken, WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { AggregatorV3Interface, IERC20Metadata } from '@balancer-labs/v3-interfaces/typechain-types';
import { FeedMock } from '@balancer-labs/v3-standalone-utils/typechain-types/contracts/test';

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
  WETH!: WETHTestToken;

  permit2!: IPermit2;
  router!: Router;
  alice!: SignerWithAddress;

  constructor(dirname: string, poolType: string) {
    this._testDirname = dirname;
    this._oracleType = poolType;
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async deployPool(poolTokens: string[]): Promise<PoolInfo | null> {
    return null;
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  async deployOracle(poolAddress: string, feeds: AggregatorV3Interface[]): Promise<OracleInfo | null> {
    return null;
  }

  itBenchmarks = () => {
    const ROUTER_VERSION = 'Router v9';
    const TOKEN_AMOUNT = fp(100);

    let tokenAddresses: string[];
    let feedMocks: FeedMock[];

    let benchmark: LPOracleBenchmark;

    before('setup benchmark', () => {
      // eslint-disable-next-line @typescript-eslint/no-this-alias
      benchmark = this;
    });

    before('setup signers', async () => {
      [, this.alice] = await ethers.getSigners();
    });

    sharedBeforeEach('deploy vault, router, tokens', async () => {
      this.vault = await TypesConverter.toIVault(await VaultDeployer.deploy());
      this.WETH = await deploy('v3-solidity-utils/WETHTestToken');
      this.permit2 = await deployPermit2();
      this.router = await deploy('v3-vault/Router', { args: [this.vault, this.WETH, this.permit2, ROUTER_VERSION] });
      this.tokenA = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token A', 'TKNA', 18] });
      this.tokenB = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token B', 'TKNB', 18] });
      this.tokenC = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token C', 'TKNC', 18] });
      this.tokenD = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token D', 'TKND', 18] });

      tokenAddresses = [];
      tokenAddresses[0] = await this.tokenA.getAddress();
      tokenAddresses[1] = await this.tokenB.getAddress();
      tokenAddresses[2] = await this.tokenC.getAddress();
      tokenAddresses[3] = await this.tokenD.getAddress();
    });

    sharedBeforeEach('token setup', async () => {
      await this.tokenA.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.tokenB.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.tokenC.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.tokenD.mint(this.alice, TOKEN_AMOUNT * 20n);
      await this.WETH.connect(this.alice).deposit({ value: TOKEN_AMOUNT });

      for (const token of [this.tokenA, this.tokenB, this.tokenC, this.tokenD, this.WETH]) {
        await token.connect(this.alice).approve(this.permit2, MAX_UINT256);
        await this.permit2.connect(this.alice).approve(token, this.router, MAX_UINT160, MAX_UINT48);
      }
    });

    const deployOracle = async (poolTokens: string[]): Promise<OracleInfo | null> => {
      // Deploy pool
      const poolInfo = await this.deployPool(poolTokens);
      if (!poolInfo) {
        throw new Error('Pool was not deployed');
      }

      // Initialize pool
      const initialBalances = Array(poolInfo.poolTokens.length).fill(TOKEN_AMOUNT);
      await this.router
        .connect(this.alice)
        .initialize(poolInfo.pool, poolInfo.poolTokens, initialBalances, FP_ZERO, false, '0x');

      const poolAddress = await poolInfo.pool.getAddress();

      const feeds = [];
      feedMocks = [];
      for (let i = 0; i < poolInfo.poolTokens.length; i++) {
        const token = poolInfo.poolTokens[i];
        const tokenMetadata = (await deployedAt('v3-interfaces/IERC20Metadata', token)) as unknown as IERC20Metadata;
        const feedMock = (await deploy('v3-standalone-utils/FeedMock', {
          args: [tokenMetadata.decimals()],
        })) as unknown as FeedMock;
        const feed = (await deployedAt(
          'v3-interfaces/AggregatorV3Interface',
          await feedMock.getAddress()
        )) as unknown as AggregatorV3Interface;
        feeds.push(feed);
        feedMocks.push(feedMock);
      }

      return this.deployOracle(poolAddress, feeds);
    };

    function itMeasuresGas(numberOfTokens: number) {
      describe(`measure gas ${numberOfTokens} tokens`, () => {
        let oracleContract: AggregatorV3Interface;

        sharedBeforeEach(`deploy oracle`, async () => {
          const poolTokens = [];
          for (let i = 0; i < numberOfTokens; i++) {
            poolTokens.push(tokenAddresses[i]);
          }

          const oracleInfo = await deployOracle(sortAddresses(poolTokens));
          if (!oracleInfo) {
            throw new Error('Oracle was not deployed');
          }
          oracleContract = oracleInfo.oracle;
        });

        it('measures gas', async () => {
          const aggregatorV3InterfaceAbi = new ethers.Interface([
            'function latestRoundData() public view returns (uint80, int256, uint256, uint256, uint80)',
          ]);
          const latestRoundData = aggregatorV3InterfaceAbi.encodeFunctionData('latestRoundData');

          const priceArray = [fp(0.1), fp(1), fp(10)];
          const cases = [];
          for (let i = 0; i < Math.pow(priceArray.length, numberOfTokens); i++) {
            const casePrices = [];
            for (let j = 0; j < numberOfTokens; j++) {
              casePrices.push(priceArray[Math.floor(i / Math.pow(priceArray.length, j)) % priceArray.length]);
            }

            cases.push(casePrices);
          }

          const receipts: ContractTransactionReceipt[] = [];
          for (const casePrices of cases) {
            for (let i = 0; i < casePrices.length; i++) {
              await feedMocks[i].setLastRoundData(casePrices[i], Math.floor(Date.now() / 1000));
            }

            const tx = await benchmark.alice.sendTransaction({
              to: await oracleContract.getAddress(),
              data: latestRoundData,
            });
            receipts.push((await tx.wait()) as unknown as ContractTransactionReceipt);
          }

          await saveMinMaxAvgSnap(
            benchmark._testDirname,
            `${benchmark._oracleType} - ${numberOfTokens} tokens`,
            receipts
          );
        });
      });
    }

    context('measure gas', () => {
      itMeasuresGas(2);
      itMeasuresGas(3);
      itMeasuresGas(4);
    });
  };
}
