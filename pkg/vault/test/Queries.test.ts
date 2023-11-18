import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { WETH, MAX_UINT256 } from '@balancer-labs/v3-helpers/src/constants';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { Router } from '../typechain-types/contracts/Router';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/BasicAuthorizerMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { VoidSigner } from 'ethers';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';

describe('Queries', function () {
  let vault: VaultMock;
  let router: Router;
  let pool: PoolMock;
  let authorizer: BasicAuthorizerMock;
  let DAI: ERC20TestToken;
  let USDC: ERC20TestToken;
  let zero: VoidSigner;

  const DAI_AMOUNT_IN = fp(1000);
  const USDC_AMOUNT_IN = fp(1000);

  let alice: SignerWithAddress;

  const ADD_LIQUIDITY_TEST_KIND = 1; // UNBALANCED
  const REMOVE_LIQUIDITY_TEST_KIND = 0; // PROPORTIONAL

  before('setup signers', async () => {
    zero = new VoidSigner('0x0000000000000000000000000000000000000000', ethers.provider);
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    authorizer = await deploy('v3-solidity-utils/BasicAuthorizerMock');
    vault = await deploy('VaultMock', { args: [authorizer.getAddress(), MONTH * 3, MONTH] });
    const vaultAddress = await vault.getAddress();
    router = await deploy('Router', { args: [vaultAddress, WETH] });

    DAI = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['DAI', 'Token A', 18] });
    USDC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['USDC', 'USDC', 18] });

    pool = await deploy('v3-vault/PoolMock', {
      args: [vaultAddress, 'Pool', 'POOL', [DAI, USDC], true],
    });

    await USDC.mint(alice, USDC_AMOUNT_IN);
    await DAI.mint(alice, DAI_AMOUNT_IN);

    await USDC.connect(alice).approve(vault, MAX_UINT256);
    await DAI.connect(alice).approve(vault, MAX_UINT256);

    await router.connect(alice).initialize(await pool.getAddress(), [DAI, USDC], [0, 0], 0, '0x');
  });

  describe('swap', () => {
    sharedBeforeEach('add liquidity', async () => {
      await router
        .connect(alice)
        .addLiquidity(
          await pool.getAddress(),
          [DAI, USDC],
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          0,
          ADD_LIQUIDITY_TEST_KIND,
          '0x'
        );
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
        .queryAddLiquidity.staticCall(
          pool,
          [DAI, USDC],
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          DAI_AMOUNT_IN,
          ADD_LIQUIDITY_TEST_KIND,
          '0x'
        );
      expect(amountsIn).to.be.deep.eq([DAI_AMOUNT_IN, USDC_AMOUNT_IN]);
      expect(bptAmountOut).to.be.eq(DAI_AMOUNT_IN);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryAddLiquidity.staticCall(
          pool,
          [DAI, USDC],
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          DAI_AMOUNT_IN,
          ADD_LIQUIDITY_TEST_KIND,
          '0x'
        )
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });

  describe('removeLiquidity', () => {
    sharedBeforeEach('add liquidity', async () => {
      await router
        .connect(alice)
        .addLiquidity(
          await pool.getAddress(),
          [DAI, USDC],
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          DAI_AMOUNT_IN,
          ADD_LIQUIDITY_TEST_KIND,
          '0x'
        );
    });

    it('queries removeLiquidity correctly', async () => {
      const { amountsOut, bptAmountIn } = await router
        .connect(zero)
        .queryRemoveLiquidity.staticCall(
          pool,
          [DAI, USDC],
          DAI_AMOUNT_IN,
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          REMOVE_LIQUIDITY_TEST_KIND,
          '0x'
        );

      expect(amountsOut[0]).to.be.almostEqual(DAI_AMOUNT_IN);
      expect(amountsOut[1]).to.be.almostEqual(USDC_AMOUNT_IN);
      expect(bptAmountIn).to.be.almostEqual(DAI_AMOUNT_IN);
    });

    it('reverts if not a static call', async () => {
      await expect(
        router.queryRemoveLiquidity.staticCall(
          pool,
          [DAI, USDC],
          DAI_AMOUNT_IN,
          [DAI_AMOUNT_IN, USDC_AMOUNT_IN],
          REMOVE_LIQUIDITY_TEST_KIND,
          '0x'
        )
      ).to.be.revertedWithCustomError(vault, 'NotStaticCall');
    });
  });
});
