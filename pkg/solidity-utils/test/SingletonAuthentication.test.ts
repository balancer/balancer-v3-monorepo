import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { BasicAuthorizerMock } from '../typechain-types/contracts/test/BasicAuthorizerMock';
import { BasicVaultMock } from '../typechain-types/contracts/test/BasicVaultMock';
import { SingletonAuthenticationMock } from '../typechain-types/contracts/test/SingletonAuthenticationMock';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';

describe('SingletonAuthentication', () => {
  let singleton: SingletonAuthenticationMock;
  let authorizer: BasicAuthorizerMock;
  let vault: BasicVaultMock;
  let admin: SignerWithAddress, other: SignerWithAddress;

  before('setup signers', async () => {
    [, admin, other] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy Authorizer, Vault, and Singleton', async () => {
    authorizer = (await deploy('BasicAuthorizerMock')) as unknown as BasicAuthorizerMock;
    vault = (await deploy('BasicVaultMock', { args: [authorizer.address] })) as unknown as BasicVaultMock;

    singleton = (await deploy('SingletonAuthenticationMock', {
      args: [vault.address],
    })) as unknown as SingletonAuthenticationMock;
  });

  it('works', () => {
    expect(true).to.be.true;
  });

  describe('constructor', () => {
    it('sets the vault address', async () => {
      expect(await singleton.getVault()).to.be.eq(vault.address);
    });

    it('uses the authorizer of the vault', async () => {
      expect(await singleton.getAuthorizer()).to.equal(authorizer.address);
    });

    it('tracks authorizer changes in the vault', async () => {
      await vault.connect(admin).setAuthorizer(other.address);

      expect(await singleton.getAuthorizer()).to.equal(other.address);
    });

    it('emits an event when the authorizer changes', async () => {
      const receipt = await vault.connect(admin).setAuthorizer(other.address);

      expectEvent.inReceipt(await receipt.wait(), 'AuthorizerChanged', {
        newAuthorizer: other.address,
      });
    });
  });

  describe('disambiguation', () => {
    const selector = '0x12345678';
    const MAINNET = 1;
    const POLYGON = 137;

    let secondOne: Contract;

    sharedBeforeEach('deploy second singleton', async () => {
      secondOne = await deploy('SingletonAuthenticationMock', { args: [vault.address] });
    });

    it('disambiguates selectors', async () => {
      const firstActionId = await singleton.getActionId(MAINNET, selector);
      const secondActionId = await secondOne.getActionId(MAINNET, selector);

      expect(firstActionId).to.not.equal(secondActionId);
    });

    it('disambiguates chains', async () => {
      const firstActionId = await secondOne.getActionId(MAINNET, selector);
      const secondActionId = await secondOne.getActionId(POLYGON, selector);

      expect(firstActionId).to.not.equal(secondActionId);
    });
  });
});
