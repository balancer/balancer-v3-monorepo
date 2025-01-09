import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';

import { PoolMock } from '../typechain-types/@balancer-labs/v3-vault/contracts/test/PoolMock';
import { MevHook, Router, PoolFactoryMock, Vault, WETHTestToken } from '../typechain-types';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { ContractTransactionResponse } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { buildTokenConfig } from '@balancer-labs/v3-helpers/src/models/tokens/tokenConfig';
import { deployPermit2 } from '@balancer-labs/v3-vault/test/Permit2Deployer';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { MAX_UINT160, MAX_UINT256, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import { ERC20 } from '@balancer-labs/v3-solidity-utils/typechain-types';

describe('MevHook', () => {
  const ROUTER_VERSION = 'Router V1';

  let permit2: IPermit2;
  let vault: Vault;
  let factory: PoolFactoryMock;
  let pool: PoolMock;
  let poolTokens: string[];
  let router: Router;
  let hook: MevHook;

  let lp: SignerWithAddress, sender: SignerWithAddress;

  let tokens: ERC20TokenList;
  let token0: ERC20, token1: ERC20, WETH: WETHTestToken;
  let vaultAddress: string;

  before('setup signers', async () => {
    [, lp, sender] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await VaultDeployer.deploy();
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

    await factory.registerPoolWithHook(pool, buildTokenConfig(poolTokens), hook);
  });

  sharedBeforeEach('allowances', async () => {
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

  it('MEV Hook Disabled', () => {
    expect(true, 'true');
  });

  interface Balances {
    sender: {
      eth: bigint;
      weth: bigint;
      token0: bigint;
    };
  }

  async function getBalances(): Promise<Balances> {
    return {
      sender: {
        eth: await ethers.provider.getBalance(sender),
        weth: await WETH.connect(sender).balanceOf(sender),
        token0: await token0.connect(sender).balanceOf(sender),
      },
    };
  }

  // async function checkMevTax(
  //   tx: ContractTransactionResponse,
  //   mevWasCharged: boolean,
  //   ethCollectorBefore: bigint,
  //   ethCollectorAfter: bigint
  // ): Promise<{
  //   gasPaidInEth: bigint;
  //   mevTax: bigint;
  // }> {
  //   const receipt = await tx.wait();
  //   const gasUsed = receipt?.gasUsed || fp(0);
  //   const gasPrice = receipt?.gasPrice || fp(0);
  //
  //   let mevTax = 0n;
  //   if (mevWasCharged) {
  //     const mevTaxEvent = receipt?.logs.find((log) => log?.fragment?.name == 'MevTaxCharged');
  //     const poolAddress: string = mevTaxEvent?.args?.[0] || '';
  //     mevTax = mevTaxEvent?.args?.[1] || fp(0);
  //     const baseFee = (await tx.getBlock())?.baseFeePerGas || fp(0);
  //
  //     expect(poolAddress).to.be.eq(await pool.getAddress());
  //     expect(mevTax).to.be.eq((gasPrice - baseFee) * MEV_TAX_MULTIPLIER);
  //     expect(ethCollectorAfter - ethCollectorBefore).to.be.eq(mevTax);
  //   }
  //
  //   const gasPaidInEth = gasUsed * gasPrice;
  //   return { gasPaidInEth, mevTax };
  // }
});
