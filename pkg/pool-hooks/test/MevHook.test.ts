import { ethers } from 'hardhat';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { fp, fpMulDown } from '@balancer-labs/v3-helpers/src/numbers';

import { PoolMock } from '../typechain-types/@balancer-labs/v3-vault/contracts/test/PoolMock';
import { MevHook, Router, PoolFactoryMock, Vault, WETHTestToken, IVault } from '../typechain-types';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { MAX_UINT160, MAX_UINT256, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import { ERC20 } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { expect } from 'chai';

describe('MevHook', () => {
  const ROUTER_VERSION = 'Router V1';
  const PRIORITY_GAS_THRESHOLD = 3_000_000n;
  const MEV_MULTIPLIER = fp(10_000_000_000);
  const MAX_MEV_FEE_PERCENTAGE = fp(0.999999);

  const STATIC_SWAP_FEE_PERCENTAGE = fp(0.01); // 1% swap fee

  let permit2: IPermit2;
  let vault: Vault;
  let iVault: IVault;
  let factory: PoolFactoryMock;
  let pool: PoolMock;
  let poolTokens: string[];
  let router: Router;
  let hook: MevHook;

  let admin: SignerWithAddress, lp: SignerWithAddress, sender: SignerWithAddress;

  let tokens: ERC20TokenList;
  let token0: ERC20, token1: ERC20, WETH: WETHTestToken;
  let vaultAddress: string;

  before('setup signers', async () => {
    [admin, lp, sender] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await VaultDeployer.deploy();
    iVault = await TypesConverter.toIVault(vault);
    vaultAddress = await vault.getAddress();
    WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await deploy('v3-vault/Router', { args: [vaultAddress, WETH, permit2, ROUTER_VERSION] });
    factory = await deploy('v3-vault/PoolFactoryMock', { args: [vaultAddress, 12 * MONTH] });

    tokens = await ERC20TokenList.create(2, { sorted: true });
    token0 = (await tokens.get(0)) as unknown as ERC20;
    token1 = (await tokens.get(1)) as unknown as ERC20;
    poolTokens = sortAddresses([await token0.getAddress(), await token1.getAddress()]);

    pool = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool with MEV Hook', 'POOL-MEV'],
    });

    hook = await deploy('MevHook', { args: [vaultAddress] });

    await factory.registerTestPoolDisableUnbalancedLiquidity(pool, buildTokenConfig(poolTokens), hook, lp);
  });

  sharedBeforeEach('permissions', async () => {
    const authorizerAddress = await iVault.getAuthorizer();
    const authorizer = await deployedAt('v3-vault/BasicAuthorizerMock', authorizerAddress);

    const actions: string[] = [];
    // Vault Actions
    actions.push(await actionId(iVault, 'setStaticSwapFeePercentage'));
    // Mev Hook Actions
    actions.push(await actionId(hook, 'disableMevTax'));
    actions.push(await actionId(hook, 'enableMevTax'));
    actions.push(await actionId(hook, 'setDefaultMevTaxMultiplier'));
    actions.push(await actionId(hook, 'setPoolMevTaxMultiplier'));
    actions.push(await actionId(hook, 'setDefaultMevTaxThreshold'));
    actions.push(await actionId(hook, 'setPoolMevTaxThreshold'));

    await Promise.all(actions.map(async (action) => authorizer.grantRole(action, admin.address)));
  });

  sharedBeforeEach('fees configuration', async () => {
    await iVault.connect(admin).setStaticSwapFeePercentage(pool, STATIC_SWAP_FEE_PERCENTAGE);
  });

  sharedBeforeEach('hook configuration', async () => {
    await hook.connect(admin).setDefaultMevTaxMultiplier(MEV_MULTIPLIER);
    await hook.connect(admin).setDefaultMevTaxThreshold(PRIORITY_GAS_THRESHOLD);
    await hook.connect(admin).setPoolMevTaxMultiplier(pool, MEV_MULTIPLIER);
    await hook.connect(admin).setPoolMevTaxThreshold(pool, PRIORITY_GAS_THRESHOLD);
  });

  sharedBeforeEach('token allowances', async () => {
    await WETH.connect(lp).deposit({ value: fp(1000) });
    await WETH.connect(sender).deposit({ value: fp(1000) });

    await tokens.mint({ to: lp, amount: fp(1e12) });
    await tokens.mint({ to: sender, amount: fp(1e12) });
    await pool.connect(lp).approve(router, MAX_UINT256);
    for (const token of [...tokens.tokens, WETH, pool]) {
      for (const from of [lp, sender]) {
        await token.connect(from).approve(permit2, MAX_UINT256);
        await permit2.connect(from).approve(token, router, MAX_UINT160, MAX_UINT48);
      }
    }
  });

  sharedBeforeEach('initialize pools', async () => {
    await router.connect(lp).initialize(pool, poolTokens, Array(poolTokens.length).fill(fp(1000)), 0, false, '0x');

    await pool.connect(lp).transfer(sender, fp(100));
  });

  describe('do not pay mev tax', async () => {
    const shouldChargeMev = false;

    it('mev hook disabled', async () => {
      await hook.connect(admin).disableMevTax();
      expect(await hook.isMevTaxEnabled()).to.be.false;

      const amountIn = fp(10);
      const baseFee = await getBaseFee();
      // "BaseFee + PriorityGas + 1" should trigger Mev Tax, but static swap fee will be charged because Mev tax is
      // disabled.
      const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactIn(balancesBefore, balancesAfter, txGasPrice, amountIn, shouldChargeMev);
    });

    it('low priority gas price', async () => {
      await hook.connect(admin).enableMevTax();
      expect(await hook.isMevTaxEnabled()).to.be.true;

      const amountIn = fp(10);
      // "PriorityGas" should not trigger Mev Tax, because to trigger the gasPrice must be BaseFee + Threshold + 1.
      const txGasPrice = PRIORITY_GAS_THRESHOLD;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactIn(balancesBefore, balancesAfter, txGasPrice, amountIn, shouldChargeMev);
    });

    it('mev fee percentage smaller than static', async () => {
      await hook.connect(admin).enableMevTax();
      expect(await hook.isMevTaxEnabled()).to.be.true;

      // Small multiplier, the mev fee percentage will be lower than static swap fee. In this case, static swap fee
      // should be charged.
      await hook.setPoolMevTaxMultiplier(pool, fpMulDown(MEV_MULTIPLIER, fp(0.0001)));

      const amountIn = fp(10);

      const baseFee = await getBaseFee();
      // "BaseFee + PriorityGas + 1" should trigger Mev Tax.
      const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactIn(balancesBefore, balancesAfter, txGasPrice, amountIn, shouldChargeMev);
    });

    it('mev multiplier is 0', async () => {
      await hook.connect(admin).enableMevTax();
      expect(await hook.isMevTaxEnabled()).to.be.true;

      // 0 multiplier. Should return static fee.
      await hook.setPoolMevTaxMultiplier(pool, 0);

      const amountIn = fp(10);

      const baseFee = await getBaseFee();
      // "BaseFee + PriorityGas + 1" should trigger Mev Tax.
      const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactIn(balancesBefore, balancesAfter, txGasPrice, amountIn, shouldChargeMev);
    });
  });

  describe('should pay mev tax', async () => {
    const shouldChargeMev = true;

    it('mev fee percentage bigger than max value', async () => {
      await hook.connect(admin).enableMevTax();
      expect(await hook.isMevTaxEnabled()).to.be.true;

      // Big multiplier, the mev fee percentage should be more than 99.9999%. Since the Max fee is 99.9999%, that's what
      // will be charged.
      await hook.setPoolMevTaxMultiplier(pool, fpMulDown(MEV_MULTIPLIER, fp(100n)));

      const amountIn = fp(10);

      const baseFee = await getBaseFee();
      // "BaseFee + PriorityGas + 1" should trigger Mev Tax.
      const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactIn(balancesBefore, balancesAfter, txGasPrice, amountIn, shouldChargeMev);
    });

    it('charge mev tax proportional to priority gas price', async () => {
      await hook.connect(admin).enableMevTax();
      expect(await hook.isMevTaxEnabled()).to.be.true;

      await hook.setPoolMevTaxMultiplier(pool, MEV_MULTIPLIER);

      const amountIn = fp(10);

      const baseFee = await getBaseFee();
      // "BaseFee + PriorityGas + 1" should trigger Mev Tax.
      const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactIn(balancesBefore, balancesAfter, txGasPrice, amountIn, shouldChargeMev);
    });
  });

  interface Balances {
    token0: bigint;
    token1: bigint;
  }

  async function getBalances(): Promise<Balances> {
    return {
      token0: await token0.connect(sender).balanceOf(sender),
      token1: await token1.connect(sender).balanceOf(sender),
    };
  }

  async function checkSwapFeeExactIn(
    balancesBefore: Balances,
    balancesAfter: Balances,
    txGasPrice: bigint,
    amountIn: bigint,
    shouldChargeMev: boolean
  ) {
    const mevMultiplier = await hook.getPoolMevTaxMultiplier(pool);

    const filter = vault.filters.Swap;
    const events = await vault.queryFilter(filter, -1);
    const swapEvent = events[0];

    const baseFee = await getBaseFee();

    let mevSwapFeePercentage = fpMulDown(txGasPrice - baseFee, mevMultiplier);
    if (mevSwapFeePercentage >= MAX_MEV_FEE_PERCENTAGE) {
      // If mevSwapFeePercentage > max fee percentage, charge the max value.
      mevSwapFeePercentage = MAX_MEV_FEE_PERCENTAGE;
    }
    const mevSwapFee = fpMulDown(mevSwapFeePercentage, amountIn);
    const staticSwapFee = fpMulDown(STATIC_SWAP_FEE_PERCENTAGE, amountIn);

    if (shouldChargeMev) {
      expect(swapEvent.args.swapFeePercentage).to.be.eq(mevSwapFeePercentage, 'Incorrect Swap Fee Percentage');
      expect(swapEvent.args.swapFeeAmount).to.be.eq(mevSwapFee, 'Incorrect Swap Fee');
      expect(balancesAfter.token0).to.be.eq(balancesBefore.token0 - amountIn);
      expect(balancesAfter.token1).to.be.eq(balancesBefore.token1 + amountIn - mevSwapFee);
    } else {
      expect(swapEvent.args.swapFeePercentage).to.be.eq(STATIC_SWAP_FEE_PERCENTAGE, 'Incorrect Swap Fee Percentage');
      expect(swapEvent.args.swapFeeAmount).to.be.eq(staticSwapFee, 'Incorrect Swap Fee');
      expect(balancesAfter.token0).to.be.eq(balancesBefore.token0 - amountIn);
      expect(balancesAfter.token1).to.be.eq(balancesBefore.token1 + amountIn - staticSwapFee);
    }
  }

  async function getBaseFee() {
    const provider = ethers.provider;
    const block = await provider.getBlock('latest'); // Get the latest block
    return block?.baseFeePerGas || 0n;
  }
});
