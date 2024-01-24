import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { Router } from '@balancer-labs/v3-vault/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { MONTH, currentTimestamp } from '@balancer-labs/v3-helpers/src/time';
import { ERC20TestToken, ERC4626TestToken, WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { MAX_UINT256, ONES_BYTES32, ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import { PoolConfigStructOutput, VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { FP_ZERO, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { TOKEN_TYPE } from '@balancer-labs/v3-helpers/src/models/types/types';

describe('ERC4626BufferPool', function () {
  const TOKEN_AMOUNT = fp(1000);
  const MIN_BPT = bn(1e6);

  let vault: IVaultMock;
  let authorizer: Contract;
  let router: Router;
  let factory: Contract;
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
    const vaultMock: VaultMock = await VaultDeployer.deployMock();
    vault = await TypesConverter.toIVaultMock(vaultMock);

    const authorizerAddress = await vault.getAuthorizer();
    authorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', authorizerAddress);

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

  async function createPool(grantPermission = false): Promise<Contract> {
    if (grantPermission) {
      const createPoolAction = await actionId(factory, 'create');

      await authorizer.grantRole(createPoolAction, alice.address);
    }

    const tx = await factory.connect(alice).create(wrappedToken, ZERO_BYTES32);
    const receipt = await tx.wait();

    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const poolAddress = event.args.pool;

    return await deployedAt('ERC4626BufferPool', poolAddress);
  }

  it('does not allow registration without permission', async () => {
    await expect(createPool()).to.be.revertedWithCustomError(vault, 'SenderNotAllowed');
  });

  describe('registration', () => {
    sharedBeforeEach('create pool', async () => {
      pool = await createPool(true);
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
      await expect(factory.connect(alice).create(wrappedToken, ONES_BYTES32)).to.be.revertedWithCustomError(
        vault,
        'WrappedTokenBufferAlreadyRegistered'
      );
    });

    it('configures the pool correctly', async () => {
      const currentTime = await currentTimestamp();
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.pauseWindowEndTime).to.gt(currentTime);
      expect(poolConfig.callbacks.shouldCallBeforeInitialize).to.be.true;
      expect(poolConfig.callbacks.shouldCallAfterInitialize).to.be.false;
      expect(poolConfig.callbacks.shouldCallBeforeAddLiquidity).to.be.true;
      expect(poolConfig.callbacks.shouldCallAfterAddLiquidity).to.be.false;
      expect(poolConfig.callbacks.shouldCallBeforeRemoveLiquidity).to.be.true;
      expect(poolConfig.callbacks.shouldCallAfterRemoveLiquidity).to.be.false;
      expect(poolConfig.callbacks.shouldCallBeforeSwap).to.be.true;
      expect(poolConfig.callbacks.shouldCallAfterSwap).to.be.false;
      expect(poolConfig.liquidityManagement.supportsAddLiquidityCustom).to.be.true;
      expect(poolConfig.liquidityManagement.supportsRemoveLiquidityCustom).to.be.false;
    });
  });

  describe('initialization', () => {
    sharedBeforeEach('create pool', async () => {
      pool = await createPool(true);

      wrappedToken.mint(TOKEN_AMOUNT, alice);
      baseToken.mint(alice, TOKEN_AMOUNT);

      wrappedToken.connect(alice).approve(vault, MAX_UINT256);
      baseToken.connect(alice).approve(vault, MAX_UINT256);
    });

    it('initializing emits an event and updates the state', async () => {
      // Preconditions
      expect(await wrappedToken.balanceOf(alice)).to.eq(TOKEN_AMOUNT);
      expect(await baseToken.balanceOf(alice)).to.eq(TOKEN_AMOUNT);

      // Cannot initialize disproportionately
      await expect(
        router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT * 2n, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      ).to.be.revertedWithCustomError(vault, 'CallbackFailed');

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

      const [, tokenTypes, balances, ,] = await vault.getPoolTokenInfo(pool);
      expect(tokenTypes).to.deep.equal([TOKEN_TYPE.ERC4626, TOKEN_TYPE.STANDARD]);
      expect(balances).to.deep.equal([TOKEN_AMOUNT, TOKEN_AMOUNT]);

      // Cannot initialize more than once
      await expect(
        router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      ).to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized');
    });
  });

  describe('remove liquidity', () => {
    sharedBeforeEach('create and initialize pool', async () => {
      pool = await createPool(true);

      wrappedToken.mint(TOKEN_AMOUNT, alice);
      baseToken.mint(alice, TOKEN_AMOUNT);

      wrappedToken.connect(alice).approve(vault, MAX_UINT256);
      baseToken.connect(alice).approve(vault, MAX_UINT256);

      await router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');
    });

    it('satisfies preconditions', async () => {
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;
      expect(await baseToken.balanceOf(alice)).to.eq(0);
      expect(await wrappedToken.balanceOf(alice)).to.eq(0);
    });

    context('invalid kinds', () => {
      it('cannot remove liquidity single token exact in', async () => {
        await expect(
          router.connect(alice).removeLiquiditySingleTokenExactIn(pool, TOKEN_AMOUNT, baseTokenAddress, 0, false, '0x')
        ).to.be.revertedWithCustomError(vault, 'InvalidRemoveLiquidityKind');
      });

      it('cannot remove liquidity single token exact out', async () => {
        await expect(
          router
            .connect(alice)
            .removeLiquiditySingleTokenExactOut(pool, TOKEN_AMOUNT, baseTokenAddress, TOKEN_AMOUNT, false, '0x')
        ).to.be.revertedWithCustomError(vault, 'InvalidRemoveLiquidityKind');
      });

      it('cannot remove liquidity custom', async () => {
        await expect(
          router.connect(alice).removeLiquidityCustom(pool, TOKEN_AMOUNT, [0, 0], false, '0x')
        ).to.be.revertedWithCustomError(vault, 'InvalidRemoveLiquidityKind');
      });
    });

    it('can remove liquidity proportionally', async () => {
      const bptAmountIn = await pool.balanceOf(alice);

      await router.connect(alice).removeLiquidityProportional(pool, bptAmountIn, [0, 0], false, '0x');

      expect(await pool.balanceOf(alice)).to.be.zero;
      expect(await baseToken.balanceOf(alice)).to.almostEqual(TOKEN_AMOUNT);
      expect(await wrappedToken.balanceOf(alice)).to.almostEqual(TOKEN_AMOUNT);
    });
  });
});
