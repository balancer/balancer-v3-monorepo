import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MAX_UINT256, MAX_UINT160, MAX_UINT48 } from '@balancer-labs/v3-helpers/src/constants';
import { IRouterMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { VoidSigner } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import * as RouterDeployer from '@balancer-labs/v3-helpers/src/models/vault/RouterDeployer';
import { PoolFactoryMock, PoolMock, RouterMock, Vault } from '@balancer-labs/v3-vault/typechain-types';
import { buildTokenConfig } from './poolSetup';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { sortAddresses } from '@balancer-labs/v3-helpers/src/models/tokens/sortingHelper';
import { WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { IPermit2 } from '../typechain-types/permit2/src/interfaces/IPermit2';
import { deployPermit2 } from './Permit2Deployer';

describe('Queries', function () {
  let permit2: IPermit2;
  let vault: Vault;
  let router: IRouterMock;
  let factory: PoolFactoryMock;
  let pool: PoolMock;
  let DAI: ERC20TestToken;
  let USDC: ERC20TestToken;
  let WETH: WETHTestToken;
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
    WETH = await deploy('v3-solidity-utils/WETHTestToken');
    permit2 = await deployPermit2();
    router = await RouterDeployer.deployRouter(vaultAddress, WETH, permit2);

    DAI = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['DAI', 'Token A', 18] });
    USDC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['USDC', 'USDC', 18] });
    const tokenAddresses = sortAddresses([await DAI.getAddress(), await USDC.getAddress()]);

    pool = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool', 'POOL'],
    });

    factory = await deploy('PoolFactoryMock', { args: [vaultAddress, 12 * MONTH] });

    await factory.registerTestPool(pool, buildTokenConfig([await DAI.getAddress(), await USDC.getAddress()].sort()));

    await USDC.mint(alice, 2n * USDC_AMOUNT_IN);
    await DAI.mint(alice, 2n * DAI_AMOUNT_IN);

    await pool.connect(alice).approve(router, MAX_UINT256);
    for (const token of [USDC, DAI]) {
      await token.connect(alice).approve(permit2, MAX_UINT256);
      await permit2.connect(alice).approve(token, router, MAX_UINT160, MAX_UINT48);
    }

    // The mock pool can be initialized with no liquidity; it mints some BPT to the initializer
    // to comply with the Vault's required minimum.
    // Also need to sort the amounts, or initialization would break if we made DAI_AMOUNT_IN != USDC_AMOUNT_IN.

    const tokenAmounts =
      tokenAddresses[0] == (await DAI.getAddress())
        ? [2n * DAI_AMOUNT_IN, 2n * USDC_AMOUNT_IN]
        : [2n * USDC_AMOUNT_IN, 2n * DAI_AMOUNT_IN];

    await router.connect(alice).initialize(pool, tokenAddresses, tokenAmounts, 0, false, '0x');
  });

  describe('swap', () => {
    const DAI_AMOUNT_OUT = fp(250);

    it('queries a swap exact in correctly', async () => {
      const amountCalculated = await router
        .connect(zero)
        .querySwapSingleTokenExactIn.staticCall(pool, USDC, DAI, USDC_AMOUNT_IN, zero.address, '0x');
      expect(amountCalculated).to.be.eq(DAI_AMOUNT_IN);
    });

    it('queries a swap exact out correctly', async () => {
      const amountCalculated = await router
        .connect(zero)
        .querySwapSingleTokenExactOut.staticCall(pool, USDC, DAI, DAI_AMOUNT_OUT, zero.address, '0x');
      expect(amountCalculated).to.be.eq(DAI_AMOUNT_OUT);
    });

    it('reverts if not a static call (exact in)', async () => {
      await expect(
        router.querySwapSingleTokenExactIn.staticCall(pool, USDC, DAI, USDC_AMOUNT_IN, zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });

    it('reverts if not a static call (exact out)', async () => {
      await expect(
        router.querySwapSingleTokenExactOut.staticCall(pool, USDC, DAI, DAI_AMOUNT_OUT, zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquidityProportional', () => {
    it('queries addLiquidityProportional correctly', async () => {
      const amountsIn = await router
        .connect(zero)
        .queryAddLiquidityProportional.staticCall(pool, BPT_AMOUNT, zero.address, '0x');
      expect(amountsIn).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidityProportional.staticCall(pool, BPT_AMOUNT, zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquidityUnbalanced', () => {
    it('queries addLiquidityUnbalanced correctly', async () => {
      const bptAmountOut = await router
        .connect(zero)
        .queryAddLiquidityUnbalanced.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], zero.address, '0x');
      expect(bptAmountOut).to.be.eq(BPT_AMOUNT - 2n); // addLiquidity unbalanced has rounding error favoring the Vault.
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidityUnbalanced.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquiditySingleTokenExactOut', () => {
    it('queries addLiquiditySingleTokenExactOut correctly', async () => {
      const amountsIn = await router
        .connect(zero)
        .queryAddLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN * 2n, zero.address, '0x');
      expect(amountsIn).to.be.eq(DAI_AMOUNT_IN * 2n);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN * 2n, zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('addLiquidityCustom', () => {
    it('queries addLiquidityCustom correctly', async () => {
      const { amountsIn, bptAmountOut, returnData } = await router
        .connect(zero)
        .queryAddLiquidityCustom.staticCall(pool, [DAI_AMOUNT_IN, USDC_AMOUNT_IN], BPT_AMOUNT, zero.address, '0xbeef');
      expect(amountsIn).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
      expect(bptAmountOut).to.be.eq(BPT_AMOUNT);
      expect(returnData).to.be.eq('0xbeef');
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidityCustom.staticCall(
          pool,
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          BPT_AMOUNT,
          zero.address,
          '0xbeef'
        )
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquidityProportional', () => {
    it('queries removeLiquidityProportional correctly', async () => {
      const amountsOut = await router
        .connect(zero)
        .queryRemoveLiquidityProportional.staticCall(pool, BPT_AMOUNT, zero.address, '0x');

      expect(amountsOut[0]).to.be.eq(DAI_AMOUNT_IN);
      expect(amountsOut[1]).to.be.eq(USDC_AMOUNT_IN);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquidityProportional.staticCall(pool, BPT_AMOUNT, zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquiditySingleTokenExactIn', () => {
    it('queries removeLiquiditySingleTokenExactIn correctly', async () => {
      const amountOut = await router
        .connect(zero)
        .queryRemoveLiquiditySingleTokenExactIn.staticCall(pool, BPT_AMOUNT, DAI, zero.address, '0x');

      expect(amountOut).to.be.eq(DAI_AMOUNT_IN * 2n);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquiditySingleTokenExactIn.staticCall(pool, BPT_AMOUNT, DAI, zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquiditySingleTokenExactOut', () => {
    it('queries removeLiquiditySingleTokenExactOut correctly', async () => {
      const amountIn = await router
        .connect(zero)
        .queryRemoveLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN, zero.address, '0x');

      expect(amountIn).to.be.eq(BPT_AMOUNT / 2n + 2n); // Has rounding error favoring the Vault.
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquiditySingleTokenExactOut.staticCall(pool, DAI, DAI_AMOUNT_IN, zero.address, '0x')
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquidityCustom', () => {
    it('queries removeLiquidityCustom correctly', async () => {
      const { bptAmountIn, amountsOut, returnData } = await router
        .connect(zero)
        .queryRemoveLiquidityCustom.staticCall(
          pool,
          BPT_AMOUNT,
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          zero.address,
          '0xbeef'
        );

      expect(bptAmountIn).to.be.eq(BPT_AMOUNT);
      expect(amountsOut).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
      expect(returnData).to.be.eq('0xbeef');
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquidityCustom.staticCall(
          pool,
          BPT_AMOUNT,
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          zero.address,
          '0xbeef'
        )
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('query and revert', () => {
    let router: RouterMock;

    sharedBeforeEach('deploy mock router', async () => {
      router = await RouterDeployer.deployRouterMock(await vault.getAddress(), WETH, permit2);
    });

    describe('swap', () => {
      it('queries a swap exact in correctly', async () => {
        const amountCalculated = await router
          .connect(zero)
          .querySwapSingleTokenExactInAndRevert.staticCall(pool, USDC, DAI, USDC_AMOUNT_IN, '0x');
        expect(amountCalculated).to.be.eq(DAI_AMOUNT_IN);
      });

      it('reverts if not a static call (exact in)', async () => {
        await expect(
          router.querySwapSingleTokenExactInAndRevert.staticCall(pool, USDC, DAI, USDC_AMOUNT_IN, '0x')
        ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
      });

      it('handles query spoofs', async () => {
        await expect(router.connect(zero).querySpoof.staticCall()).to.be.revertedWithCustomError(
          vault,
          'QuoteResultSpoofed'
        );
      });

      it('handles custom error codes', async () => {
        await expect(router.connect(zero).queryRevertErrorCode.staticCall()).to.be.revertedWithCustomError(
          router,
          'MockErrorCode'
        );
      });

      it('handles legacy errors', async () => {
        await expect(router.connect(zero).queryRevertLegacy.staticCall()).to.be.revertedWith('Legacy revert reason');
      });

      it('handles revert with no reason', async () => {
        await expect(router.connect(zero).queryRevertNoReason.staticCall()).to.be.revertedWithCustomError(
          router,
          'ErrorSelectorNotFound'
        );
      });

      it('handles panic', async () => {
        await expect(router.connect(zero).queryRevertPanic.staticCall()).to.be.revertedWithPanic();
      });
    });
  });
});
