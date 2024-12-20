import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';

import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import { Router, MevRouter, MevTaxCollectorMock, PoolFactoryMock, Vault, WETHTestToken } from '../typechain-types';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { ContractTransactionResponse, VoidSigner } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { deployPermit2 } from './Permit2Deployer';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { buildTokenConfig } from './poolSetup';
import { MAX_UINT160, MAX_UINT256, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import { ERC20 } from '@balancer-labs/v3-solidity-utils/typechain-types';

describe('MevSwaps', () => {
  const MEV_ROUTER_VERSION = 'MevRouter v1';
  const MEV_TAX_MULTIPLIER = 1000n;
  // PRIORITY_GAS_THRESHOLD needs to be more than 1_000_000_000, which is the default hardhat gasPrice.
  const PRIORITY_GAS_THRESHOLD = 1_500_000_000;

  const ROUTER_VERSION = 'Router v9';

  let permit2: IPermit2;
  let vault: Vault;
  let factory: PoolFactoryMock;
  let pool: PoolMock;
  let poolTokens: string[];
  let router: MevRouter, basicRouter: Router;
  let mevTaxCollector: MevTaxCollectorMock;

  let lp: SignerWithAddress, sender: SignerWithAddress, zero: VoidSigner;

  let tokens: ERC20TokenList;
  let token0: ERC20, WETH: WETHTestToken;
  let vaultAddress: string;

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, lp, sender] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await VaultDeployer.deploy();
    vaultAddress = await vault.getAddress();
    WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    mevTaxCollector = await deploy('MevTaxCollectorMock');
    const routerParams = {
      mevTaxCollector: await mevTaxCollector.getAddress(),
      mevTaxMultiplier: MEV_TAX_MULTIPLIER,
      priorityGasThreshold: PRIORITY_GAS_THRESHOLD,
    };
    router = await deploy('MevRouter', { args: [vaultAddress, WETH, permit2, MEV_ROUTER_VERSION, routerParams] });
    basicRouter = await deploy('Router', { args: [vaultAddress, WETH, permit2, ROUTER_VERSION] });
    factory = await deploy('PoolFactoryMock', { args: [vaultAddress, 12 * MONTH] });

    tokens = await ERC20TokenList.create(1, { sorted: true });
    token0 = (await tokens.get(0)) as unknown as ERC20;
    poolTokens = sortAddresses([await WETH.getAddress(), await token0.getAddress()]);

    pool = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool With Eth', 'POOL-ETH'],
    });

    await factory.registerTestPool(pool, buildTokenConfig(poolTokens));
  });

  sharedBeforeEach('allowances', async () => {
    await WETH.connect(lp).deposit({ value: fp(1000) });
    await WETH.connect(sender).deposit({ value: fp(1000) });

    await tokens.mint({ to: lp, amount: fp(1e12) });
    await tokens.mint({ to: sender, amount: fp(1e12) });
    await pool.connect(lp).approve(router, MAX_UINT256);
    await pool.connect(lp).approve(basicRouter, MAX_UINT256);
    for (const token of [...tokens.tokens, WETH, pool]) {
      for (const from of [lp, sender]) {
        await token.connect(from).approve(permit2, MAX_UINT256);
        for (const to of [router, basicRouter]) {
          await permit2.connect(from).approve(token, to, MAX_UINT160, MAX_UINT48);
        }
      }
    }
  });

  sharedBeforeEach('initialize pools', async () => {
    await basicRouter.connect(lp).initialize(pool, poolTokens, Array(poolTokens.length).fill(fp(1000)), 0, false, '0x');

    await pool.connect(lp).transfer(sender, fp(100));
  });

  describe('swap exact in', async () => {
    describe('sender did not pay priority', async () => {
      it('should not pay mev tax using WETH', async () => {
        const amountIn = fp(10);

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const wethSenderBefore = await WETH.connect(sender).balanceOf(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactIn(pool, WETH, token0, amountIn, 0, MAX_UINT256, false, '0x');

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const wethSenderAfter = await WETH.connect(sender).balanceOf(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);

        const receipt = await tx.wait();
        const gasUsed = receipt?.gasUsed || fp(0);
        const gasPrice = receipt?.gasPrice || fp(0);
        const ethUsed = gasUsed * gasPrice;

        // Sender paid the swap with WETH, so the ETH balance is not affected by the swap.
        expect(wethSenderBefore - wethSenderAfter).to.be.eq(amountIn);
        // Since amountIn == amountOut in a linear pool (PoolMock), the amount received is amountIn.
        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountIn);
        // If the sender paid only the gas, it means that no mev tax was charged.
        expect(ethSenderBefore - ethUsed).to.be.eq(ethSenderAfter);
      });

      it('should not pay mev tax using native eth', async () => {
        const amountIn = fp(10);

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactIn(pool, WETH, token0, amountIn, 0, MAX_UINT256, true, '0x', { value: amountIn });

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);

        const receipt = await tx.wait();
        const gasUsed = receipt?.gasUsed || fp(0);
        const gasPrice = receipt?.gasPrice || fp(0);
        const ethUsed = gasUsed * gasPrice;

        // Since amountIn == amountOut in a linear pool (PoolMock), the amount received is amountIn.
        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountIn);
        // If the sender paid only the gas and the exact in amount, it means that no mev tax was charged.
        expect(ethSenderBefore - ethUsed - amountIn).to.be.eq(ethSenderAfter);
      });
    });

    describe('sender paid priority', async () => {
      it('should pay mev tax using WETH', async () => {
        const amountIn = fp(10);
        const gasPriceTx = 2 * PRIORITY_GAS_THRESHOLD;

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const wethSenderBefore = await WETH.connect(sender).balanceOf(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);
        const ethCollectorBefore = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactIn(pool, WETH, token0, amountIn, 0, MAX_UINT256, false, '0x', {
            value: fp(10), // Added to pay mev tax
            gasPrice: gasPriceTx,
          });

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const wethSenderAfter = await WETH.connect(sender).balanceOf(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);
        const ethCollectorAfter = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const { gasPaidInEth, mevTax } = await checkMevTax(tx, ethCollectorBefore, ethCollectorAfter);

        // Sender paid the swap with WETH, so the ETH balance is not affected by the swap.
        expect(wethSenderBefore - wethSenderAfter).to.be.eq(amountIn);
        // Since amountIn == amountOut in a linear pool (PoolMock), the amount received is amountIn.
        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountIn);
        // Sender should pay gasand mev tax. Any excess of ETH sent to the router must be returned to the sender.
        expect(ethSenderBefore - gasPaidInEth - mevTax).to.be.eq(ethSenderAfter);
      });

      it('should pay mev tax using native eth', async () => {
        const amountIn = fp(10);
        const gasPriceTx = 2 * PRIORITY_GAS_THRESHOLD;

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);
        const ethCollectorBefore = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactIn(pool, WETH, token0, amountIn, 0, MAX_UINT256, true, '0x', {
            value: amountIn + fp(10),
            gasPrice: gasPriceTx,
          });

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);
        const ethCollectorAfter = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const { gasPaidInEth, mevTax } = await checkMevTax(tx, ethCollectorBefore, ethCollectorAfter);

        // Since amountIn == amountOut in a linear pool (PoolMock), the amount received is amountIn.
        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountIn);
        // Sender should pay gas, exact in amount and mev tax. Any excess of ETH sent to the router must be returned to
        // the sender.
        expect(ethSenderBefore - gasPaidInEth - amountIn - mevTax).to.be.eq(ethSenderAfter);
      });
    });
  });

  describe('swap exact out', async () => {
    describe('sender did not pay priority', async () => {
      it('should not pay mev tax using WETH', async () => {
        const amountOut = fp(10);

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const wethSenderBefore = await WETH.connect(sender).balanceOf(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactOut(pool, WETH, token0, amountOut, MAX_UINT256, MAX_UINT256, false, '0x');

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const wethSenderAfter = await WETH.connect(sender).balanceOf(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);

        const receipt = await tx.wait();
        const gasUsed = receipt?.gasUsed || fp(0);
        const gasPrice = receipt?.gasPrice || fp(0);
        const ethUsed = gasUsed * gasPrice;

        // Sender paid the swap with WETH, so the ETH balance is not affected by the swap. Also, Since amountIn ==
        // amountOut in a linear pool (PoolMock), the amount paid is amountOut.
        expect(wethSenderBefore - wethSenderAfter).to.be.eq(amountOut);
        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountOut);
        // If the sender paid only the gas, it means that no mev tax was charged.
        expect(ethSenderBefore - ethUsed).to.be.eq(ethSenderAfter);
      });

      it('should not pay mev tax using native eth', async () => {
        const amountOut = fp(10);

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactOut(pool, WETH, token0, amountOut, MAX_UINT256, MAX_UINT256, true, '0x', {
            value: amountOut,
          });

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);

        const receipt = await tx.wait();
        const gasUsed = receipt?.gasUsed || fp(0);
        const gasPrice = receipt?.gasPrice || fp(0);
        const ethUsed = gasUsed * gasPrice;

        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountOut);
        // If the sender paid only the gas and the exact in amount, it means that no mev tax was charged. Also,
        // since amountIn == amountOut in a linear pool (PoolMock), the amount paid is amountOut.
        expect(ethSenderBefore - ethUsed - amountOut).to.be.eq(ethSenderAfter);
      });
    });

    describe('sender paid priority', async () => {
      it('should pay mev tax using WETH', async () => {
        const amountOut = fp(10);
        const gasPriceTx = 2 * PRIORITY_GAS_THRESHOLD;

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const wethSenderBefore = await WETH.connect(sender).balanceOf(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);
        const ethCollectorBefore = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactOut(pool, WETH, token0, amountOut, MAX_UINT256, MAX_UINT256, false, '0x', {
            value: fp(10), // Added to pay mev tax
            gasPrice: gasPriceTx,
          });

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const wethSenderAfter = await WETH.connect(sender).balanceOf(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);
        const ethCollectorAfter = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const { gasPaidInEth, mevTax } = await checkMevTax(tx, ethCollectorBefore, ethCollectorAfter);

        // Sender paid the swap with WETH, so the ETH balance is not affected by the swap. Also, since amountIn ==
        // amountOut in a linear pool (PoolMock), the amount paid is amountOut.
        expect(wethSenderBefore - wethSenderAfter).to.be.eq(amountOut);
        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountOut);
        // Sender should pay gas and mev tax. Any excess of ETH sent to the router must be returned to the sender.
        expect(ethSenderBefore - gasPaidInEth - mevTax).to.be.eq(ethSenderAfter);
      });

      it('should pay mev tax using native eth', async () => {
        const amountOut = fp(10);
        const gasPriceTx = 2 * PRIORITY_GAS_THRESHOLD;

        const ethSenderBefore = await ethers.provider.getBalance(sender);
        const token0SenderBefore = await token0.connect(sender).balanceOf(sender);
        const ethCollectorBefore = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const tx = await router
          .connect(sender)
          .swapSingleTokenExactOut(pool, WETH, token0, amountOut, MAX_UINT256, MAX_UINT256, true, '0x', {
            value: amountOut + fp(10),
            gasPrice: gasPriceTx,
          });

        const ethSenderAfter = await ethers.provider.getBalance(sender);
        const token0SenderAfter = await token0.connect(sender).balanceOf(sender);
        const ethCollectorAfter = await ethers.provider.getBalance(await mevTaxCollector.getAddress());

        const { gasPaidInEth, mevTax } = await checkMevTax(tx, ethCollectorBefore, ethCollectorAfter);

        expect(token0SenderAfter - token0SenderBefore).to.be.eq(amountOut);
        // Sender should pay gas, exact in amount and mev tax. Any excess of ETH sent to the router must be returned to
        // the sender. Also, since amountIn == amountOut in a linear pool (PoolMock), the amount paid is amountOut.
        expect(ethSenderBefore - gasPaidInEth - amountOut - mevTax).to.be.eq(ethSenderAfter);
      });
    });
  });

  async function checkMevTax(
    tx: ContractTransactionResponse,
    ethCollectorBefore: bigint,
    ethCollectorAfter: bigint
  ): Promise<{
    gasPaidInEth: bigint;
    mevTax: bigint;
  }> {
    const receipt = await tx.wait();
    const gasUsed = receipt?.gasUsed || fp(0);
    const gasPrice = receipt?.gasPrice || fp(0);

    const mevTaxEvent = receipt?.logs.find((log) => log?.fragment?.name == 'MevTaxCharged');
    const poolAddress: string = mevTaxEvent?.args?.[0] || '';
    const mevTax = mevTaxEvent?.args?.[1] || fp(0);
    const baseFee = (await tx.getBlock())?.baseFeePerGas || fp(0);

    expect(poolAddress).to.be.eq(await pool.getAddress());
    expect(mevTax).to.be.eq((gasPrice - baseFee) * MEV_TAX_MULTIPLIER);
    expect(ethCollectorAfter - ethCollectorBefore).to.be.eq(mevTax);

    const gasPaidInEth = gasUsed * gasPrice;
    return { gasPaidInEth, mevTax };
  }
});
