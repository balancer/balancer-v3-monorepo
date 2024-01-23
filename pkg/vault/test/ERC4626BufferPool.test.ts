import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { ERC4626BufferPoolFactory, IVault, Router } from '@balancer-labs/v3-vault/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { MONTH, currentTimestamp } from '@balancer-labs/v3-helpers/src/time';
import { ERC20TestToken, ERC4626TestToken, WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { MAX_UINT256, ONES_BYTES32, ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import { PoolConfigStructOutput } from '../typechain-types/contracts/test/VaultMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { FP_ZERO, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';

describe('ERC4626BufferPool', function () {
  const TOKEN_AMOUNT = fp(1000);
  const MIN_BPT = bn(1e6);

  let vault: IVault;
  let router: Router;
  let factory: ERC4626BufferPoolFactory;
  let wrappedToken: ERC4626TestToken;
  let baseToken: ERC20TestToken;
  let baseTokenAddress: string;
  let wrappedTokenAddress: string;
  let tokenAddresses: string[];

  let alice: SignerWithAddress;

  let pool: Contract;

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    vault = await TypesConverter.toIVault(await VaultDeployer.deploy());

    const WETH: WETHTestToken = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('v3-vault/Router', { args: [vault, await WETH.getAddress()] });

    baseToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Dai Stablecoin', 'DAI', 18] });
    wrappedToken = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [baseToken, 'Wrapped aDAI', 'waDAI', 18],
    });

    baseTokenAddress = await baseToken.getAddress();
    wrappedTokenAddress = await wrappedToken.getAddress();
    tokenAddresses = [wrappedTokenAddress, baseTokenAddress];

    factory = await deploy('v3-vault/ERC4626BufferPoolFactory', { args: [vault, 12 * MONTH] });
  });

  async function createPool(): Promise<Contract> {
    const tx = await factory.create(wrappedToken, ZERO_BYTES32);
    const receipt = await tx.wait();

    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const poolAddress = event.args.pool;

    return await deployedAt('ERC4626BufferPool', poolAddress);
  }

  describe('registration', () => {
    sharedBeforeEach('create pool', async () => {
      pool = await createPool();
    });

    it('creates a pool', async () => {
      expect(await factory.isPoolFromFactory(pool)).to.be.true;
    });

    it('pool has correct metadata', async () => {
      expect(await pool.name()).to.eq('Balancer Buffer-Wrapped aDAI');
      expect(await pool.symbol()).to.eq('BB-waDAI');
    });

    it('registers the pool', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.false;
    });

    it('has the correct tokens', async () => {
      const actualTokens = await vault.getPoolTokens(pool);

      expect(actualTokens).to.deep.equal(tokenAddresses);
    });

    it('cannot be registered twice', async () => {
      await expect(factory.create(wrappedToken, ONES_BYTES32)).to.be.revertedWithCustomError(
        vault,
        'WrappedTokenBufferAlreadyRegistered'
      );
    });

    it('configures the pool correctly', async () => {
      const currentTime = await currentTimestamp();
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.pauseWindowEndTime).to.gt(currentTime);
      expect(poolConfig.callbacks.shouldCallBeforeSwap).to.be.true;
      expect(poolConfig.callbacks.shouldCallAfterSwap).to.be.false;
      expect(poolConfig.liquidityManagement.supportsAddLiquidityCustom).to.be.true;
      expect(poolConfig.liquidityManagement.supportsRemoveLiquidityCustom).to.be.false;
    });
  });

  describe('initialization', () => {
    sharedBeforeEach('create pool', async () => {
      pool = await createPool();

      wrappedToken.mint(TOKEN_AMOUNT, alice);
      baseToken.mint(alice, TOKEN_AMOUNT);

      wrappedToken.connect(alice).approve(vault, MAX_UINT256);
      baseToken.connect(alice).approve(vault, MAX_UINT256);
    });

    it('initializing emits an event and updates the state', async () => {
      // Preconditions
      expect(await wrappedToken.balanceOf(alice)).to.eq(TOKEN_AMOUNT);
      expect(await baseToken.balanceOf(alice)).to.eq(TOKEN_AMOUNT);

      expect(
        await router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      )
        .to.emit(vault, 'PoolInitialized')
        .withArgs(pool);

      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await pool.balanceOf(alice)).to.eq(TOKEN_AMOUNT * 2n - MIN_BPT);
      expect(await wrappedToken.balanceOf(alice)).to.eq(0);
      expect(await baseToken.balanceOf(alice)).to.eq(0);
    });
  });
});
