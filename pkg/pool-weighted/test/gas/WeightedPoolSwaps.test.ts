/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { saveSnap } from '@balancer-labs/v3-helpers/src/gas';
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
  MAX_UINT128,
} from '@balancer-labs/v3-helpers/src/constants';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import {
  PoolConfigStructOutput,
  TokenConfigStruct,
} from '@balancer-labs/v3-interfaces/typechain-types/contracts/vault/IVault';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types/permit2/src/interfaces/IPermit2';
import { IVault, ProtocolFeeController } from '@balancer-labs/v3-vault/typechain-types';
import { WeightedPool, WeightedPoolFactory } from '@balancer-labs/v3-pool-weighted/typechain-types';
import { ERC20WithRateTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { PoolRoleAccountsStruct } from '@balancer-labs/v3-vault/typechain-types/contracts/Vault';

describe('WeightedPool Gas Benchmark', function () {
  const MAX_PROTOCOL_SWAP_FEE = fp(0.5);
  const MAX_PROTOCOL_YIELD_FEE = fp(0.2);

  const TOKEN_AMOUNT = fp(100);

  const WEIGHTS = [fp(0.5), fp(0.5)];
  const SWAP_AMOUNT = fp(20);

  const SWAP_FEE = fp(0.01);

  let permit2: IPermit2;
  let vault: IVault;
  let feeCollector: ProtocolFeeController;
  let pool: WeightedPool;
  let router: Router;
  let alice: SignerWithAddress;
  let admin: SignerWithAddress;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20WithRateTestToken;
  let tokenD: ERC20WithRateTestToken;
  let poolTokens: string[];
  let tokenConfig: TokenConfigStruct[];
  let initialBalances: bigint[];

  let tokenAAddress: string;
  let tokenBAddress: string;
  let tokenCAddress: string;
  let tokenDAddress: string;

  let factory: WeightedPoolFactory;

  before('setup signers', async () => {
    [, alice, admin] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens', async function () {
    vault = await TypesConverter.toIVault(await VaultDeployer.deploy());
    feeCollector = (await deployedAt(
      'v3-vault/ProtocolFeeController',
      await vault.getProtocolFeeController()
    )) as unknown as ProtocolFeeController;
    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await deploy('v3-vault/Router', { args: [vault, WETH, permit2] });
    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
    tokenC = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token C', 'TKNC', 18] });
    tokenD = await deploy('v3-solidity-utils/ERC20WithRateTestToken', { args: ['Token D', 'TKND', 18] });

    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();
    tokenCAddress = await tokenC.getAddress();
    tokenDAddress = await tokenD.getAddress();
  });

  sharedBeforeEach('protocol fees configuration', async () => {
    const setSwapFeeAction = await actionId(feeCollector, 'setGlobalProtocolSwapFeePercentage');
    const setYieldFeeAction = await actionId(feeCollector, 'setGlobalProtocolYieldFeePercentage');

    const authorizerAddress = await vault.getAuthorizer();
    const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

    await authorizer.grantRole(setSwapFeeAction, admin.address);
    await authorizer.grantRole(setYieldFeeAction, admin.address);

    await feeCollector.connect(admin).setGlobalProtocolSwapFeePercentage(MAX_PROTOCOL_SWAP_FEE);
    await feeCollector.connect(admin).setGlobalProtocolYieldFeePercentage(MAX_PROTOCOL_YIELD_FEE);
  });

  sharedBeforeEach('token setup', async () => {
    await tokenA.mint(alice, TOKEN_AMOUNT * 10n);
    await tokenB.mint(alice, TOKEN_AMOUNT * 10n);
    await tokenC.mint(alice, TOKEN_AMOUNT * 10n);
    await tokenD.mint(alice, TOKEN_AMOUNT * 10n);

    for (const token of [tokenA, tokenB, tokenC, tokenD]) {
      await token.connect(alice).approve(permit2, MAX_UINT256);
      await permit2.connect(alice).approve(token, router, MAX_UINT160, MAX_UINT48);
    }
  });

  sharedBeforeEach('deploy weighted pool factory', async () => {
    factory = await deploy('v3-pool-weighted/WeightedPoolFactory', {
      args: [await vault.getAddress(), MONTH * 12, '', ''],
    });
  });

  describe('test standard pool', () => {
    sharedBeforeEach(async () => {
      poolTokens = sortAddresses([tokenAAddress, tokenBAddress]);
      tokenConfig = buildTokenConfig(poolTokens, false);
    });

    itTestsSwap(
      '[Standard]',
      async () => {
        return;
      },
      async () => {
        return;
      }
    );
  });

  describe('test yield pool', () => {
    sharedBeforeEach(async () => {
      poolTokens = sortAddresses([tokenCAddress, tokenDAddress]);
      tokenConfig = buildTokenConfig(poolTokens, true);
    });

    itTestsSwap(
      '[With rate]',
      async () => {
        await tokenC.setRate(fp(1.1));
        await tokenD.setRate(fp(1.1));
      },
      async () => {
        await tokenC.setRate(fp(1.2));
        await tokenD.setRate(fp(1.2));
      }
    );
  });

  function itTestsSwap(gasTag: string, actionAfterInit: () => Promise<void>, actionAfterFirstTx: () => Promise<void>) {
    sharedBeforeEach('deploy pool', async () => {
      const poolRoleAccounts: PoolRoleAccountsStruct = {
        pauseManager: ZERO_ADDRESS,
        swapFeeManager: ZERO_ADDRESS,
        poolCreator: ZERO_ADDRESS,
      };
      const tx = await factory.create(
        'WeightedPool',
        'Test',
        tokenConfig,
        WEIGHTS,
        poolRoleAccounts,
        SWAP_FEE,
        ZERO_ADDRESS,
        ZERO_BYTES32
      );
      const receipt = await tx.wait();
      const event = expectEvent.inReceipt(receipt, 'PoolCreated');

      pool = (await deployedAt('v3-pool-weighted/WeightedPool', event.args.pool)) as unknown as WeightedPool;
    });

    sharedBeforeEach('set pool fee', async () => {
      const setPoolSwapFeeAction = await actionId(vault, 'setStaticSwapFeePercentage');

      const authorizerAddress = await vault.getAuthorizer();
      const authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

      await authorizer.grantRole(setPoolSwapFeeAction, admin.address);

      await vault.connect(admin).setStaticSwapFeePercentage(pool, SWAP_FEE);
    });

    sharedBeforeEach('initialize pool', async () => {
      initialBalances = Array(poolTokens.length).fill(TOKEN_AMOUNT);
      await router.connect(alice).initialize(pool, poolTokens, initialBalances, FP_ZERO, false, '0x');
      await actionAfterInit();
    });

    it('pool and protocol fee preconditions', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await vault.getStaticSwapFeePercentage(pool)).to.eq(SWAP_FEE);
    });

    it('measures gas', async () => {
      // Warm up
      let tx = await router
        .connect(alice)
        .swapSingleTokenExactIn(pool, poolTokens[0], poolTokens[1], SWAP_AMOUNT, 0, MAX_UINT256, false, '0x');

      let receipt = await tx.wait();
      await saveSnap(__dirname, `${gasTag} swap single token exact in with fees - cold slots`, receipt);

      await actionAfterFirstTx();

      // Measure
      tx = await router
        .connect(alice)
        .swapSingleTokenExactOut(
          pool,
          poolTokens[1],
          poolTokens[0],
          SWAP_AMOUNT,
          MAX_UINT128,
          MAX_UINT256,
          false,
          '0x'
        );
      receipt = await tx.wait();
      await saveSnap(__dirname, `${gasTag} swap single token exact in with fees - warm slots`, receipt);
    });
  }
});
