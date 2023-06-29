import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { ERC20BalancerPoolToken } from '../typechain-types/contracts/ERC20BalancerPoolToken';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import '@balancer-labs/v3-common/setupTests';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';

describe('ERC20BalancerPoolToken', function () {
  const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';

  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  let vault: VaultMock;
  let poolA: ERC20BalancerPoolToken;
  let poolB: ERC20BalancerPoolToken;
  let tokenA: ERC20TestToken;
  let tokenB: ERC20TestToken;
  let tokenC: ERC20TestToken;

  let vaultAddress: string;

  let user: SignerWithAddress;
  let other: SignerWithAddress;
  let relayer: SignerWithAddress;
  let factory: SignerWithAddress;

  let tokenAAddress: string;
  let tokenBAddress: string;
  let tokenCAddress: string;

  let poolAAddress: string;
  let poolBAddress: string;

  let poolATokens: string[];

  before('setup signers', async () => {
    [, user, other, factory, relayer] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault, tokens, and pools', async function () {
    vault = await deploy('VaultMock', { args: [WETH, PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION] });
    vaultAddress = await vault.getAddress();

    tokenA = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token A', 'TKNA', 18] });
    tokenB = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token B', 'TKNB', 6] });
    tokenC = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token C', 'TKNC', 8] });

    poolA = await deploy('ERC20BalancerPoolToken', { args: [vaultAddress, 'Pool A', 'POOLA'] });
    poolB = await deploy('ERC20BalancerPoolToken', { args: [vaultAddress, 'Pool B', 'POOLB'] });

    expect(await poolA.name()).to.equal('Pool A');
    expect(await poolA.symbol()).to.equal('POOLA');
    expect(await poolA.decimals()).to.equal(18);
  });

  sharedBeforeEach('get addresses', async () => {
    tokenAAddress = await tokenA.getAddress();
    tokenBAddress = await tokenB.getAddress();
    tokenCAddress = await tokenC.getAddress();

    poolAAddress = await poolA.getAddress();
    poolBAddress = await poolB.getAddress();

    poolATokens = [tokenAAddress, tokenBAddress, tokenCAddress];
  });

  describe('minting', async () => {
    const bptAmount = fp(100);

    sharedBeforeEach('register the pool', async () => {
      await poolA.initialize(factory, poolATokens);
    });

    it('vault can mint BPT', async () => {
      await vault.mint(poolAAddress, user.address, bptAmount);

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

    it('minting emits a transfer event on the token', async () => {
      await expect(await vault.mint(poolAAddress, user.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(ZERO_ADDRESS, user.address, bptAmount);
    });

    it('cannot mint to zero address', async () => {
      await expect(vault.mint(poolBAddress, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidReceiver')
        .withArgs(ZERO_ADDRESS);
    });
  });

  describe('burning', async () => {
    const totalSupply = fp(100);
    const bptAmount = fp(32.5);

    sharedBeforeEach('register the pool, and mint initial supply', async () => {
      await poolA.initialize(factory, poolATokens);
      await vault.mint(poolAAddress, user.address, totalSupply);
    });

    it('vault can burn BPT', async () => {
      await vault.burn(poolAAddress, user.address, bptAmount);

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

    it('burning emits a transfer event on the token', async () => {
      await expect(await vault.burn(poolAAddress, user.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, ZERO_ADDRESS, bptAmount);
    });

    it('cannot burn from the zero address', async () => {
      await expect(vault.burn(poolBAddress, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidSender')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot burn more than the balance', async () => {
      // User has zero balance of PoolB
      await expect(vault.burn(poolBAddress, user.address, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientBalance')
        .withArgs(user.address, 0, bptAmount);
    });
  });

  describe('transfer', () => {
    const totalSupply = fp(50);
    const bptAmount = fp(18);

    const remainingBalance = totalSupply - bptAmount;

    sharedBeforeEach('register the pool, and mint initial supply', async () => {
      await poolA.initialize(factory, poolATokens);
      await vault.mint(poolAAddress, user.address, totalSupply);
    });

    function itTransfersBPTCorrectly() {
      it('transfers BPT between users', async () => {
        expect(await poolA.balanceOf(user.address)).to.equal(remainingBalance);
        expect(await poolA.balanceOf(other.address)).to.equal(bptAmount);

        // Supply doesn't change
        expect(await poolA.totalSupply()).to.equal(totalSupply);
      });
    }

    it('transfers BPT directly', async () => {
      await poolA.connect(user).transfer(other.address, bptAmount);

      itTransfersBPTCorrectly();
    });

    it('transfers BPT through the vault', async () => {
      await vault.connect(user).transfer(poolAAddress, user.address, other.address, bptAmount);

      itTransfersBPTCorrectly();
    });

    it('direct transfer emits a transfer event on the token', async () => {
      await expect(await poolA.connect(user).transfer(other.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, other.address, bptAmount);
    });

    it('indirect transfer emits a transfer event on the token', async () => {
      await expect(await vault.connect(user).transfer(poolAAddress, user.address, other.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, other.address, bptAmount);
    });

    it('vault cannot transfer a non-BPT token', async () => {
      await tokenA.mint(user.address, bptAmount);
      expect(await tokenA.balanceOf(user.address)).to.equal(bptAmount);

      await expect(vault.connect(user).transfer(tokenAAddress, user.address, other.address, bptAmount))
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(tokenAAddress);
    });

    it('cannot transfer from zero address', async () => {
      await expect(vault.connect(user).transfer(poolAAddress, ZERO_ADDRESS, other.address, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidSender')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot transfer to zero address', async () => {
      await expect(vault.connect(user).transfer(poolAAddress, user.address, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidReceiver')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot transfer more than balance', async () => {
      await expect(vault.connect(user).transfer(poolAAddress, user.address, other.address, totalSupply + 1n))
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientBalance')
        .withArgs(user.address, totalSupply, totalSupply + 1n);
    });

    it('cannot emit transfer event except through the Vault', async () => {
      await expect(poolA.connect(user).emitTransfer(user.address, other.address, totalSupply))
        .to.be.revertedWithCustomError(poolA, 'SenderIsNotVault')
        .withArgs(user.address);
    });

    it('cannot emit approval event except through the Vault', async () => {
      await expect(poolA.connect(user).emitApprove(user.address, other.address, totalSupply))
        .to.be.revertedWithCustomError(poolA, 'SenderIsNotVault')
        .withArgs(user.address);
    });
  });

  describe('allowance', () => {
    const bptAmount = fp(72);

    sharedBeforeEach('register the pool', async () => {
      await poolA.initialize(factory, poolATokens);
    });

    function itSetsApprovalsCorrectly() {
      it('sets approval', async () => {
        expect(await poolA.allowance(user.address, relayer.address)).to.equal(bptAmount);
        expect(await poolA.allowance(user.address, other.address)).to.equal(0);

        expect(await vault.allowance(poolAAddress, user.address, relayer.address)).to.equal(bptAmount);
        expect(await vault.allowance(poolAAddress, user.address, other.address)).to.equal(0);
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
        await vault.connect(user).approve(poolAAddress, user.address, relayer.address, bptAmount);
      });

      itSetsApprovalsCorrectly();
    });

    it('direct approval emits an event on the token', async () => {
      await expect(await poolA.connect(user).approve(relayer.address, bptAmount))
        .to.emit(poolA, 'Approval')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('indirect approval emits an event on the token', async () => {
      await expect(await vault.connect(user).approve(poolAAddress, user.address, relayer.address, bptAmount))
        .to.emit(poolA, 'Approval')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('cannot approve from zero address', async () => {
      await expect(vault.connect(user).approve(poolAAddress, ZERO_ADDRESS, other.address, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidApprover')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot approve to zero address', async () => {
      await expect(vault.connect(user).approve(poolAAddress, user.address, ZERO_ADDRESS, bptAmount))
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidSpender')
        .withArgs(ZERO_ADDRESS);
    });
  });

  describe('transferFrom', () => {
    const totalSupply = fp(50);
    const bptAmount = fp(18);

    const remainingBalance = totalSupply - bptAmount;

    sharedBeforeEach('register the pool, mint initial supply, and approve transfer', async () => {
      await poolA.initialize(factory, poolATokens);
      await vault.mint(poolAAddress, user.address, totalSupply);
      await poolA.connect(user).approve(relayer.address, bptAmount);
    });

    function itTransfersBPTCorrectly() {
      it('relayer can transfer BPT', async () => {
        expect(await poolA.balanceOf(user.address)).to.equal(remainingBalance);
        expect(await poolA.balanceOf(relayer.address)).to.equal(bptAmount);

        // Supply doesn't change
        expect(await poolA.totalSupply()).to.equal(totalSupply);
      });
    }

    context('transfers BPT directly', async () => {
      sharedBeforeEach('direct transferFrom', async () => {
        await poolA.connect(relayer).transferFrom(user.address, relayer.address, bptAmount);
      });

      itTransfersBPTCorrectly();
    });

    context('transfers BPT through the vault', async () => {
      sharedBeforeEach('indirect transferFrom', async () => {
        await vault.connect(relayer).transfer(poolAAddress, user.address, relayer.address, bptAmount);
      });

      itTransfersBPTCorrectly();
    });

    it('direct transfer emits a transfer event on the token', async () => {
      await expect(await poolA.connect(relayer).transferFrom(user.address, relayer.address, bptAmount))
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('indirect transfer emits a transfer event on the token', async () => {
      await expect(
        await vault
          .connect(relayer)
          .transferFrom(poolAAddress, relayer.address, user.address, relayer.address, bptAmount)
      )
        .to.emit(poolA, 'Transfer')
        .withArgs(user.address, relayer.address, bptAmount);
    });

    it('vault cannot transfer a non-BPT token', async () => {
      await tokenA.mint(user.address, bptAmount);
      expect(await tokenA.balanceOf(user.address)).to.equal(bptAmount);

      await expect(
        vault.connect(relayer).transferFrom(tokenAAddress, relayer.address, user.address, relayer.address, bptAmount)
      )
        .to.be.revertedWithCustomError(vault, 'PoolNotRegistered')
        .withArgs(tokenAAddress);
    });

    it('cannot transfer to zero address', async () => {
      await expect(
        vault.connect(relayer).transferFrom(poolAAddress, relayer.address, user.address, ZERO_ADDRESS, bptAmount)
      )
        .to.be.revertedWithCustomError(vault, 'ERC20InvalidReceiver')
        .withArgs(ZERO_ADDRESS);
    });

    it('cannot transfer more than balance', async () => {
      // Give infinite allowance
      await poolA.connect(user).approve(relayer.address, MAX_UINT256);

      await expect(
        vault.connect(user).transferFrom(poolAAddress, relayer.address, user.address, other.address, totalSupply + 1n)
      )
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientBalance')
        .withArgs(user.address, totalSupply, totalSupply + 1n);
    });

    it('cannot transfer more than allowance', async () => {
      await expect(
        vault.connect(user).transferFrom(poolAAddress, relayer.address, user.address, other.address, bptAmount + 1n)
      )
        .to.be.revertedWithCustomError(vault, 'ERC20InsufficientAllowance')
        .withArgs(relayer.address, bptAmount, bptAmount + 1n);
    });
  });
});
