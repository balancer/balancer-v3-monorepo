import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { Router } from '../typechain-types/contracts/Router';
import { ERC20PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/ERC20PoolMock';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/BasicAuthorizerMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { VoidSigner } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';

describe('Queries', function () {
  let vault: VaultMock;
  let router: Router;
  let pool: ERC20PoolMock;
  let authorizer: BasicAuthorizerMock;
  let DAI: ERC20TestToken;
  let USDC: ERC20TestToken;
  let zero: VoidSigner;

  const DAI_AMOUNT_IN = fp(1000);
  const USDC_AMOUNT_IN = fp(1000);
  const BPT_AMOUNT = fp(1000);

  let alice: SignerWithAddress;

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    authorizer = await deploy('v3-solidity-utils/BasicAuthorizerMock');
    vault = await deploy('VaultMock', { args: [authorizer.getAddress(), MONTH * 3, MONTH] });
    const vaultAddress = await vault.getAddress();
    const WETH = await deploy('v3-solidity-utils/WETHTestToken');
    router = await deploy('Router', { args: [vaultAddress, WETH] });

    DAI = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['DAI', 'Token A', 18] });
    USDC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['USDC', 'USDC', 18] });

    pool = await deploy('v3-vault/ERC20PoolMock', {
      args: [vaultAddress, 'Pool', 'POOL', [DAI, USDC], [ZERO_ADDRESS, ZERO_ADDRESS], true, 0, ZERO_ADDRESS],
    });

    await USDC.mint(alice, USDC_AMOUNT_IN * 100n);
    await DAI.mint(alice, DAI_AMOUNT_IN * 100n);

    await USDC.connect(alice).approve(vault, MAX_UINT256);
    await DAI.connect(alice).approve(vault, MAX_UINT256);

    // Initializing it like this makes the BPT supply be 1:1 with the deposited tokens.
    const minInitBpt = await pool.MIN_INIT_BPT();
    await router
      .connect(alice)
      .initialize(await pool.getAddress(), [DAI, USDC], [minInitBpt, minInitBpt], 0, false, '0x');
  });

  describe('swap', () => {
    sharedBeforeEach('add liquidity', async () => {
      await router
        .connect(alice)
        .addLiquidityUnbalanced(await pool.getAddress(), [DAI_AMOUNT_IN, USDC_AMOUNT_IN], 0, false, '0x');
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
        .queryAddLiquidityUnbalanced.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, '0x');
      expect(bptAmountOut).to.be.eq(BPT_AMOUNT);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidityUnbalanced.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquiditySingleTokenExactOut', () => {
    it('queries addLiquiditySingleTokenExactOut correctly', async () => {
      const amountsIn = await router
        .connect(zero)
        .queryAddLiquiditySingleTokenExactOut.staticCall(pool, 0, DAI_AMOUNT_IN, BPT_AMOUNT, '0x');
      expect(amountsIn).to.be.deep.eq([DAI_AMOUNT_IN, 0]);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquiditySingleTokenExactOut.staticCall(pool, 0, DAI_AMOUNT_IN, BPT_AMOUNT, '0x')
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

  describe('remove', () => {
    sharedBeforeEach('add liquidity', async () => {
      await router
        .connect(alice)
        .addLiquidityUnbalanced(await pool.getAddress(), [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, false, '0x');
    });

    describe('removeLiquidityProportional', () => {
      it('queries removeLiquidityProportional correctly', async () => {
        const amountsOut = await router
          .connect(zero)
          .queryRemoveLiquidityProportional.staticCall(pool, BPT_AMOUNT, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], '0x');

        // Accept some error in the proportional math.
        expect(amountsOut[0]).to.be.almostEqual(DAI_AMOUNT_IN, 1e-9);
        expect(amountsOut[1]).to.be.almostEqual(USDC_AMOUNT_IN, 1e-9);
      });

      it('reverts if not a static call', async () => {
        await expect(
          router.queryRemoveLiquidityProportional.staticCall(pool, BPT_AMOUNT, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], '0x')
        ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
      });
    });

    describe('removeLiquiditySingleTokenExactIn', () => {
      it('queries removeLiquiditySingleTokenExactIn correctly', async () => {
        const amountsOut = await router
          .connect(zero)
          .queryRemoveLiquiditySingleTokenExactIn.staticCall(pool, BPT_AMOUNT, 0, DAI_AMOUNT_IN, '0x');

        expect(amountsOut[0]).to.be.almostEqual(DAI_AMOUNT_IN, 1e-9);
        expect(amountsOut[1]).to.be.eq(0);
      });

      it('reverts if not a static call', async () => {
        await expect(
          router.queryRemoveLiquiditySingleTokenExactIn.staticCall(pool, BPT_AMOUNT, 0, DAI_AMOUNT_IN, '0x')
        ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
      });
    });

    describe('removeLiquiditySingleTokenExactOut', () => {
      it('queries removeLiquiditySingleTokenExactOut correctly', async () => {
        const amountIn = await router
          .connect(zero)
          .queryRemoveLiquiditySingleTokenExactOut.staticCall(pool, BPT_AMOUNT, 0, DAI_AMOUNT_IN, '0x');

        expect(amountIn).to.be.eq(BPT_AMOUNT);
      });

      it('reverts if not a static call', async () => {
        await expect(
          router.queryRemoveLiquiditySingleTokenExactOut.staticCall(pool, BPT_AMOUNT, 0, DAI_AMOUNT_IN, '0x')
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
});
