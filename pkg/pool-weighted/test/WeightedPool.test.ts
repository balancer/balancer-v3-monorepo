import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { PoolConfigStructOutput, VaultMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/VaultMock';
import { Router } from '@balancer-labs/v3-vault/typechain-types/contracts/Router';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/BasicAuthorizerMock';
import { PoolMock } from '@balancer-labs/v3-pool-utils/typechain-types/contracts/test/PoolMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { FP_ZERO, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';

describe('WeightedPool', function () {
  let vault: VaultMock;
  let pool: PoolMock;
  let router: Router;
  let factory: SignerWithAddress;
  let alice: SignerWithAddress;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;
  let poolTokens: string[];
  let vaultAddress: string;
  let poolAddress: string;

  before('setup signers', async () => {
    [, factory, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, router, tokens, and pool', async function () {
    const PAUSE_WINDOW_DURATION = MONTH * 3;
    const BUFFER_PERIOD_DURATION = MONTH;

    const authorizer: BasicAuthorizerMock = await deploy('v3-solidity-utils/BasicAuthorizerMock');
    vault = await deploy('v3-vault/VaultMock', {
      args: [await authorizer.getAddress(), PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION],
    });
    vaultAddress = await vault.getAddress();

    router = await deploy('v3-vault/Router', { args: [vaultAddress, ZERO_ADDRESS] });

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
    tokenC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

    const tokenAAddress = await tokenA.getAddress();
    const tokenBAddress = await tokenB.getAddress();
    const tokenCAddress = await tokenC.getAddress();

    poolTokens = [tokenAAddress, tokenBAddress, tokenCAddress];

    pool = await deploy('v3-pool-utils/PoolMock', {
      args: [vaultAddress, 'Pool', 'POOL', factory, poolTokens, true],
    });

    poolAddress = await pool.getAddress();
  });

  describe('initialization', () => {
    const TOKEN_AMOUNT = fp(100);
    const INITIAL_BALANCES = [TOKEN_AMOUNT, TOKEN_AMOUNT, FP_ZERO];

    context('uninitialized', () => {
      it('is registered, but not initialized on deployment', async () => {
        const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(poolAddress);

        expect(poolConfig.isRegisteredPool).to.be.true;
        expect(poolConfig.isInitializedPool).to.be.false;
      });
    });

    context('initialized', () => {
      sharedBeforeEach('initialize pool', async () => {
        tokenA.mint(alice, TOKEN_AMOUNT);
        tokenB.mint(alice, TOKEN_AMOUNT);

        tokenA.connect(alice).approve(await vault.getAddress(), MAX_UINT256);
        tokenB.connect(alice).approve(await vault.getAddress(), MAX_UINT256);

        expect(await router.connect(alice).initialize(poolAddress, poolTokens, INITIAL_BALANCES, FP_ZERO, '0x'))
          .to.emit(vault, 'PoolInitialized')
          .withArgs(poolAddress);
      });

      it('is registered and initialized', async () => {
        const poolConfig: PoolConfigStructOutput = await vault.getPoolConfig(poolAddress);

        expect(poolConfig.isRegisteredPool).to.be.true;
        expect(poolConfig.isInitializedPool).to.be.true;
      });

      it('has the correct pool tokens and balances', async () => {
        const tokensFromPool = await pool.getPoolTokens();
        expect(tokensFromPool).to.deep.equal(poolTokens);

        const [tokensFromVault, balancesFromVault] = await vault.getPoolTokenInfo(poolAddress);
        expect(tokensFromVault).to.deep.equal(tokensFromPool);
        expect(balancesFromVault).to.deep.equal(INITIAL_BALANCES);
      });

      it('cannot be initialized twice', async () => {
        await expect(router.connect(alice).initialize(poolAddress, poolTokens, INITIAL_BALANCES, FP_ZERO, '0x'))
          .to.be.revertedWithCustomError(vault, 'PoolAlreadyInitialized')
          .withArgs(poolAddress);
      });
    });
  });
});
