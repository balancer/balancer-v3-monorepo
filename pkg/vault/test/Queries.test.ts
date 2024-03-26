import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { Router } from '../typechain-types/contracts/Router';
import { ERC20PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/ERC20PoolMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { VoidSigner } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { Vault } from '@balancer-labs/v3-vault/typechain-types';
import { buildTokenConfig } from './poolSetup';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';

describe('Queries', function () {
  let vault: Vault;
  let router: Router;
  let pool: ERC20PoolMock;
  let DAI: ERC20TestToken;
  let USDC: ERC20TestToken;
  let zero: VoidSigner;

  const DAI_AMOUNT_IN = fp(1000);
  const USDC_AMOUNT_IN = fp(1000);
  const BPT_AMOUNT = fp(2000);

  let alice: SignerWithAddress;

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await VaultDeployer.deploy();
    const vaultAddress = await vault.getAddress();
    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('Router', { args: [vaultAddress, WETH] });

    DAI = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['DAI', 'Token A', 18] });
    USDC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['USDC', 'USDC', 18] });
    const tokenAddresses = sortAddresses([await DAI.getAddress(), await USDC.getAddress()]);

    pool = await deploy('v3-vault/PoolMock', {
      args: [
        vaultAddress,
        'Pool',
        'POOL',
        buildTokenConfig(tokenAddresses),
        true,
        365 * 24 * 3600,
        ZERO_ADDRESS,
        ZERO_ADDRESS,
      ],
    });

    await USDC.mint(alice, 2n * USDC_AMOUNT_IN);
    await DAI.mint(alice, 2n * DAI_AMOUNT_IN);

    await USDC.connect(alice).approve(vault, MAX_UINT256);
    await DAI.connect(alice).approve(vault, MAX_UINT256);

    // The mock pool can be initialized with no liquidity; it mints some BPT to the initializer
    // to comply with the vault's required minimum.
    // Also need to sort the amounts, or initialization would break if we made DAI_AMOUNT_IN != USDC_AMOUNT_IN

    const tokenAmounts =
      tokenAddresses[0] == (await DAI.getAddress())
        ? [2n * DAI_AMOUNT_IN, 2n * USDC_AMOUNT_IN]
        : [2n * USDC_AMOUNT_IN, 2n * DAI_AMOUNT_IN];

    await router.connect(alice).initialize(pool, tokenAddresses, tokenAmounts, 0, false, '0x');
  });

  // TODO: query a pool that has an actual invariant (introduced in #145)
  describe('swap', () => {
    const DAI_AMOUNT_OUT = fp(250);

    it('queries a swap exact in correctly', async () => {
      const amountCalculated = await router
        .connect(zero)
        .querySwapSingleTokenExactIn.staticCall(pool, USDC, DAI, USDC_AMOUNT_IN, '0x');
      expect(amountCalculated).to.be.eq(DAI_AMOUNT_IN);
    });

    it('queries a swap exact out correctly', async () => {
      const amountCalculated = await router
        .connect(zero)
        .querySwapSingleTokenExactOut.staticCall(pool, USDC, DAI, DAI_AMOUNT_OUT, '0x');
      expect(amountCalculated).to.be.eq(DAI_AMOUNT_OUT);
    });

    it('reverts if not a static call (exact in)', async () => {
      await expect(
        router.querySwapSingleTokenExactIn.staticCall(pool, USDC, DAI, USDC_AMOUNT_IN, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });

    it('reverts if not a static call (exact out)', async () => {
      await expect(
        router.querySwapSingleTokenExactOut.staticCall(pool, USDC, DAI, DAI_AMOUNT_OUT, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquidityProportional', () => {
    it('queries addLiquidityProportional correctly', async () => {
      const amountsIn = await router
        .connect(zero)
        .queryAddLiquidityProportional.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, '0x');
      expect(amountsIn).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidityProportional.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquidityUnbalanced', () => {
    it('queries addLiquidityUnbalanced correctly', async () => {
      const bptAmountOut = await router
        .connect(zero)
        .queryAddLiquidityUnbalanced.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], '0x');
      expect(bptAmountOut).to.be.eq(BPT_AMOUNT);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidityUnbalanced.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquiditySingleTokenExactOut', () => {
    it('queries addLiquiditySingleTokenExactOut correctly', async () => {
      const amountsIn = await router
        .connect(zero)
        .queryAddLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN * 2n, '0x');
      expect(amountsIn).to.be.eq(DAI_AMOUNT_IN * 2n);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN * 2n, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquidityCustom', () => {
    it('queries addLiquidityCustom correctly', async () => {
      const { amountsIn, bptAmountOut, returnData } = await router
        .connect(zero)
        .queryAddLiquidityCustom.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, '0xbeef');
      expect(amountsIn).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
      expect(bptAmountOut).to.be.eq(BPT_AMOUNT);
      expect(returnData).to.be.eq('0xbeef');
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidityCustom.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, '0xbeef')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquidityProportional', () => {
    it('queries removeLiquidityProportional correctly', async () => {
      const amountsOut = await router.connect(zero).queryRemoveLiquidityProportional.staticCall(pool, BPT_AMOUNT, '0x');

      expect(amountsOut[0]).to.be.eq(DAI_AMOUNT_IN);
      expect(amountsOut[1]).to.be.eq(USDC_AMOUNT_IN);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquidityProportional.staticCall(pool, BPT_AMOUNT, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquiditySingleTokenExactIn', () => {
    it('queries removeLiquiditySingleTokenExactIn correctly', async () => {
      const amountOut = await router
        .connect(zero)
        .queryRemoveLiquiditySingleTokenExactIn.staticCall(pool, BPT_AMOUNT, DAI, '0x');

      expect(amountOut).to.be.eq(DAI_AMOUNT_IN * 2n);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquiditySingleTokenExactIn.staticCall(pool, BPT_AMOUNT, DAI, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquiditySingleTokenExactOut', () => {
    it('queries removeLiquiditySingleTokenExactOut correctly', async () => {
      const amountIn = await router
        .connect(zero)
        .queryRemoveLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN, '0x');

      expect(amountIn).to.be.eq(BPT_AMOUNT / 2n);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquidityCustom', () => {
    it('queries removeLiquidityCustom correctly', async () => {
      const { bptAmountIn, amountsOut, returnData } = await router
        .connect(zero)
        .queryRemoveLiquidityCustom.staticCall(pool, BPT_AMOUNT, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], '0xbeef');

      expect(bptAmountIn).to.be.eq(BPT_AMOUNT);
      expect(amountsOut).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
      expect(returnData).to.be.eq('0xbeef');
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquidityCustom.staticCall(pool, BPT_AMOUNT, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], '0xbeef')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });
});
