import { expect } from 'chai';
import { Contract } from 'ethers';
import { ethers } from 'hardhat';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe('CodeDeployer', function () {
  let factory: Contract;

  sharedBeforeEach(async () => {
    factory = await deploy('CodeDeployerFactory', { args: [] });
  });

  context('with no code', () => {
    itStoresArgumentAsCode('0x');
  });

  context('with some code', () => {
    itStoresArgumentAsCode('0x1234');
  });

  context('with code 24kB long', () => {
    itStoresArgumentAsCode(`0x${'00'.repeat(24 * 1024)}`);
  });

  context('with code over 24kB long', () => {
    // Have marked it unlimited, since the Vault is now too large; therefore this won't fail on hardhat
    it.skip('reverts', async () => {
      const data = `0x${'00'.repeat(24 * 1024 + 1)}`;
      await expect(factory.deploy(data)).to.be.revertedWith('CODE_DEPLOYMENT_FAILED');
    });
  });

  function itStoresArgumentAsCode(data: string) {
    it('stores its constructor argument as its code', async () => {
      const receipt = await (await factory.deploy(data)).wait();
      const event = expectEvent.inReceipt(receipt, 'CodeDeployed');

      expect(await ethers.provider.getCode(event.args.destination)).to.equal(data);
    });
  }
});
