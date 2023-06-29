import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH, fromNow } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { BalancerPoolToken } from '../typechain-types/contracts/BalancerPoolToken';
import { ERC721BasePool } from '../typechain-types/contracts/ERC721BasePool';
import { ERC721MultiToken } from '../typechain-types/contracts/ERC721MultiToken';
import { TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { ANY_ADDRESS, MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import '@balancer-labs/v3-common/setupTests';
import { bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import { Typed } from 'ethers';

describe.only('ERC721MultiToken', function () {
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';

  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  let vault: VaultMock;
  let usdcPool: BalancerPoolToken;
  let usdtPool: BalancerPoolToken;
  let usdc: TestToken;
  let usdt: TestToken;

  let vaultAddress: string;

  let user: SignerWithAddress;
  let other: SignerWithAddress;
  let relayer: SignerWithAddress;
  let factory: SignerWithAddress;

  let usdcAddress: string;
  let usdtAddress: string;

  let usdcPoolAddress: string;
  let usdtPoolAddress: string;

  let tokenAddresses: string[];

  before('setup signers', async () => {
    [, user, other, factory, relayer] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await deploy('VaultMock', { args: [WETH, PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION] });
    vaultAddress = await vault.getAddress();

    usdc = await deploy('v3-solidity-utils/TestToken', { args: ['USDC', 'USDC', 6] });
    usdt = await deploy('v3-solidity-utils/TestToken', { args: ['USDT', 'USDT', 18] });

    usdcAddress = await usdc.getAddress();
    usdtAddress = await usdt.getAddress();

    tokenAddresses = [usdcAddress, usdtAddress];

    usdcPool = await deploy('ERC721BasePool', {
      args: [vaultAddress, factory, tokenAddresses, 'USDC Pool', 'POOL-USDC'],
    });
    usdtPool = await deploy('ERC721BasePool', {
      args: [vaultAddress, factory, tokenAddresses, 'USDT Pool', 'POOL-USDT'],
    });

    usdcPoolAddress = await usdcPool.getAddress();
    usdtPoolAddress = await usdtPool.getAddress();
  });

  describe('minting', async () => {
    const bptAmount = fp(100);

    it('vault can mint BPT', async () => {
      await vault.mint(usdcPoolAddress, user.address, bptAmount);

      // balanceOf directly on pool token
      expect(await usdcPool.balanceOf(user.address)).to.equal(bptAmount);
      expect(await usdtPool.balanceOf(user.address)).to.equal(0);

      // balanceOf indirectly, through vault
      expect(await vault.balanceOf(usdcPoolAddress, user.address)).to.equal(bptAmount);
      expect(await vault.balanceOf(usdtPoolAddress, user.address)).to.equal(0);

      // user has the total supply (directly on pool token)
      expect(await usdcPool.totalSupply()).to.equal(bptAmount);
      expect(await usdtPool.totalSupply()).to.equal(0);

      // user has the total supply (indirectly, through vault)
      expect(await vault.totalSupply(usdcPoolAddress)).to.equal(bptAmount);
      expect(await vault.totalSupply(usdtPoolAddress)).to.equal(0);
    });

    it('minting emits a transfer event on the token', async () => {
      await expect(await vault.mint(usdcPoolAddress, user.address, bptAmount))
        .to.emit(usdcPool, 'Transfer')
        .withArgs(ZERO_ADDRESS, user.address, bptAmount);
    });

    it('cannot mint to zero address', async () => {
      await expect(vault.mint(usdtPoolAddress, ZERO_ADDRESS, bptAmount)).to.be.revertedWith(
        'ERC20: mint to the zero address'
      );
    });
  });

  describe('minting', async () => {
    const bptAmount = fp(100);

    sharedBeforeEach('register the pool', async () => {
      await usdcPool.initialize(factory, tokenAddresses);
    });

    it('vault can mint BPT', async () => {
      await vault.mint(usdcPoolAddress, user.address, bptAmount);

      // balanceOf directly on pool token
      expect(await usdcPool.balanceOf(user.address)).to.equal(bptAmount);
      expect(await usdtPool.balanceOf(user.address)).to.equal(0);

      // balanceOf indirectly, through vault
      expect(await vault.balanceOf(usdcPoolAddress, user.address)).to.equal(bptAmount);
      expect(await vault.balanceOf(usdtPoolAddress, user.address)).to.equal(0);

      // user has the total supply (directly on pool token)
      expect(await usdcPool.totalSupply()).to.equal(bptAmount);
      expect(await usdtPool.totalSupply()).to.equal(0);

      // user has the total supply (indirectly, through vault)
      expect(await vault.totalSupply(usdcPoolAddress)).to.equal(bptAmount);
      expect(await vault.totalSupply(usdtPoolAddress)).to.equal(0);
    });

    it('minting emits a transfer event on the token', async () => {
      await expect(await vault.mint(usdcPoolAddress, user.address, bptAmount))
        .to.emit(usdcPool, 'Transfer')
        .withArgs(ZERO_ADDRESS, user.address, bptAmount);
    });

    it('cannot mint to zero address', async () => {
      await expect(vault.mint(usdtPoolAddress, ZERO_ADDRESS, bptAmount)).to.be.revertedWith(
        'ERC20: mint to the zero address'
      );
    });
  });

  describe('burning', async () => {
    const totalSupply = fp(100);
    const bptAmount = fp(32.5);

    sharedBeforeEach('register the pool, and mint initial supply', async () => {
      await usdcPool.initialize(factory, tokenAddresses);
      await vault.mint(usdcPoolAddress, user.address, totalSupply);
    });

    it('vault can burn BPT', async () => {
      await vault.burn(usdcPoolAddress, user.address, bptAmount);

      const remainingBalance = totalSupply - bptAmount;

      // balanceOf directly on pool token
      expect(await usdcPool.balanceOf(user.address)).to.equal(remainingBalance);

      // balanceOf indirectly, through vault
      expect(await vault.balanceOf(usdcPoolAddress, user.address)).to.equal(remainingBalance);

      // user has the total supply (directly on pool token)
      expect(await usdcPool.totalSupply()).to.equal(remainingBalance);

      // user has the total supply (indirectly, through vault)
      expect(await vault.totalSupply(usdcPoolAddress)).to.equal(remainingBalance);
    });

    it('burning emits a transfer event on the token', async () => {
      await expect(await vault.burn(usdcPoolAddress, user.address, bptAmount))
        .to.emit(usdcPool, 'Transfer')
        .withArgs(user.address, ZERO_ADDRESS, bptAmount);
    });

    it('cannot burn from the zero address', async () => {
      await expect(vault.burn(usdtPoolAddress, ZERO_ADDRESS, bptAmount)).to.be.revertedWith(
        'ERC20: burn from the zero address'
      );
    });

    it('cannot burn more than the balance', async () => {
      // User has zero balance of PoolB
      await expect(vault.burn(usdtPoolAddress, user.address, bptAmount)).to.be.revertedWith(
        'ERC20: burn amount exceeds balance'
      );
    });
  });

  describe('transfer', () => {
    const totalSupply = fp(50);
    const bptAmount = fp(18);

    const remainingBalance = totalSupply - bptAmount;

    sharedBeforeEach('register the pool, and mint initial supply', async () => {
      await usdcPool.initialize(factory, tokenAddresses);
      await vault.mint(usdcPoolAddress, user.address, totalSupply);
    });

    function itTransfersBPTCorrectly() {
      it('transfers BPT between users', async () => {
        expect(await usdcPool.balanceOf(user.address)).to.equal(remainingBalance);
        expect(await usdcPool.balanceOf(other.address)).to.equal(bptAmount);

        // Supply doesn't change
        expect(await usdcPool.totalSupply()).to.equal(totalSupply);
      });
    }

    it('transfers BPT directly', async () => {
      await usdcPool.connect(user).transfer(other.address, bptAmount);

      itTransfersBPTCorrectly();
    });

    it('transfers BPT through the vault', async () => {
      await vault.connect(user).transfer(usdcPoolAddress, user.address, other.address, bptAmount);

      itTransfersBPTCorrectly();
    });

    it('direct transfer emits a transfer event on the token', async () => {
      await expect(await usdcPool.connect(user).transfer(other.address, bptAmount))
        .to.emit(usdcPool, 'Transfer')
        .withArgs(user.address, other.address, bptAmount);
    });

    it('indirect transfer emits a transfer event on the token', async () => {
      await expect(await vault.connect(user).transfer(usdcPoolAddress, user.address, other.address, bptAmount))
        .to.emit(usdcPool, 'Transfer')
        .withArgs(user.address, other.address, bptAmount);
    });

    it('vault cannot transfer a non-BPT token', async () => {
      await DAI.mint(user.address, bptAmount);
      expect(await DAI.balanceOf(user.address)).to.equal(bptAmount);

      await expect(vault.connect(user).transfer(usdcAddress, user.address, other.address, bptAmount))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(usdcAddress);
    });

    it('cannot transfer from zero address', async () => {
      await expect(
        vault.connect(user).transfer(usdcPoolAddress, ZERO_ADDRESS, other.address, bptAmount)
      ).to.be.revertedWith('ERC20: transfer from the zero address');
    });

    it('cannot transfer to zero address', async () => {
      await expect(
        vault.connect(user).transfer(usdcPoolAddress, user.address, ZERO_ADDRESS, bptAmount)
      ).to.be.revertedWith('ERC20: transfer to the zero address');
    });

    it('cannot transfer more than balance', async () => {
      await expect(
        vault.connect(user).transfer(usdcPoolAddress, user.address, other.address, totalSupply + 1n)
      ).to.be.revertedWith('ERC20: transfer amount exceeds balance');
    });
  });

  describe('allowance', () => {
    const bptAmount = fp(72);

    sharedBeforeEach('register the pool', async () => {
      await usdcPool.initialize(factory, tokenAddresses);
    });

    function itSetsApprovalsCorrectly() {
      it('sets approval', async () => {
        expect(await usdcPool.allowance(user.address, relayer.address)).to.equal(bptAmount);
        expect(await usdcPool.allowance(user.address, other.address)).to.equal(0);

        expect(await vault.allowance(usdcPoolAddress, user.address, relayer.address)).to.equal(bptAmount);
        expect(await vault.allowance(usdcPoolAddress, user.address, other.address)).to.equal(0);
      });
    }

    context('sets approval directly', async () => {
      sharedBeforeEach('set approval', async () => {
        await usdcPool.connect(user).approve(relayer.address, bptAmount);
      });

      itSetsApprovalsCorrectly();
    });

    context('sets approval through the vault', async () => {
      sharedBeforeEach('set approval', async () => {
        await vault.connect(user).approve(usdcPoolAddress, user.address, relayer.address, bptAmount);
      });

      itSetsApprovalsCorrectly();
    });

    it('direct approval emits an event on the token', async () => {
      await expect(await usdcPool.connect(user).approve(relayer.address, bptAmount))
        .to.emit(usdcPool, 'Approval')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('indirect approval emits an event on the token', async () => {
      await expect(await vault.connect(user).approve(usdcPoolAddress, user.address, relayer.address, bptAmount))
        .to.emit(usdcPool, 'Approval')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('cannot approve from zero address', async () => {
      await expect(
        vault.connect(user).approve(usdcPoolAddress, ZERO_ADDRESS, other.address, bptAmount)
      ).to.be.revertedWith('ERC20: approve from the zero address');
    });

    it('cannot approve to zero address', async () => {
      await expect(
        vault.connect(user).approve(usdcPoolAddress, user.address, ZERO_ADDRESS, bptAmount)
      ).to.be.revertedWith('ERC20: approve to the zero address');
    });
  });

  describe('transferFrom', () => {
    const totalSupply = fp(50);
    const bptAmount = fp(18);

    const remainingBalance = totalSupply - bptAmount;

    sharedBeforeEach('register the pool, mint initial supply, and approve transfer', async () => {
      await usdcPool.initialize(factory, tokenAddresses);
      await vault.mint(usdcPoolAddress, user.address, totalSupply);
      await usdcPool.connect(user).approve(relayer.address, bptAmount);
    });

    function itTransfersBPTCorrectly() {
      it('relayer can transfer BPT', async () => {
        expect(await usdcPool.balanceOf(user.address)).to.equal(remainingBalance);
        expect(await usdcPool.balanceOf(relayer.address)).to.equal(bptAmount);

        // Supply doesn't change
        expect(await usdcPool.totalSupply()).to.equal(totalSupply);
      });
    }

    context('transfers BPT directly', async () => {
      sharedBeforeEach('direct transferFrom', async () => {
        await usdcPool.connect(relayer).transferFrom(user.address, relayer.address, bptAmount);
      });

      itTransfersBPTCorrectly();
    });

    context('transfers BPT through the vault', async () => {
      sharedBeforeEach('indirect transferFrom', async () => {
        await vault.connect(relayer).transfer(usdcPoolAddress, user.address, relayer.address, bptAmount);
      });

      itTransfersBPTCorrectly();
    });

    it('direct transfer emits a transfer event on the token', async () => {
      await expect(await usdcPool.connect(relayer).transferFrom(user.address, relayer.address, bptAmount))
        .to.emit(usdcPool, 'Transfer')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('indirect transfer emits a transfer event on the token', async () => {
      await expect(
        await vault
          .connect(relayer)
          .transferFrom(usdcPoolAddress, relayer.address, user.address, relayer.address, bptAmount)
      )
        .to.emit(usdcPool, 'Transfer')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('vault cannot transfer a non-BPT token', async () => {
      await DAI.mint(user.address, bptAmount);
      expect(await DAI.balanceOf(user.address)).to.equal(bptAmount);

      await expect(
        vault.connect(relayer).transferFrom(usdcAddress, relayer.address, user.address, relayer.address, bptAmount)
      )
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(usdcAddress);
    });

    it('cannot transfer to zero address', async () => {
      await expect(
        vault.connect(relayer).transferFrom(usdcPoolAddress, relayer.address, user.address, ZERO_ADDRESS, bptAmount)
      ).to.be.revertedWith('ERC20: transfer to the zero address');
    });

    it('cannot transfer more than balance', async () => {
      // Give infinite allowance
      await usdcPool.connect(user).approve(relayer.address, MAX_UINT256);

      await expect(
        vault
          .connect(user)
          .transferFrom(usdcPoolAddress, relayer.address, user.address, other.address, totalSupply + 1n)
      ).to.be.revertedWith('ERC20: transfer amount exceeds balance');
    });

    it('cannot transfer more than allowance', async () => {
      await expect(
        vault.connect(user).transferFrom(usdcPoolAddress, relayer.address, user.address, other.address, bptAmount + 1n)
      ).to.be.revertedWith('ERC20: insufficient allowance');
    });
  });
});
