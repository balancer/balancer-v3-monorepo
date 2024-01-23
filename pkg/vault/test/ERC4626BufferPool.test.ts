import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { ERC4626BufferPoolFactory, IVault } from '@balancer-labs/v3-vault/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { MONTH, currentTimestamp } from '@balancer-labs/v3-helpers/src/time';
import { ERC20TestToken, ERC4626TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { ONES_BYTES32, ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import { PoolConfigStructOutput } from '../typechain-types/contracts/test/VaultMock';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';

describe('ERC4626BufferPool', function () {
  let vault: IVault;
  let factory: ERC4626BufferPoolFactory;
  let wrappedToken: ERC4626TestToken;
  let baseToken: ERC20TestToken;
  let pool: Contract;

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    vault = await TypesConverter.toIVault(await VaultDeployer.deploy());

    baseToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Dai Stablecoin', 'DAI', 18] });
    wrappedToken = await deploy('v3-solidity-utils/ERC4626TestToken', {
      args: [baseToken, 'Wrapped aDAI', 'waDAI', 18],
    });

    factory = await deploy('v3-vault/ERC4626BufferPoolFactory', { args: [vault, 12 * MONTH] });
  });

  describe('registration', () => {
    sharedBeforeEach('create pool', async () => {
      const tx = await factory.create(wrappedToken, ZERO_BYTES32);
      const receipt = await tx.wait();

      const event = expectEvent.inReceipt(receipt, 'PoolCreated');

      const poolAddress = event.args.pool;

      pool = await deployedAt('ERC4626BufferPool', poolAddress);
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

      expect(actualTokens).to.deep.equal([await wrappedToken.getAddress(), await baseToken.getAddress()]);
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
});
