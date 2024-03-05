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
import { ANY_ADDRESS, MAX_UINT256, ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';
import { PoolConfigStructOutput, VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { FP_ONE, FP_ZERO, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';

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
  let factoryAddress: string;
  let tokenAddresses: string[];

  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let pool: Contract;

  before('setup signers', async () => {
    [, alice, bob] = await ethers.getSigners();
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
    factoryAddress = await factory.getAddress();
  });

  async function createBufferPool(): Promise<Contract> {
    // initialize assets and supply
    await baseToken.mint(wrappedToken, TOKEN_AMOUNT);
    await wrappedToken.mint(TOKEN_AMOUNT, alice);

    const tx = await factory.connect(alice).create(wrappedToken, ANY_ADDRESS, ZERO_BYTES32);
    const receipt = await tx.wait();

    const event = expectEvent.inReceipt(receipt, 'PoolCreated');

    const poolAddress = event.args.pool;

    return await deployedAt('ERC4626BufferPool', poolAddress);
  }

  async function createAndInitializeBufferPool(): Promise<Contract> {
    await grantFactoryPermissions();
    await vault.connect(alice).registerBufferPoolFactory(factory);

    pool = await createBufferPool();

    await baseToken.mint(alice, TOKEN_AMOUNT);

    wrappedToken.connect(alice).approve(vault, MAX_UINT256);
    baseToken.connect(alice).approve(vault, MAX_UINT256);

    await router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');

    return pool;
  }

  async function grantFactoryPermissions() {
    const registerFactoryAction = await actionId(vault, 'registerBufferPoolFactory');
    const deregisterFactoryAction = await actionId(vault, 'deregisterBufferPoolFactory');

    await authorizer.grantRole(registerFactoryAction, alice.address);
    await authorizer.grantRole(deregisterFactoryAction, alice.address);
  }

  describe('factory permissions', () => {
    context('without permission', () => {
      it('cannot register a pool', async () => {
        await expect(createBufferPool()).to.be.revertedWithCustomError(vault, 'UnregisteredBufferPoolFactory');
      });
    });

    context('with permission', () => {
      sharedBeforeEach('grant permission', async () => {
        await grantFactoryPermissions();
      });

      it('can register a buffer pool factory', async () => {
        expect(await vault.connect(alice).registerBufferPoolFactory(factory)).to.not.be.reverted;
      });

      it('cannot register a buffer pool factory twice', async () => {
        await vault.connect(alice).registerBufferPoolFactory(factory);

        await expect(vault.connect(alice).registerBufferPoolFactory(factory)).to.be.revertedWithCustomError(
          vault,
          'BufferPoolFactoryAlreadyRegistered'
        );
      });

      it('can deregister a buffer pool factory', async () => {
        await vault.connect(alice).registerBufferPoolFactory(factory);

        expect(await vault.connect(alice).deregisterBufferPoolFactory(factory)).to.not.be.reverted;
      });

      it('cannot deregister an unregistered buffer pool factory', async () => {
        await expect(vault.connect(alice).deregisterBufferPoolFactory(ANY_ADDRESS)).to.be.revertedWithCustomError(
          vault,
          'BufferPoolFactoryNotRegistered'
        );
      });
    });
  });

  describe('events', () => {
    sharedBeforeEach('grant permission', async () => {
      await grantFactoryPermissions();
    });

    it('factory registration emits an event', async () => {
      await expect(vault.connect(alice).registerBufferPoolFactory(factory))
        .to.emit(vault, 'BufferPoolFactoryRegistered')
        .withArgs(factoryAddress);
    });

    it('factory deregistration emits an event', async () => {
      await vault.connect(alice).registerBufferPoolFactory(factory);

      await expect(vault.connect(alice).deregisterBufferPoolFactory(factory))
        .to.emit(vault, 'BufferPoolFactoryDeregistered')
        .withArgs(factoryAddress);
    });

    it('buffer creation emits an event', async () => {
      await vault.connect(alice).registerBufferPoolFactory(factory);

      expect(await createBufferPool())
        .to.emit(vault, 'WrappedTokenBufferCreated')
        .withArgs(wrappedTokenAddress, baseTokenAddress);
    });
  });

  describe('registration', () => {
    sharedBeforeEach('register factory and create pool', async () => {
      await grantFactoryPermissions();
      await vault.connect(alice).registerBufferPoolFactory(factory);

      pool = await createBufferPool();
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
      expect(poolConfig.isBufferPool).to.be.true;
    });

    it('has the correct tokens', async () => {
      const actualTokens = await vault.getPoolTokens(pool);

      expect(actualTokens).to.deep.equal(tokenAddresses);
    });

    it('configures the pool correctly', async () => {
      const currentTime = await currentTimestamp();
      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      const [paused, , , pauseManager] = await vault.getPoolPausedState(pool);
      expect(paused).to.be.false;
      expect(pauseManager).to.eq(ANY_ADDRESS);

      expect(poolConfig.pauseWindowEndTime).to.gt(currentTime);
      expect(poolConfig.hooks.shouldCallBeforeInitialize).to.be.true;
      expect(poolConfig.hooks.shouldCallAfterInitialize).to.be.false;
      expect(poolConfig.hooks.shouldCallBeforeAddLiquidity).to.be.true;
      expect(poolConfig.hooks.shouldCallAfterAddLiquidity).to.be.false;
      expect(poolConfig.hooks.shouldCallBeforeRemoveLiquidity).to.be.true;
      expect(poolConfig.hooks.shouldCallAfterRemoveLiquidity).to.be.false;
      expect(poolConfig.hooks.shouldCallBeforeSwap).to.be.true;
      expect(poolConfig.hooks.shouldCallAfterSwap).to.be.false;
      expect(poolConfig.liquidityManagement.supportsAddLiquidityCustom).to.be.true;
      expect(poolConfig.liquidityManagement.supportsRemoveLiquidityCustom).to.be.false;
    });
  });

  describe('initialization', () => {
    sharedBeforeEach('create pool', async () => {
      await grantFactoryPermissions();
      await vault.connect(alice).registerBufferPoolFactory(factory);

      pool = await createBufferPool();

      await baseToken.mint(alice, TOKEN_AMOUNT);

      await wrappedToken.connect(alice).approve(vault, MAX_UINT256);
      await baseToken.connect(alice).approve(vault, MAX_UINT256);
    });

    it('satisfies preconditions', async () => {
      expect(await wrappedToken.balanceOf(alice)).to.eq(TOKEN_AMOUNT);
      expect(await baseToken.balanceOf(alice)).to.eq(TOKEN_AMOUNT);
    });

    it('cannot be initialized disproportionately', async () => {
      // Cannot initialize disproportionately
      await expect(
        router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT * 2n, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      ).to.be.revertedWithCustomError(vault, 'BeforeInitializeHookFailed');
    });

    it('emits an event', async () => {
      expect(
        await router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      )
        .to.emit(vault, 'PoolInitialized')
        .withArgs(pool);
    });

    it('updates the state', async () => {
      await router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');

      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(pool);

      expect(poolConfig.isPoolRegistered).to.be.true;
      expect(poolConfig.isPoolInitialized).to.be.true;

      expect(await pool.balanceOf(alice)).to.eq(TOKEN_AMOUNT * 2n - MIN_BPT);
      expect(await wrappedToken.balanceOf(alice)).to.eq(0);
      expect(await baseToken.balanceOf(alice)).to.eq(0);

      const [, tokenTypes, balances, ,] = await vault.getPoolTokenInfo(pool);
      expect(tokenTypes).to.deep.equal([TokenType.ERC4626, TokenType.STANDARD]);
      expect(balances).to.deep.equal([TOKEN_AMOUNT, TOKEN_AMOUNT]);
    });

    it('cannot be initialized twice', async () => {
      await router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x');
      await expect(
        router.connect(alice).initialize(pool, tokenAddresses, [TOKEN_AMOUNT, TOKEN_AMOUNT], FP_ZERO, false, '0x')
      ).to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized');
    });
  });

  describe('swaps', () => {
    sharedBeforeEach('create and initialize pool', async () => {
      pool = await createAndInitializeBufferPool();
    });

    it('does not allow buffer pool swaps through a router', async () => {
      await expect(
        router
          .connect(alice)
          .swapSingleTokenExactIn(
            pool,
            baseTokenAddress,
            wrappedTokenAddress,
            TOKEN_AMOUNT,
            0,
            MAX_UINT256,
            false,
            '0x'
          )
      )
        .to.be.revertedWithCustomError(vault, 'CannotSwapWithBufferPool')
        .withArgs(await pool.getAddress());
    });

    it('does not allow external swaps', async () => {
      await expect(
        pool.connect(alice).onSwap({
          kind: 0,
          amountGivenScaled18: FP_ONE,
          balancesScaled18: [FP_ONE, FP_ONE],
          indexIn: 0,
          indexOut: 1,
          sender: alice,
          userData: '0x',
        })
      ).to.be.revertedWithCustomError(vault, 'SenderIsNotVault');
    });
  });

  describe('rebalancing', () => {
    sharedBeforeEach('create and initialize pool', async () => {
      pool = await createAndInitializeBufferPool();
    });

    context('without permission', () => {
      it('calls to rebalance revert without permission', async () => {
        await expect(pool.connect(alice).rebalance()).to.be.revertedWithCustomError(vault, 'SenderNotAllowed');
      });
    });

    context('with permission', () => {
      sharedBeforeEach('grant permission', async () => {
        const rebalanceAction = await actionId(pool, 'rebalance');

        await authorizer.grantRole(rebalanceAction, alice.address);
      });

      it('can rebalance a buffer pool', async () => {
        // TODO: Add real tests once it is implemented.
        await expect(pool.connect(alice).rebalance()).to.not.be.reverted;
      });
    });
  });

  describe('add liquidity', () => {
    sharedBeforeEach('create and initialize pool', async () => {
      pool = await createAndInitializeBufferPool();
    });

    context('invalid kinds', () => {
      it('cannot add liquidity unbalanced', async () => {
        await expect(
          router.connect(alice).addLiquidityUnbalanced(pool, [0, TOKEN_AMOUNT], 0, false, '0x')
        ).to.be.revertedWithCustomError(vault, 'BeforeAddLiquidityHookFailed');
      });

      it('cannot add liquidity single token exact out', async () => {
        await expect(
          router
            .connect(alice)
            .addLiquiditySingleTokenExactOut(pool, baseTokenAddress, TOKEN_AMOUNT, TOKEN_AMOUNT, false, '0x')
        ).to.be.revertedWithCustomError(vault, 'BeforeAddLiquidityHookFailed');
      });
    });

    it('can add liquidity custom', async () => {
      wrappedToken.mint(TOKEN_AMOUNT + MIN_BPT, bob);
      baseToken.mint(bob, TOKEN_AMOUNT + MIN_BPT);

      wrappedToken.connect(bob).approve(vault, MAX_UINT256);
      baseToken.connect(bob).approve(vault, MAX_UINT256);

      const bptAmount = await pool.balanceOf(alice);
      const MAX_AMOUNT = TOKEN_AMOUNT + MIN_BPT;

      await router.connect(bob).addLiquidityCustom(pool, [MAX_AMOUNT, MAX_AMOUNT], bptAmount, false, '0x');
    });
  });

  describe('remove liquidity', () => {
    sharedBeforeEach('create and initialize pool', async () => {
      pool = await createAndInitializeBufferPool();
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
        ).to.be.revertedWithCustomError(vault, 'BeforeRemoveLiquidityHookFailed');
      });

      it('cannot remove liquidity single token exact out', async () => {
        await expect(
          router
            .connect(alice)
            .removeLiquiditySingleTokenExactOut(pool, TOKEN_AMOUNT, baseTokenAddress, TOKEN_AMOUNT, false, '0x')
        ).to.be.revertedWithCustomError(vault, 'BeforeRemoveLiquidityHookFailed');
      });

      it('cannot remove liquidity custom', async () => {
        await expect(
          router.connect(alice).removeLiquidityCustom(pool, TOKEN_AMOUNT, [0, 0], false, '0x')
        ).to.be.revertedWithCustomError(vault, 'BeforeRemoveLiquidityHookFailed');
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
