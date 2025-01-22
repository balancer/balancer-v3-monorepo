import { ethers } from 'hardhat';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { fp, fpMulDown } from '@balancer-labs/v3-helpers/src/numbers';
import { setNextBlockBaseFeePerGas } from '@nomicfoundation/hardhat-network-helpers';

import { PoolMock } from '../typechain-types/@balancer-labs/v3-vault/contracts/test/PoolMock';
import { MevTaxHook, Router, PoolFactoryMock, Vault, WETHTestToken, IVault } from '../typechain-types';
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

enum RegistryContractType {
  OTHER,
  POOL_FACTORY,
  ROUTER,
  HOOK,
  ERC4626,
}

describe('MevTaxHook', () => {
  const ROUTER_VERSION = 'Router V1';
  const PRIORITY_GAS_THRESHOLD = 3_000_000n;
  const MEV_MULTIPLIER = fp(10_000_000_000);

  const STATIC_SWAP_FEE_PERCENTAGE = fp(0.01); // 1% swap fee

  let permit2: IPermit2;
  let vault: Vault;
  let iVault: IVault;
  let factory: PoolFactoryMock;
  let pool: PoolMock;
  let poolTokens: string[];
  let router: Router;
  let untrustedRouter: Router;
  let hook: MevTaxHook;
  let registry: BalancerContractRegistry;

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
    untrustedRouter = await deploy('v3-vault/Router', { args: [vaultAddress, WETH, permit2, 'UNTRUSTED_VERSION'] });
    factory = await deploy('v3-vault/PoolFactoryMock', { args: [vaultAddress, 12 * MONTH] });
    registry = await deploy('standalone-utils/BalancerContractRegistry', { args: [vaultAddress] });

    tokens = await ERC20TokenList.create(2, { sorted: true });
    token0 = (await tokens.get(0)) as unknown as ERC20;
    token1 = (await tokens.get(1)) as unknown as ERC20;
    poolTokens = sortAddresses([await token0.getAddress(), await token1.getAddress()]);

    pool = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool with MEV Hook', 'POOL-MEV'],
    });

    hook = await deploy('MevTaxHook', { args: [vaultAddress, registry] });

    await factory.registerPoolWithHook(pool, buildTokenConfig(poolTokens), hook);
  });

  sharedBeforeEach('permissions', async () => {
    const authorizerAddress = await iVault.getAuthorizer();
    const authorizer = await deployedAt('v3-vault/BasicAuthorizerMock', authorizerAddress);

    const actions: string[] = [];
    // Vault Actions
    actions.push(await actionId(iVault, 'setStaticSwapFeePercentage'));
    // Registry Actions
    actions.push(await actionId(registry, 'registerBalancerContract'));
    // MEV Hook Actions
    actions.push(await actionId(hook, 'addMevTaxExemptSenders'));
    actions.push(await actionId(hook, 'disableMevTax'));
    actions.push(await actionId(hook, 'enableMevTax'));
    actions.push(await actionId(hook, 'setDefaultMevTaxMultiplier'));
    actions.push(await actionId(hook, 'setDefaultMevTaxThreshold'));
    actions.push(await actionId(hook, 'setMaxMevSwapFeePercentage'));
    actions.push(await actionId(hook, 'setPoolMevTaxMultiplier'));
    actions.push(await actionId(hook, 'setPoolMevTaxThreshold'));

    await Promise.all(actions.map(async (action) => authorizer.grantRole(action, admin.address)));
  });

  sharedBeforeEach('registry configuration', async () => {
    await registry.connect(admin).registerBalancerContract(RegistryContractType.ROUTER, 'Router', router);
  });

  sharedBeforeEach('fees configuration', async () => {
    await iVault.connect(admin).setStaticSwapFeePercentage(pool, STATIC_SWAP_FEE_PERCENTAGE);
  });

  sharedBeforeEach('hook configuration', async () => {
    await hook.connect(admin).setDefaultMevTaxMultiplier(MEV_MULTIPLIER);
    await hook.connect(admin).setDefaultMevTaxThreshold(PRIORITY_GAS_THRESHOLD);
    await hook.connect(admin).setPoolMevTaxMultiplier(pool, MEV_MULTIPLIER);
    await hook.connect(admin).setPoolMevTaxThreshold(pool, PRIORITY_GAS_THRESHOLD);

    await hook.connect(admin).enableMevTax();
  });

  sharedBeforeEach('token allowances', async () => {
    await WETH.connect(lp).deposit({ value: fp(1000) });
    await WETH.connect(sender).deposit({ value: fp(1000) });

    await tokens.mint({ to: lp, amount: fp(1e12) });
    await tokens.mint({ to: sender, amount: fp(1e12) });
    await pool.connect(lp).approve(router, MAX_UINT256);
    await pool.connect(lp).approve(untrustedRouter, MAX_UINT256);
    for (const token of [...tokens.tokens, WETH, pool]) {
      for (const from of [lp, sender]) {
        await token.connect(from).approve(permit2, MAX_UINT256);
        await permit2.connect(from).approve(token, router, MAX_UINT160, MAX_UINT48);
        await permit2.connect(from).approve(token, untrustedRouter, MAX_UINT160, MAX_UINT48);
      }
    }
  });

  sharedBeforeEach('initialize pools', async () => {
    await router.connect(lp).initialize(pool, poolTokens, Array(poolTokens.length).fill(fp(1000)), 0, false, '0x');

    await pool.connect(lp).transfer(sender, fp(100));
  });

  describe('when there is no MEV tax', async () => {
    it('MEV hook disabled', async () => {
      await hook.connect(admin).disableMevTax();
      expect(await hook.isMevTaxEnabled()).to.be.false;

      const amountIn = fp(10);
      const baseFee = await getNextBlockBaseFee();
      // "BaseFee + 2 * PriorityGasThreshold" should trigger MEV Tax, but static swap fee will be charged because MEV tax is
      // disabled.
      const txGasPrice = baseFee + 2n * PRIORITY_GAS_THRESHOLD;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactInWithoutMevTax(balancesBefore, balancesAfter, amountIn);
    });

    it('low priority gas price', async () => {
      const amountIn = fp(10);
      // To trigger MEV tax, `txGasPrice` > `BaseFee + PriorityGasThreshold`.
      const txGasPrice = PRIORITY_GAS_THRESHOLD;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactInWithoutMevTax(balancesBefore, balancesAfter, amountIn);
    });

    it('MEV multiplier is 0', async () => {
      // 0 multiplier. Should return static fee.
      await hook.setPoolMevTaxMultiplier(pool, 0);

      const amountIn = fp(10);

      const baseFee = await getNextBlockBaseFee();
      // "BaseFee + PriorityGas + 1" should trigger MEV Tax.
      const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactInWithoutMevTax(balancesBefore, balancesAfter, amountIn);
    });

    it('Address is MEV tax-exempt', async () => {
      await hook.connect(admin).addMevTaxExemptSenders([sender]);
      await hook.setPoolMevTaxMultiplier(pool, MEV_MULTIPLIER);

      const amountIn = fp(10);

      const baseFee = await getNextBlockBaseFee();
      // `BaseFee + 10 * PRIORITY_GAS_THRESHOLD` should trigger MEV Tax and pay MEV tax over
      // `9 * PRIORITY_GAS_THRESHOLD` (static fee is charged up to `baseFee + PRIORITY_GAS_THRESHOLD`). However, since
      // "sender" is exempt, he will pay only static fee.
      const txGasPrice = baseFee + 10n * PRIORITY_GAS_THRESHOLD;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactInWithoutMevTax(balancesBefore, balancesAfter, amountIn);
    });
  });

  describe('when there is MEV tax', async () => {
    it('MEV fee percentage bigger than default max value', async () => {
      await hook.connect(admin).setMaxMevSwapFeePercentage(fp(0.2));

      // Big multiplier, the MEV fee percentage should be more than 20%. Since the Max fee is set to 20%, that's what
      // will be charged.
      await hook.setPoolMevTaxMultiplier(pool, fpMulDown(MEV_MULTIPLIER, fp(100000000n)));

      const amountIn = fp(10);

      const baseFee = await getNextBlockBaseFee();
      // "BaseFee + PriorityGas + 1" should trigger MEV Tax.
      const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactInChargingMevTax(balancesBefore, balancesAfter, txGasPrice, amountIn);
    });

    it('Address is MEV tax-exempt but router is not trusted', async () => {
      await hook.connect(admin).addMevTaxExemptSenders([sender]);
      await hook.setPoolMevTaxMultiplier(pool, MEV_MULTIPLIER);

      const amountIn = fp(10);

      const baseFee = await getNextBlockBaseFee();
      // `BaseFee + 10 * PRIORITY_GAS_THRESHOLD` should trigger MEV Tax and pay MEV tax over
      // `9 * PRIORITY_GAS_THRESHOLD` (static fee is charged up to `baseFee + PRIORITY_GAS_THRESHOLD`). However, since
      // "sender" is exempt, he will pay only static fee.
      const txGasPrice = baseFee + 10n * PRIORITY_GAS_THRESHOLD;

      const balancesBefore = await getBalances();

      await untrustedRouter
        .connect(sender)
        .swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
          gasPrice: txGasPrice,
        });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactInChargingMevTax(balancesBefore, balancesAfter, txGasPrice, amountIn);
    });

    it('charge MEV tax proportional to priority gas price', async () => {
      await hook.setPoolMevTaxMultiplier(pool, MEV_MULTIPLIER);

      const amountIn = fp(10);

      const baseFee = await getNextBlockBaseFee();
      // `BaseFee + 10 * PRIORITY_GAS_THRESHOLD` should trigger MEV Tax and pay MEV tax over
      // `9 * PRIORITY_GAS_THRESHOLD` (static fee is charged up to `baseFee + PRIORITY_GAS_THRESHOLD`).
      const txGasPrice = baseFee + 10n * PRIORITY_GAS_THRESHOLD;

      const balancesBefore = await getBalances();

      await router.connect(sender).swapSingleTokenExactIn(pool, token0, token1, amountIn, 0, MAX_UINT256, false, '0x', {
        gasPrice: txGasPrice,
      });

      const balancesAfter = await getBalances();

      await checkSwapFeeExactInChargingMevTax(balancesBefore, balancesAfter, txGasPrice, amountIn);
    });
  });

  describe('add liquidity', async () => {
    context('when there is no MEV tax', () => {
      it('allows proportional for any gas price', async () => {
        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = (baseFee + PRIORITY_GAS_THRESHOLD) * 100n;

        await expect(
          router
            .connect(sender)
            .addLiquidityProportional(pool, Array(poolTokens.length).fill(fp(1000)), fp(1), false, '0x', {
              gasPrice: txGasPrice,
            })
        ).to.not.be.reverted;
      });

      it('allows unbalanced for gas price below threshold', async () => {
        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD;

        await expect(
          router
            .connect(sender)
            .addLiquidityUnbalanced(pool, Array(poolTokens.length).fill(fp(100)), fp(0), false, '0x', {
              gasPrice: txGasPrice,
            })
        ).to.not.be.reverted;
      });
    });

    context('when MEV tax has to be applied', () => {
      it('allows unbalanced for any gas price if the hook is disabled', async () => {
        await hook.connect(admin).disableMevTax();

        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = (baseFee + PRIORITY_GAS_THRESHOLD) * 100n;

        await expect(
          router
            .connect(sender)
            .addLiquidityUnbalanced(pool, Array(poolTokens.length).fill(fp(100)), fp(0), false, '0x', {
              gasPrice: txGasPrice,
            })
        ).to.not.be.reverted;
      });

      it('blocks unbalanced for gas price above threshold', async () => {
        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

        await expect(
          router
            .connect(sender)
            .addLiquidityUnbalanced(pool, Array(poolTokens.length).fill(fp(1000)), fp(0), false, '0x', {
              gasPrice: txGasPrice,
            })
        ).to.be.revertedWithCustomError(vault, 'BeforeAddLiquidityHookFailed');
      });
    });
  });

  describe('remove liquidity', async () => {
    context('when there is no MEV tax', () => {
      it('allows proportional for any gas price', async () => {
        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = (baseFee + PRIORITY_GAS_THRESHOLD) * 100n;

        await expect(
          router.connect(lp).removeLiquidityProportional(pool, fp(1), Array(poolTokens.length).fill(0n), false, '0x', {
            gasPrice: txGasPrice,
          })
        ).to.not.be.reverted;
      });

      it('allows unbalanced for gas price below threshold', async () => {
        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD;

        await expect(
          router.connect(lp).removeLiquiditySingleTokenExactIn(pool, fp(1), token0, 1n, false, '0x', {
            gasPrice: txGasPrice,
          })
        ).to.not.be.reverted;
      });
    });

    context('when MEV tax has to be applied', () => {
      it('allows unbalanced for any gas price if the hook is disabled', async () => {
        await hook.connect(admin).disableMevTax();

        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = (baseFee + PRIORITY_GAS_THRESHOLD) * 100n;

        await expect(
          router.connect(lp).removeLiquiditySingleTokenExactIn(pool, fp(1), token0, 1n, false, '0x', {
            gasPrice: txGasPrice,
          })
        ).to.not.be.reverted;
      });

      it('blocks unbalanced for gas price above threshold', async () => {
        const baseFee = await getNextBlockBaseFee();
        const txGasPrice = baseFee + PRIORITY_GAS_THRESHOLD + 1n;

        await expect(
          router.connect(lp).removeLiquiditySingleTokenExactIn(pool, fp(1), token0, 1n, false, '0x', {
            gasPrice: txGasPrice,
          })
        ).to.be.revertedWithCustomError(vault, 'BeforeRemoveLiquidityHookFailed');
      });
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

  async function checkSwapFeeExactInChargingMevTax(
    balancesBefore: Balances,
    balancesAfter: Balances,
    txGasPrice: bigint,
    amountIn: bigint
  ) {
    const mevMultiplier = await hook.getPoolMevTaxMultiplier(pool);

    const filter = vault.filters.Swap;
    const events = await vault.queryFilter(filter, -1);
    const swapEvent = events[0];

    const baseFee = await getNextBlockBaseFee();

    const priorityGasPrice = txGasPrice - baseFee;
    let mevSwapFeePercentage =
      STATIC_SWAP_FEE_PERCENTAGE + fpMulDown(priorityGasPrice - PRIORITY_GAS_THRESHOLD, mevMultiplier);
    const maxMevSwapFeePercentage = await hook.getMaxMevSwapFeePercentage();

    if (mevSwapFeePercentage >= maxMevSwapFeePercentage) {
      // If mevSwapFeePercentage > max fee percentage, charge the max value.
      mevSwapFeePercentage = maxMevSwapFeePercentage;
    }
    const mevSwapFee = fpMulDown(mevSwapFeePercentage, amountIn);

    expect(swapEvent.args.swapFeePercentage).to.be.eq(mevSwapFeePercentage, 'Incorrect Swap Fee Percentage');
    expect(swapEvent.args.swapFeePercentage).to.be.gte(
      STATIC_SWAP_FEE_PERCENTAGE,
      'MEV fee percentage lower than static fee percentage'
    );
    expect(swapEvent.args.swapFeeAmount).to.be.eq(mevSwapFee, 'Incorrect Swap Fee');
    expect(balancesAfter.token0).to.be.eq(balancesBefore.token0 - amountIn);
    expect(balancesAfter.token1).to.be.eq(balancesBefore.token1 + amountIn - mevSwapFee);
  }

  async function checkSwapFeeExactInWithoutMevTax(balancesBefore: Balances, balancesAfter: Balances, amountIn: bigint) {
    const filter = vault.filters.Swap;
    const events = await vault.queryFilter(filter, -1);
    const swapEvent = events[0];

    const staticSwapFee = fpMulDown(STATIC_SWAP_FEE_PERCENTAGE, amountIn);

    expect(swapEvent.args.swapFeePercentage).to.be.eq(STATIC_SWAP_FEE_PERCENTAGE, 'Incorrect Swap Fee Percentage');
    expect(swapEvent.args.swapFeeAmount).to.be.eq(staticSwapFee, 'Incorrect Swap Fee');
    expect(balancesAfter.token0).to.be.eq(balancesBefore.token0 - amountIn);
    expect(balancesAfter.token1).to.be.eq(balancesBefore.token1 + amountIn - staticSwapFee);
  }

  async function getNextBlockBaseFee() {
    const provider = ethers.provider;
    const block = await provider.getBlock('latest'); // Get the latest block
    const latestBlockBaseFee = block?.baseFeePerGas || 0n;
    await setNextBlockBaseFeePerGas(latestBlockBaseFee);

    return latestBlockBaseFee;
  }
});
