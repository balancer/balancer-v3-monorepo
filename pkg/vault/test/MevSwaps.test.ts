import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';

import { PoolMock } from '../typechain-types/contracts/test/PoolMock';
import { Router, MevRouter, MevTaxCollectorMock, PoolFactoryMock, Vault, WETHTestToken } from '../typechain-types';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { VoidSigner } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { deployPermit2 } from './Permit2Deployer';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { buildTokenConfig } from './poolSetup';
import { MAX_UINT160, MAX_UINT256, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';

describe('MevSwaps', () => {
  const MEV_ROUTER_VERSION = 'MevRouter v1';
  const ROUTER_VERSION = 'Router v9';

  let permit2: IPermit2;
  let vault: Vault;
  let factory: PoolFactoryMock;
  let poolWithEth: PoolMock, poolWithoutEth: PoolMock;
  let poolWithEthTokens: string[], poolWithoutEthTokens: string[];
  let router: MevRouter, basicRouter: Router;

  let lp: SignerWithAddress, sender: SignerWithAddress, zero: VoidSigner;

  let tokens: ERC20TokenList;
  let token0: string, token1: string, WETH: WETHTestToken;
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
    const collector: MevTaxCollectorMock = await deploy('MevTaxCollectorMock');
    const routerParams = {
      mevTaxCollector: await collector.getAddress(),
      mevTaxMultiplier: 9,
      priorityGasThreshold: fp(1),
    };
    router = await deploy('MevRouter', { args: [vaultAddress, WETH, permit2, MEV_ROUTER_VERSION, routerParams] });
    basicRouter = await deploy('Router', { args: [vaultAddress, WETH, permit2, ROUTER_VERSION] });
    factory = await deploy('PoolFactoryMock', { args: [vaultAddress, 12 * MONTH] });

    tokens = await ERC20TokenList.create(2, { sorted: true });
    token0 = await tokens.get(0).getAddress();
    token1 = await tokens.get(1).getAddress();
    poolWithEthTokens = sortAddresses([await WETH.getAddress(), token1]);
    poolWithoutEthTokens = sortAddresses([token0, token1]);

    poolWithEth = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool With Eth', 'POOL-ETH'],
    });

    poolWithoutEth = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool Without Eth', 'POOL-NETH'],
    });

    await factory.registerTestPool(poolWithEth, buildTokenConfig(poolWithEthTokens));
    await factory.registerTestPool(poolWithoutEth, buildTokenConfig(poolWithoutEthTokens));
  });

  sharedBeforeEach('allowances', async () => {
    const pools = [poolWithEth, poolWithoutEth];

    await WETH.connect(lp).deposit({ value: fp(1000) });
    await WETH.connect(sender).deposit({ value: fp(1000) });

    await tokens.mint({ to: lp, amount: fp(1e12) });
    await tokens.mint({ to: sender, amount: fp(1e12) });
    for (const pool of pools) {
      await pool.connect(lp).approve(router, MAX_UINT256);
      await pool.connect(lp).approve(basicRouter, MAX_UINT256);
    }
    for (const token of [...tokens.tokens, WETH, poolWithEth, poolWithoutEth]) {
      for (const from of [lp, sender]) {
        await token.connect(from).approve(permit2, MAX_UINT256);
        for (const to of [router, basicRouter]) {
          await permit2.connect(from).approve(token, to, MAX_UINT160, MAX_UINT48);
        }
      }
    }
  });

  sharedBeforeEach('initialize pools', async () => {
    await basicRouter
      .connect(lp)
      .initialize(poolWithEth, poolWithEthTokens, Array(poolWithEthTokens.length).fill(fp(1000)), 0, false, '0x');
    await basicRouter
      .connect(lp)
      .initialize(
        poolWithoutEth,
        poolWithoutEthTokens,
        Array(poolWithoutEthTokens.length).fill(fp(1000)),
        0,
        false,
        '0x'
      );

    await poolWithEth.connect(lp).transfer(sender, fp(100));
    await poolWithoutEth.connect(lp).transfer(sender, fp(100));
  });

  it('true', () => {
    console.log('yes');
  });
});
