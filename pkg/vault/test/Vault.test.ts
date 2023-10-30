import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH, fromNow } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { ERC20BalancerPoolToken } from '../typechain-types/contracts/ERC20BalancerPoolToken';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/BasicAuthorizerMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { bn } from '@balancer-labs/v3-helpers/src/numbers';
import { setupEnvironment } from './poolSetup';
import { impersonate } from '@balancer-labs/v3-helpers/src/signers';
import { NullAuthorizer } from '../typechain-types/contracts/test/NullAuthorizer';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import '@balancer-labs/v3-common/setupTests';

describe('Vault', function () {
  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  let vault: VaultMock;
  let poolA: ERC20BalancerPoolToken;
  let poolB: ERC20BalancerPoolToken;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;

  let factory: SignerWithAddress;
  let alice: SignerWithAddress;

  let tokenAAddress: string;
  let tokenBAddress: string;

  let poolAAddress: string;
  let poolBAddress: string;

  let poolATokens: string[];
  let poolBTokens: string[];
  let invalidTokens: string[];
  let duplicateTokens: string[];

  before('setup signers', async () => {
    [, factory, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    const { vault: vaultMock, tokens, pools } = await setupEnvironment(factory.address);

    vault = vaultMock;

    tokenA = tokens[0];
    tokenB = tokens[1];
    tokenC = tokens[2];

    poolA = pools[0]; // This pool is registered
    poolB = pools[1]; // This pool is unregistered

    poolAAddress = await poolA.getAddress();
    poolBAddress = await poolB.getAddress();

    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();

    const tokenCAddress = await tokenC.getAddress();
    poolATokens = [tokenAAddress, tokenBAddress, tokenCAddress];
    poolBTokens = [tokenAAddress, tokenCAddress];
    invalidTokens = [tokenAAddress, ZERO_ADDRESS, tokenCAddress];
    duplicateTokens = [tokenAAddress, tokenBAddress, tokenAAddress];

    expect(await poolA.name()).to.equal('Pool A');
    expect(await poolA.symbol()).to.equal('POOLA');
    expect(await poolA.decimals()).to.equal(18);

    expect(await poolB.name()).to.equal('Pool B');
    expect(await poolB.symbol()).to.equal('POOLB');
    expect(await poolB.decimals()).to.equal(18);
  });

  describe('registration', () => {
    let unregisteredPoolSigner: SignerWithAddress;

    sharedBeforeEach('get pool signer for calls through vault', async () => {
      // PoolB isn't registered
      unregisteredPoolSigner = await impersonate(poolBAddress);
    });

    it('can register a pool', async () => {
      expect(await vault.isRegisteredPool(poolAAddress)).to.be.true;
      expect(await vault.isRegisteredPool(poolBAddress)).to.be.false;

      const { tokens, balances } = await vault.getPoolTokens(poolAAddress);
      expect(tokens).to.deep.equal(poolATokens);
      expect(balances).to.deep.equal(Array(tokens.length).fill(0));

      await expect(vault.getPoolTokens(poolBAddress))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(poolBAddress);
    });

    it('registering a pool emits an event', async () => {
      await expect(await vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, poolBTokens))
        .to.emit(vault, 'PoolRegistered')
        .withArgs(
          poolBAddress,
          factory.address,
          poolBTokens,
          [false, false, false, false, false],
          [true, true, true, true, true, true],
          [true, true]
        );
    });

    it('cannot register a pool twice', async () => {
      await vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, poolBTokens);

      await expect(vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, poolBTokens))
        .to.be.revertedWithCustomError(vault, 'PoolAlreadyRegistered')
        .withArgs(poolBAddress);
    });

    it('cannot register a pool with an invalid token', async () => {
      await expect(
        vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, invalidTokens)
      ).to.be.revertedWithCustomError(vault, 'InvalidToken');
    });

    it('cannot register a pool with duplicate tokens', async () => {
      await expect(vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, duplicateTokens))
        .to.be.revertedWithCustomError(vault, 'TokenAlreadyRegistered')
        .withArgs(tokenAAddress);
    });

    it('cannot register a pool when paused', async () => {
      await vault.pause();

      await expect(
        vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, poolBTokens)
      ).to.be.revertedWithCustomError(vault, 'AlreadyPaused');
    });

    it('cannot register while registering another pool', async () => {
      await expect(vault.reentrantRegisterPool(factory, poolATokens)).to.be.revertedWithCustomError(
        vault,
        'ReentrancyGuardReentrantCall'
      );
    });

    it('cannot get pool tokens for an invalid pool', async () => {
      await expect(vault.getPoolTokens(ANY_ADDRESS))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(ANY_ADDRESS);
    });

    it('cannot register a pool with too few tokens', async () => {
      await expect(
        vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, [poolATokens[0]])
      ).to.be.revertedWithCustomError(vault, 'MinTokens');
    });

    it('cannot register a pool with too many tokens', async () => {
      const tokens = await ERC20TokenList.create(5);

      await expect(
        vault.connect(unregisteredPoolSigner).manualRegisterPool(factory.address, await tokens.addresses)
      ).to.be.revertedWithCustomError(vault, 'MaxTokens');
    });
  });

  describe('initialization', () => {
    let authorizer: BasicAuthorizerMock;
    let timedVault: VaultMock;

    sharedBeforeEach('redeploy Vault', async () => {
      authorizer = await deploy('v3-solidity-utils/BasicAuthorizerMock');
      timedVault = await deploy('VaultMock', {
        args: [authorizer.getAddress(), PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION],
      });
    });

    it('is temporarily pausable', async () => {
      expect(await timedVault.paused()).to.equal(false);

      const [pauseWindowEndTime, bufferPeriodEndTime] = await timedVault.getPauseEndTimes();
      expect(pauseWindowEndTime).to.equal(await fromNow(PAUSE_WINDOW_DURATION));
      expect(bufferPeriodEndTime).to.equal((await fromNow(PAUSE_WINDOW_DURATION)) + bn(BUFFER_PERIOD_DURATION));
    });
  });

  describe('authorizer', () => {
    let oldAuthorizer: Contract;
    let newAuthorizer: NullAuthorizer;
    let oldAuthorizerAddress: string;

    sharedBeforeEach('get old and deploy new authorizer', async () => {
      oldAuthorizerAddress = await vault.getAuthorizer();
      oldAuthorizer = await deployedAt('v3-solidity-utils/BasicAuthorizerMock', oldAuthorizerAddress);

      newAuthorizer = await deploy('NullAuthorizer');
    });

    context('without permission', () => {
      it('cannot change authorizer', async () => {
        await expect(vault.setAuthorizer(await newAuthorizer.getAddress())).to.be.revertedWithCustomError(
          vault,
          'SenderNotAllowed'
        );
      });
    });

    context('with permission', () => {
      let newAuthorizerAddress: string;

      sharedBeforeEach('grant permission', async () => {
        const setAuthorizerAction = await actionId(vault, 'setAuthorizer');

        await oldAuthorizer.grantRole(setAuthorizerAction, alice.address);
      });

      it('can change authorizer', async () => {
        newAuthorizerAddress = await newAuthorizer.getAddress();

        await expect(await vault.connect(alice).setAuthorizer(newAuthorizerAddress))
          .to.emit(vault, 'AuthorizerChanged')
          .withArgs(newAuthorizerAddress);

        expect(await vault.getAuthorizer()).to.equal(newAuthorizerAddress);
      });

      it('the null authorizer allows everything', async () => {
        await vault.connect(alice).setAuthorizer(newAuthorizerAddress);

        await vault.setAuthorizer(oldAuthorizerAddress);

        expect(await vault.getAuthorizer()).to.equal(oldAuthorizerAddress);
      });
    });
  });

  describe('pool tokens', () => {
    it('returns the min and max pool counts', async () => {
      const minTokens = await vault.getMinimumPoolTokens();
      const maxTokens = await vault.getMaximumPoolTokens();

      expect(minTokens).to.eq(2);
      expect(maxTokens).to.eq(4);
    });
  });
});
