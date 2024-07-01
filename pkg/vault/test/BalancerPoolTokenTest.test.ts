import { ethers } from 'hardhat';
import { expect } from 'chai';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { impersonate } from '@balancer-labs/v3-helpers/src/signers';
import { setupEnvironment } from './poolSetup';
import '@balancer-labs/v3-common/setupTests';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';

describe('BalancerPoolToken', function () {
  const PAUSE_WINDOW_DURATION = MONTH * 9;

  let vault: IVaultMock;
  let poolA: PoolMock;
  let poolB: PoolMock;

  let user: SignerWithAddress;
  let other: SignerWithAddress;
  let relayer: SignerWithAddress;

  let poolASigner: SignerWithAddress;

  let poolAAddress: string;
  let poolBAddress: string;

  before('setup signers', async () => {
    [, user, other, relayer] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { vault: vaultMock, pools } = await setupEnvironment(PAUSE_WINDOW_DURATION);
    vault = vaultMock;

    poolA = pools[0]; // This pool is registered
    poolB = pools[1]; // This pool is unregistered

    poolAAddress = await poolA.getAddress();
    poolBAddress = await poolB.getAddress();

    expect(await poolA.name()).to.equal('Pool A');
    expect(await poolA.symbol()).to.equal('POOL-A');
    expect(await poolA.decimals()).to.equal(18);

    expect(await poolB.name()).to.equal('Pool B');
    expect(await poolB.symbol()).to.equal('POOL-B');
    expect(await poolB.decimals()).to.equal(18);
  });

  sharedBeforeEach('', async () => {
    // Simulate a call from the real Pool by "casting" it as a Signer,
    // so it can be used with `connect` like an EOA
    poolASigner = await impersonate(poolAAddress);
  });

  describe('minting', async () => {
    const bptAmount = fp(100);

    it('vault can mint BPT', async () => {
      await vault.mintERC20(poolAAddress, user.address, bptAmount);

      // balanceOf directly on pool token
      expect(await poolA.balanceOf(user.address)).to.equal(bptAmount);
      expect(await poolB.balanceOf(user.address)).to.equal(0);

      // balanceOf indirectly, through vault
      expect(await vault.balanceOf(poolAAddress, user.address)).to.equal(bptAmount);
      expect(await vault.balanceOf(poolBAddress, user.address)).to.equal(0);

      // user has the total supply (directly on pool token)
      expect(await poolA.totalSupply()).to.equal(bptAmount);
      expect(await poolB.totalSupply()).to.equal(0);

      // user has the total supply (indirectly, through vault)
      expect(await vault.totalSupply(poolAAddress)).to.equal(bptAmount);
      expect(await vault.totalSupply(poolBAddress)).to.equal(0);
    });

    it('minting ERC20 BPT emits a transfer event on the token', async () => {
      await expect(await vault.mintERC20(poolAAddress, user.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(ZERO_ADDRESS, user.address, bptAmount);
    });

    it('cannot mint ERC20 BPT to zero address', async () => {
      await expect(vault.mintERC20(poolBAddress, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidReceiver')
        .withArgs(ZERO_ADDRESS);
    });
  });

  describe('burning', async () => {
    const totalSupply = fp(100);
    const bptAmount = fp(32.5);

    sharedBeforeEach('Mint initial ERC20 BPT supply of pool A', async () => {
      await vault.mintERC20(poolAAddress, user.address, totalSupply);
    });

    it('vault can burn ERC20 BPT', async () => {
      await vault.burnERC20(poolAAddress, user.address, bptAmount);

      const remainingBalance = totalSupply - bptAmount;

      // balanceOf directly on pool token
      expect(await poolA.balanceOf(user.address)).to.equal(remainingBalance);

      // balanceOf indirectly, through vault
      expect(await vault.balanceOf(poolAAddress, user.address)).to.equal(remainingBalance);

      // user has the total supply (directly on pool token)
      expect(await poolA.totalSupply()).to.equal(remainingBalance);

      // user has the total supply (indirectly, through vault)
      expect(await vault.totalSupply(poolAAddress)).to.equal(remainingBalance);
    });

    it('burning ERC20 BPT emits a transfer event on the token', async () => {
      await expect(await vault.burnERC20(poolAAddress, user.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, ZERO_ADDRESS, bptAmount);
    });

    it('cannot burn ERC20 BPT from the zero address', async () => {
      await expect(vault.burnERC20(poolBAddress, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidSender')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot burn more than the ERC20 BPT balance', async () => {
      // User has zero balance of PoolB
      await expect(vault.burnERC20(poolBAddress, user.address, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientBalance')
        .withArgs(user.address, 0, bptAmount);
    });
  });

  describe('transfer', () => {
    const totalSupply = fp(50);
    const bptAmount = fp(18);

    const remainingBalance = totalSupply - bptAmount;

    sharedBeforeEach('Mint initial ERC20 BPT supply of pool A', async () => {
      await vault.mintERC20(poolAAddress, user.address, totalSupply);
    });

    function itTransfersBPTCorrectly() {
      it('transfers BPT between users', async () => {
        expect(await poolA.balanceOf(user.address)).to.equal(remainingBalance);
        expect(await poolA.balanceOf(other.address)).to.equal(bptAmount);

        // Supply doesn't change
        expect(await poolA.totalSupply()).to.equal(totalSupply);
      });

      it('direct ERC20 BPT transfer emits a transfer event on the token', async () => {
        await expect(await poolA.connect(user).transfer(other.address, bptAmount))
          .to.emit(poolA, 'Transfer')
          .withArgs(user.address, other.address, bptAmount);
      });

      it('indirect ERC20 BPT transfer emits a transfer event on the token', async () => {
        await expect(await vault.connect(poolASigner).transfer(user.address, other.address, bptAmount))
          .to.emit(poolA, 'Transfer')
          .withArgs(user.address, other.address, bptAmount);
      });
    }

    it('transfers ERC20 BPT directly', async () => {
      await poolA.connect(user).transfer(other.address, bptAmount);

      itTransfersBPTCorrectly();
    });

    it('transfers ERC20 BPT through the vault', async () => {
      await vault.connect(poolASigner).transfer(user.address, other.address, bptAmount);

      itTransfersBPTCorrectly();
    });

    it('cannot transfer ERC20 BPT from zero address', async () => {
      await expect(vault.connect(poolASigner).transfer(ZERO_ADDRESS, other.address, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidSender')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot transfer ERC20 BPT to zero address', async () => {
      await expect(vault.connect(poolASigner).transfer(user.address, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidReceiver')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot transfer more than balance', async () => {
      await expect(vault.connect(poolASigner).transfer(user.address, other.address, totalSupply + 1n))
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientBalance')
        .withArgs(user.address, totalSupply, totalSupply + 1n);
    });

    it('cannot emit transfer event except through the Vault', async () => {
      await expect(poolA.connect(user).emitTransfer(user.address, other.address, totalSupply))
        .to.be.revertedWithCustomError(poolA, 'SenderIsNotVault')
        .withArgs(user.address);
    });

    it('cannot emit approval event except through the Vault', async () => {
      await expect(poolA.connect(user).emitApproval(user.address, other.address, totalSupply))
        .to.be.revertedWithCustomError(poolA, 'SenderIsNotVault')
        .withArgs(user.address);
    });
  });

  describe('allowance', () => {
    const bptAmount = fp(72);

    function itSetsApprovalsCorrectly() {
      it('sets approval', async () => {
        expect(await poolA.allowance(user.address, relayer.address)).to.equal(bptAmount);
        expect(await poolA.allowance(user.address, other.address)).to.equal(0);

        expect(await vault.allowance(poolAAddress, user.address, relayer.address)).to.equal(bptAmount);
        expect(await vault.allowance(poolAAddress, user.address, other.address)).to.equal(0);
      });

      it('direct ERC20 approval emits an event on the token', async () => {
        await expect(await poolA.connect(user).approve(relayer.address, bptAmount))
          .to.emit(poolA, 'Approval')
          .withArgs(user.address, relayer.address, bptAmount);
      });

      it('indirect ERC20 approval emits an event on the token', async () => {
        await expect(await vault.connect(poolASigner).approve(user, relayer, bptAmount))
          .to.emit(poolA, 'Approval')
          .withArgs(user.address, relayer.address, bptAmount);
      });
    }

    context('sets approval directly', async () => {
      sharedBeforeEach('set approval', async () => {
        await poolA.connect(user).approve(relayer.address, bptAmount);
      });

      itSetsApprovalsCorrectly();
    });

    context('sets approval through the vault', async () => {
      sharedBeforeEach('set approval', async () => {
        await vault.connect(poolASigner).approve(user, relayer, bptAmount);
      });

      itSetsApprovalsCorrectly();
    });

    it('cannot approve to zero address', async () => {
      await expect(vault.connect(poolASigner).approve(user, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidSpender')
        .withArgs(ZERO_ADDRESS);
    });
  });

  describe('transferFrom', () => {
    const totalSupply = fp(50);
    const bptAmount = fp(18);

    const remainingBalance = totalSupply - bptAmount;

    sharedBeforeEach('Mint initial ERC20 BPT supply of pool A, and approve transfer', async () => {
      await vault.mintERC20(poolAAddress, user.address, totalSupply);
      await poolA.connect(user).approve(relayer.address, bptAmount);
    });

    function itTransfersBPTCorrectly() {
      it('relayer can transfer ERC20 BPT', async () => {
        expect(await poolA.balanceOf(user.address)).to.equal(remainingBalance);
        expect(await poolA.balanceOf(relayer.address)).to.equal(bptAmount);

        // Supply doesn't change
        expect(await poolA.totalSupply()).to.equal(totalSupply);
      });
    }

    context('transfers ERC20 BPT directly', async () => {
      sharedBeforeEach('direct transferFrom', async () => {
        await poolA.connect(relayer).transferFrom(user.address, relayer.address, bptAmount);
      });

      itTransfersBPTCorrectly();
    });

    context('transfers ERC20 BPT through the vault', async () => {
      sharedBeforeEach('indirect transferFrom', async () => {
        await vault.connect(poolASigner).transfer(user.address, relayer.address, bptAmount);
      });

      itTransfersBPTCorrectly();
    });

    it('direct transfer emits a transfer event on the token', async () => {
      await expect(await poolA.connect(relayer).transferFrom(user.address, relayer.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('indirect transfer emits a transfer event on the ERC20 BPT token', async () => {
      await expect(
        await vault.connect(poolASigner).transferFrom(relayer.address, user.address, relayer.address, bptAmount)
      )
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('cannot transfer ERC20 BPT to zero address', async () => {
      await expect(vault.connect(poolASigner).transferFrom(relayer.address, user.address, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidReceiver')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot transfer more than ERC20 BPT balance', async () => {
      // Give infinite allowance
      await poolA.connect(user).approve(relayer.address, MAX_UINT256);

      await expect(
        vault.connect(poolASigner).transferFrom(relayer.address, user.address, other.address, totalSupply + 1n)
      )
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientBalance')
        .withArgs(user.address, totalSupply, totalSupply + 1n);
    });

    it('cannot transfer more than ERC20 BPT allowance', async () => {
      const allowance = await vault.connect(user).allowance(poolA, user, relayer);

      await expect(vault.connect(poolASigner).transferFrom(relayer, user, other, allowance + 1n))
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientAllowance')
        .withArgs(relayer.address, bptAmount, allowance + 1n);
    });
  });
});
