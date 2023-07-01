import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH, fromNow } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { ERC20BalancerPoolToken } from '../typechain-types/contracts/ERC20BalancerPoolToken';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import '@balancer-labs/v3-common/setupTests';
import { bn } from '@balancer-labs/v3-helpers/src/numbers';
import { Typed } from 'ethers';

describe('Vault', function () {
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
  const ETH_SENTINEL = ZERO_ADDRESS;

  const BAL = '0xba100000625a3754423978a60c9317c58a424e3d';
  const DAI = '0x6b175474e89094c44da98b954eedeac495271d0f';
  const WBTC = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';

  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  let vault: VaultMock;
  let poolA: ERC20BalancerPoolToken;
  let poolB: ERC20BalancerPoolToken;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;

  let vaultAddress: string;

  let factory: SignerWithAddress;
  let user: SignerWithAddress;
  let other: SignerWithAddress;

  let tokenAAddress: string;
  let tokenBAddress: string;
  let tokenCAddress: string;

  let poolAAddress: string;
  let poolBAddress: string;

  let poolATokens: string[];

  before('setup signers', async () => {
    [, factory, user, other] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await deploy('VaultMock', { args: [WETH, PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION] });
    vaultAddress = await vault.getAddress();

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
    tokenC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

    poolA = await deploy('ERC20BalancerPoolToken', { args: [vaultAddress, 'Pool A', 'POOLA'] });
    poolB = await deploy('ERC20BalancerPoolToken', { args: [vaultAddress, 'Pool B', 'POOLB'] });

    expect(await poolA.name()).to.equal('Pool A');
    expect(await poolA.symbol()).to.equal('POOLA');
    expect(await poolA.decimals()).to.equal(18);
  });

  sharedBeforeEach('get addresses', async () => {
    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();
    tokenCAddress = await tokenC.getAddress();

    poolAAddress = await poolA.getAddress();
    poolBAddress = await poolB.getAddress();

    poolATokens = [tokenAAddress, tokenBAddress, tokenCAddress];
  });

  describe('registration', () => {
    it('can register a pool', async () => {
      await poolA.initialize(factory, poolATokens);

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
      await expect(await poolA.initialize(factory, poolATokens))
        .to.emit(vault, 'PoolRegistered')
        .withArgs(poolAAddress, factory.address, poolATokens);
    });

    it('cannot register a pool twice', async () => {
      await poolA.initialize(factory, poolATokens);

      await expect(poolA.initialize(factory, poolATokens))
        .to.be.revertedWithCustomError(vault, 'PoolAlreadyRegistered')
        .withArgs(poolAAddress);
    });

    it('cannot register a pool with an invalid token', async () => {
      await expect(
        poolA.initialize(factory, [tokenAAddress, tokenCAddress, ZERO_ADDRESS])
      ).to.be.revertedWithCustomError(vault, 'InvalidToken');
    });

    it('cannot register a pool with duplicate tokens', async () => {
      await expect(poolA.initialize(factory, [tokenAAddress, tokenBAddress, tokenAAddress]))
        .to.be.revertedWithCustomError(vault, 'TokenAlreadyRegistered')
        .withArgs(tokenAAddress);
    });

    it('cannot register a pool when paused', async () => {
      await vault.pause();

      await expect(poolA.initialize(factory, poolATokens)).to.be.revertedWithCustomError(vault, 'AlreadyPaused');
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

    it('cannot transfer from an invalid pool', async () => {
      await expect(vault.transfer(ANY_ADDRESS, user.address, other.address, 0))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(ANY_ADDRESS);
      await expect(vault.transferFrom(ANY_ADDRESS, user.address, user.address, other.address, 0))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(ANY_ADDRESS);
    });

    it('cannot approve an invalid pool', async () => {
      await expect(vault.approve(ANY_ADDRESS, user.address, other.address, 0))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(ANY_ADDRESS);
    });
  });

  describe('native ETH handling', () => {
    it('detects the ETH asset', async () => {
      expect(await vault.isETH(ETH_SENTINEL)).to.be.true;
      expect(await vault.isETH(ANY_ADDRESS)).to.be.false;
    });

    it('translates native ETH', async () => {
      expect(await vault.translateToIERC20(Typed.address(ETH_SENTINEL))).to.equal(WETH);
      expect(await vault.translateToIERC20(Typed.address(ANY_ADDRESS))).to.equal(ANY_ADDRESS);
    });

    it('translates an array of tokens', async () => {
      const tokensIn = [WETH, BAL, ETH_SENTINEL, DAI, WBTC];
      const tokensOut = [WETH, BAL, WETH, DAI, WBTC];

      expect(await vault['translateToIERC20(address[])'](tokensIn)).to.deep.equal(tokensOut);
    });
  });

  describe('initialization', () => {
    let timedVault: VaultMock;

    sharedBeforeEach('redeploy Vault', async () => {
      timedVault = await deploy('VaultMock', { args: [WETH, PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION] });
    });

    it('initializes WETH', async () => {
      expect(await timedVault.WETH()).to.equal(WETH);
    });

    it('is temporarily pausable', async () => {
      expect(await timedVault.paused()).to.equal(false);

      const [pauseWindowEndTime, bufferPeriodEndTime] = await timedVault.getPauseEndTimes();
      expect(pauseWindowEndTime).to.equal(await fromNow(PAUSE_WINDOW_DURATION));
      expect(bufferPeriodEndTime).to.equal((await fromNow(PAUSE_WINDOW_DURATION)) + bn(BUFFER_PERIOD_DURATION));
    });
  });
});
