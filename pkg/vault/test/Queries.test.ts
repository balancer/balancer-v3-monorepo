import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { WETH, MAX_UINT256 } from '@balancer-labs/v3-helpers/src/constants';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { Router } from '../typechain-types/contracts/test/Router';
import { BasePoolToken } from '../typechain-types/contracts/BasePoolToken';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { VoidSigner } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';

describe('Queries', function () {
  let vault: VaultMock;
  let router: Router;
  let pool: BasePoolToken;
  let DAI: ERC20TestToken;
  let USDC: ERC20TestToken;
  let zero: VoidSigner;

  const DAI_AMOUNT_IN = fp(1000);
  const USDC_AMOUNT_IN = fp(1000);

  let factory: SignerWithAddress;
  let alice: SignerWithAddress;

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, factory, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await deploy('VaultMock', { args: [MONTH * 3, MONTH] });
    const vaultAddress = await vault.getAddress();
    router = await deploy('Router', { args: [vaultAddress, WETH] });

    DAI = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['DAI', 'Token A', 18] });
    USDC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['USDC', 'USDC', 18] });

    pool = await deploy('ERC20PoolMock', {
      args: [vaultAddress, 'Pool', 'POOL', factory, [DAI, USDC], true],
    });

    await USDC.mint(alice, USDC_AMOUNT_IN);
    await DAI.mint(alice, DAI_AMOUNT_IN);

    await USDC.connect(alice).approve(vault, MAX_UINT256);
    await DAI.connect(alice).approve(vault, MAX_UINT256);
  });

  describe('swap', () => {
    sharedBeforeEach('add liquidity', async () => {
      await router
        .connect(alice)
        .addLiquidity(await pool.getAddress(), [DAI, USDC], [DAI_AMOUNT_IN, USDC_AMOUNT_IN], DAI_AMOUNT_IN, '0x');
    });

    it('queries a swap correctly', async () => {
      const amountCalculated = await router
        .connect(zero)
        .querySwap.staticCall(0, pool, USDC, DAI, USDC_AMOUNT_IN, '0x');
      expect(amountCalculated).to.be.eq(DAI_AMOUNT_IN);
    });

    it('reverts if not a static call', async () => {
      await expect(router.querySwap.staticCall(0, pool, USDC, DAI, USDC_AMOUNT_IN, '0x')).to.be.revertedWithCustomError(
        vault,
        'NotStaticCall'
      );
    });
  });

  describe('addLiquidity', () => {
    it('queries addLiquidity correctly', async () => {
      const { amountsIn, bptAmountOut } = await router
        .connect(zero)
        .queryAddLiquidity.staticCall(pool, [DAI, USDC], [DAI_AMOUNT_IN, USDC_AMOUNT_IN], DAI_AMOUNT_IN, '0x');
      expect(amountsIn).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
      expect(bptAmountOut).to.be.eq(DAI_AMOUNT_IN);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidity.staticCall(pool, [DAI, USDC], [DAI_AMOUNT_IN, USDC_AMOUNT_IN], DAI_AMOUNT_IN, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquidity', () => {
    sharedBeforeEach('add liquidity', async () => {
      await router
        .connect(alice)
        .addLiquidity(await pool.getAddress(), [DAI, USDC], [DAI_AMOUNT_IN, USDC_AMOUNT_IN], DAI_AMOUNT_IN, '0x');
    });

    it('queries a removeLiquidity correctly', async () => {
      const amountsOut = await router
        .connect(zero)
        .queryRemoveLiquidity.staticCall(pool, [DAI, USDC], [DAI_AMOUNT_IN, USDC_AMOUNT_IN], DAI_AMOUNT_IN, '0x');
      expect(amountsOut).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquidity.staticCall(pool, [DAI, USDC], [DAI_AMOUNT_IN, USDC_AMOUNT_IN], DAI_AMOUNT_IN, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });
});
