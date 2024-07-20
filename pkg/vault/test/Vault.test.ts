import { expect } from 'chai';
import { Contract } from 'ethers';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH, currentTimestamp, fromNow } from '@balancer-labs/v3-helpers/src/time';
import { PoolConfigStructOutput } from '../typechain-types/contracts/test/VaultMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { ANY_ADDRESS, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { FP_ONE, bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { buildTokenConfig, setupEnvironment } from './poolSetup';
import { NullAuthorizer } from '../typechain-types/contracts/test/NullAuthorizer';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import { PoolFactoryMock, RateProviderMock, VaultExtensionMock } from '../typechain-types';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { TokenType } from '@balancer-labs/v3-helpers/src/models/types/types';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { PoolRoleAccountsStruct } from '../typechain-types/contracts/Vault';

describe('Vault', function () {
  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;
  const POOL_SWAP_FEE = fp(0.01);
  const MAX_TOKENS = 8;

  let vault: IVaultMock;
  let vaultExtension: VaultExtensionMock;
  let factory: PoolFactoryMock;

  let poolA: PoolMock;
  let poolB: PoolMock;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;

  let tokenAAddress: string;
  let tokenBAddress: string;
  let poolBAddress: string;

  let poolATokens: string[];
  let poolBTokens: string[];
  let invalidTokens: string[];
  let duplicateTokens: string[];
  let unsortedTokens: string[];

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    const { vault: vaultMock, tokens, pools } = await setupEnvironment(PAUSE_WINDOW_DURATION);

    vault = vaultMock;
    vaultExtension = (await deployedAt(
      'VaultExtensionMock',
      await vault.getVaultExtension()
    )) as unknown as VaultExtensionMock;

    factory = await deploy('PoolFactoryMock', { args: [vault, 12 * MONTH] });

    tokenA = tokens[0];
    tokenB = tokens[1];
    tokenC = tokens[2];

    poolA = pools[0]; // This pool is registered
    poolB = pools[1]; // This pool is unregistered

    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();
    poolBAddress = await poolB.getAddress();

    const tokenCAddress = await tokenC.getAddress();
    poolATokens = sortAddresses([tokenAAddress, tokenBAddress, tokenCAddress]);
    poolBTokens = sortAddresses([tokenAAddress, tokenCAddress]);
    invalidTokens = sortAddresses([tokenAAddress, ZERO_ADDRESS, tokenCAddress]);
    duplicateTokens = sortAddresses([tokenAAddress, tokenBAddress, tokenAAddress]);

    // Copy and reverse A tokens.
    unsortedTokens = Array.from(poolATokens);
    unsortedTokens.reverse();

    expect(await poolA.name()).to.equal('Pool A');
    expect(await poolA.symbol()).to.equal('POOL-A');
    expect(await poolA.decimals()).to.equal(18);

    expect(await poolB.name()).to.equal('Pool B');
    expect(await poolB.symbol()).to.equal('POOL-B');
    expect(await poolB.decimals()).to.equal(18);
  });

  describe('registration', () => {
    it('cannot register a pool with unsorted tokens', async () => {
      await expect(vault.manualRegisterPoolPassThruTokens(poolB, unsortedTokens)).to.be.revertedWithCustomError(
        vaultExtension,
        'TokensNotSorted'
      );
    });

    it('can register a pool', async () => {
      expect(await vault.isPoolRegistered(poolA)).to.be.true;
      expect(await vault.isPoolRegistered(poolB)).to.be.false;

      const [tokens, , balances] = await vault.getPoolTokenInfo(poolA);

      expect(tokens).to.deep.equal(poolATokens);
      expect(balances).to.deep.equal(Array(tokens.length).fill(0));

      await expect(vault.getPoolTokens(poolB))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(poolBAddress);
    });

    it('pools are initially not in recovery mode', async () => {
      expect(await vault.isPoolInRecoveryMode(poolA)).to.be.false;
    });

    it('pools are initially unpaused', async () => {
      expect(await vault.isPoolPaused(poolA)).to.equal(false);
    });

    it('registering a pool emits an event', async () => {
      const tokenConfig = Array.from({ length: poolBTokens.length }, (_, i) => [
        poolBTokens[i],
        TokenType.STANDARD.toString(),
        ZERO_ADDRESS,
        false,
      ]);

      const currentTime = await currentTimestamp();
      const pauseWindowEndTime = Number(currentTime) + PAUSE_WINDOW_DURATION;

      const expectedArgs = {
        pool: poolBAddress,
        factory: await vault.getPoolFactoryMock(),
        tokenConfig,
        swapFeePercentage: 0,
        pauseWindowEndTime: pauseWindowEndTime.toString(),
        roleAccounts: [ANY_ADDRESS, ZERO_ADDRESS, ANY_ADDRESS],
        hooksConfig: [false, false, false, false, false, false, false, false, false, false, ZERO_ADDRESS],
        liquidityManagement: [false, true, true, false],
      };

      const roleAccounts: PoolRoleAccountsStruct = {
        pauseManager: ANY_ADDRESS,
        swapFeeManager: ZERO_ADDRESS,
        poolCreator: ANY_ADDRESS,
      };

      // Use expectEvent here to prevent errors with structs of arrays with hardhat matchers.
      const tx = await vault.manualRegisterPoolAtTimestamp(poolB, poolBTokens, pauseWindowEndTime, roleAccounts);
      const receipt = await tx.wait();

      expectEvent.inReceipt(receipt, 'PoolRegistered', expectedArgs);
    });

    it('registering a pool with a swap fee emits an event', async () => {
      await expect(vault.manualRegisterPoolWithSwapFee(poolB, poolBTokens, POOL_SWAP_FEE))
        .to.emit(vault, 'SwapFeePercentageChanged')
        .withArgs(poolBAddress, POOL_SWAP_FEE);
    });

    it('cannot register a pool twice', async () => {
      await vault.manualRegisterPool(poolB, poolBTokens);

      await expect(vault.manualRegisterPool(poolB, poolBTokens))
        .to.be.revertedWithCustomError(vaultExtension, 'PoolAlreadyRegistered')
        .withArgs(await poolB.getAddress());
    });

    it('cannot register a pool with an invalid token (zero address)', async () => {
      await expect(vault.manualRegisterPool(poolB, invalidTokens)).to.be.revertedWithCustomError(
        vaultExtension,
        'InvalidToken'
      );
    });

    it('cannot register a pool with an invalid token (pool address)', async () => {
      const poolBTokensWithItself = Array.from(poolBTokens);
      poolBTokensWithItself.push(poolBAddress);

      const finalTokens = sortAddresses(poolBTokensWithItself);

      await expect(vault.manualRegisterPool(poolB, finalTokens)).to.be.revertedWithCustomError(
        vaultExtension,
        'InvalidToken'
      );
    });

    it('cannot register a pool with duplicate tokens', async () => {
      await expect(vault.manualRegisterPool(poolB, duplicateTokens))
        .to.be.revertedWithCustomError(vaultExtension, 'TokenAlreadyRegistered')
        .withArgs(tokenAAddress);
    });

    it('cannot register a pool when paused', async () => {
      await vault.manualPauseVault();

      await expect(vault.manualRegisterPool(poolB, poolBTokens)).to.be.revertedWithCustomError(vault, 'VaultPaused');
    });

    it('cannot get pool tokens for an invalid pool', async () => {
      await expect(vault.getPoolTokens(ANY_ADDRESS))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(ANY_ADDRESS);
    });

    it('cannot register a pool with too few tokens', async () => {
      await expect(vault.manualRegisterPool(poolB, [poolATokens[0]])).to.be.revertedWithCustomError(
        vaultExtension,
        'MinTokens'
      );
    });

    it('cannot register a pool with too many tokens', async () => {
      const tokens = await ERC20TokenList.create(MAX_TOKENS + 1, { sorted: true });

      await expect(vault.manualRegisterPool(poolB, await tokens.addresses)).to.be.revertedWithCustomError(
        vaultExtension,
        'MaxTokens'
      );
    });
  });

  describe('initialization', () => {
    let timedVault: IVaultMock;

    sharedBeforeEach('redeploy Vault', async () => {
      const timedVaultMock = await VaultDeployer.deployMock({
        pauseWindowDuration: PAUSE_WINDOW_DURATION,
        bufferPeriodDuration: BUFFER_PERIOD_DURATION,
      });
      timedVault = await TypesConverter.toIVaultMock(timedVaultMock);
    });

    it('is temporarily pausable', async () => {
      expect(await timedVault.isVaultPaused()).to.equal(false);

      const [paused, pauseWindowEndTime, bufferPeriodEndTime] = await timedVault.getVaultPausedState();

      expect(paused).to.be.false;
      // We subtract 3 because the timestamp is set when the extension is deployed.
      // Each contract deployment pushes the timestamp by 1, and the main Vault is deployed right after the extension,
      // vault admin, and protocol fee controller.
      expect(pauseWindowEndTime).to.equal(await fromNow(PAUSE_WINDOW_DURATION - 3));
      expect(bufferPeriodEndTime).to.equal((await fromNow(PAUSE_WINDOW_DURATION - 3)) + bn(BUFFER_PERIOD_DURATION));

      await timedVault.manualPauseVault();
      expect(await timedVault.isVaultPaused()).to.be.true;

      await timedVault.manualUnpauseVault();
      expect(await timedVault.isVaultPaused()).to.be.false;
    });

    it('pausing the Vault emits an event', async () => {
      await expect(await timedVault.manualPauseVault())
        .to.emit(timedVault, 'VaultPausedStateChanged')
        .withArgs(true);

      await expect(await timedVault.manualUnpauseVault())
        .to.emit(timedVault, 'VaultPausedStateChanged')
        .withArgs(false);
    });

    describe('rate providers', () => {
      let poolC: PoolMock;
      let rateProviders: string[];
      let expectedRates: bigint[];
      let rateProvider: RateProviderMock;

      sharedBeforeEach('deploy pool', async () => {
        rateProviders = Array(poolATokens.length).fill(ZERO_ADDRESS);
        rateProvider = await deploy('v3-vault/RateProviderMock');
        rateProviders[0] = await rateProvider.getAddress();
        expectedRates = Array(poolATokens.length).fill(FP_ONE);

        poolC = await deploy('v3-vault/PoolMock', {
          args: [vault, 'Pool C', 'POOLC'],
        });

        await factory.registerTestPool(poolC, buildTokenConfig(poolATokens, rateProviders));
      });

      it('has rate providers', async () => {
        const [, tokenInfo] = await vault.getPoolTokenInfo(poolC);
        const poolProviders = tokenInfo.map((config) => config.rateProvider);
        const { tokenRates } = await vault.getPoolTokenRates(poolC);

        expect(poolProviders).to.deep.equal(rateProviders);
        expect(tokenRates).to.deep.equal(expectedRates);
      });

      it('rate providers respond to changing rates', async () => {
        const newRate = fp(0.5);

        await rateProvider.mockRate(newRate);
        expectedRates[0] = newRate;

        const { tokenRates } = await vault.getPoolTokenRates(poolC);
        expect(tokenRates).to.deep.equal(expectedRates);
      });
    });

    describe('pausing pools', () => {
      let pool: PoolMock;
      let poolAddress: string;

      sharedBeforeEach('deploy pool', async () => {
        pool = await deploy('v3-vault/PoolMock', {
          args: [vault, 'Pool X', 'POOLX'],
        });
        poolAddress = await pool.getAddress();

        await factory.registerTestPool(poolAddress, buildTokenConfig(poolATokens));
      });

      it('Pools are temporarily pausable', async () => {
        expect(await vault.isPoolPaused(poolAddress)).to.equal(false);

        const paused = await vault.isPoolPaused(poolAddress);
        expect(paused).to.be.false;

        await vault.manualPausePool(poolAddress);
        expect(await vault.isPoolPaused(poolAddress)).to.be.true;

        await vault.manualUnpausePool(poolAddress);
        expect(await vault.isPoolPaused(poolAddress)).to.be.false;
      });

      it('pausing a pool emits an event', async () => {
        await expect(await vault.manualPausePool(poolAddress))
          .to.emit(vault, 'PoolPausedStateChanged')
          .withArgs(poolAddress, true);

        await expect(await vault.manualUnpausePool(poolAddress))
          .to.emit(vault, 'PoolPausedStateChanged')
          .withArgs(poolAddress, false);
      });
    });
  });

  describe('authorizer', () => {
    let newAuthorizer: NullAuthorizer;
    let oldAuthorizerAddress: string;
    let v2Vault: Contract;

    sharedBeforeEach('get old and deploy new authorizer', async () => {
      oldAuthorizerAddress = await vault.getAuthorizer();
      newAuthorizer = await deploy('NullAuthorizer');

      const v2VaultAddress = await vault.getV2Vault();
      v2Vault = await deployedAt('v3-vault/V2VaultMock', v2VaultAddress);
    });

    context('from v2 Vault', () => {
      let newAuthorizerAddress: string;

      it('has the current authorizer address', async () => {
        expect(await vault.getAuthorizer()).to.equal(oldAuthorizerAddress);
      });

      it('can change authorizer', async () => {
        newAuthorizerAddress = await newAuthorizer.getAddress();

        // Set the address in the v2 Vault.
        await v2Vault.setAuthorizer(newAuthorizerAddress);

        await expect(await vault.updateAuthorizer())
          .to.emit(vault, 'AuthorizerChanged')
          .withArgs(newAuthorizerAddress);

        expect(await vault.getAuthorizer()).to.equal(newAuthorizerAddress);
      });
    });
  });

  describe('pool tokens', () => {
    const DECIMAL_DIFF_BITS = 5;

    function decodeDecimalDiffs(diff: number, numTokens: number): number[] {
      const result: number[] = [];

      for (let i = 0; i < numTokens; i++) {
        // Compute the 5-bit mask for each token
        const mask = (2 ** DECIMAL_DIFF_BITS - 1) << (i * DECIMAL_DIFF_BITS);
        // Logical AND with the input, and shift back down to get the final result
        result[i] = (diff & mask) >> (i * DECIMAL_DIFF_BITS);
      }

      return result;
    }

    it('returns the min and max pool counts', async () => {
      const minTokens = await vault.getMinimumPoolTokens();
      const maxTokens = await vault.getMaximumPoolTokens();

      expect(minTokens).to.eq(2);
      expect(maxTokens).to.eq(MAX_TOKENS);
    });

    it('stores the decimal differences', async () => {
      const expectedDecimals = await Promise.all(
        poolATokens.map(async (token) => (await deployedAt('v3-solidity-utils/ERC20TestToken', token)).decimals())
      );
      const expectedDecimalDiffs = expectedDecimals.map((d) => bn(18) - d);

      const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(poolA);
      const actualDecimalDiffs = decodeDecimalDiffs(Number(poolConfig.tokenDecimalDiffs), poolATokens.length);

      expect(actualDecimalDiffs).to.deep.equal(expectedDecimalDiffs);
    });

    it('computes the scaling factors', async () => {
      // Get them from the pool (mock), using ScalingHelpers
      const poolScalingFactors = await poolA.getDecimalScalingFactors();
      // Get them from the Vault (using PoolConfig)
      const { decimalScalingFactors } = await vault.getPoolTokenRates(poolA);

      expect(decimalScalingFactors).to.deep.equal(poolScalingFactors);
    });
  });

  describe('recovery mode', () => {
    sharedBeforeEach('register pool', async () => {
      await vault.manualRegisterPool(poolB, poolBTokens);
    });

    it('enable/disable functions are permissioned', async () => {
      await expect(vault.enableRecoveryMode(poolB)).to.be.revertedWithCustomError(vault, 'SenderNotAllowed');
      await expect(vault.disableRecoveryMode(poolB)).to.be.revertedWithCustomError(vault, 'SenderNotAllowed');
    });

    context('in recovery mode', () => {
      sharedBeforeEach('put pool in recovery mode', async () => {
        await vault.manualEnableRecoveryMode(poolB);
      });

      it('can place pool in recovery mode', async () => {
        expect(await vault.isPoolInRecoveryMode(poolB)).to.be.true;
      });

      it('cannot put in recovery mode twice', async () => {
        await expect(vault.manualEnableRecoveryMode(poolB)).to.be.revertedWithCustomError(vault, 'PoolInRecoveryMode');
      });

      it('can call recovery mode only function', async () => {
        await expect(vault.recoveryModeExit(poolB)).to.not.be.reverted;
      });

      it('can disable recovery mode', async () => {
        await vault.manualDisableRecoveryMode(poolB);

        expect(await vault.isPoolInRecoveryMode(poolB)).to.be.false;
      });

      it('disabling recovery mode emits an event', async () => {
        await expect(vault.manualDisableRecoveryMode(poolB))
          .to.emit(vault, 'PoolRecoveryModeStateChanged')
          .withArgs(poolBAddress, false);
      });
    });

    context('not in recovery mode', () => {
      it('is initially not in recovery mode', async () => {
        expect(await vault.isPoolInRecoveryMode(poolB)).to.be.false;
      });

      it('cannot disable when not in recovery mode', async () => {
        await expect(vault.manualDisableRecoveryMode(poolB)).to.be.revertedWithCustomError(
          vault,
          'PoolNotInRecoveryMode'
        );
      });

      it('cannot call recovery mode only function when not in recovery mode', async () => {
        await expect(vault.recoveryModeExit(poolB)).to.be.revertedWithCustomError(vault, 'PoolNotInRecoveryMode');
      });

      it('enabling recovery mode emits an event', async () => {
        await expect(vault.manualEnableRecoveryMode(poolB))
          .to.emit(vault, 'PoolRecoveryModeStateChanged')
          .withArgs(poolBAddress, true);
      });
    });
  });

  describe('reentrancy guard state', () => {
    it('reentrancy guard should be false when not in Vault context', async () => {
      expect(await vault.unguardedCheckNotEntered()).to.not.be.reverted;
    });

    it('reentrancy guard should be true when in Vault context', async () => {
      expect(await vault.guardedCheckEntered()).to.not.be.reverted;
    });
  });
});
