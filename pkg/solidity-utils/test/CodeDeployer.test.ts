import { expect } from 'chai';
import { Contract, Signer } from 'ethers';
import { ethers } from 'hardhat';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { CodeDeployer__factory } from '../typechain-types';

describe('CodeDeployer', function () {
  let factory: Contract;
  let admin: Signer;

  before('setup signers', async () => {
    [, admin] = await ethers.getSigners();
  });

  sharedBeforeEach(async () => {
    factory = await deploy('CodeDeployerMock', { args: [] });
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
    before(function () {
      // Skip this test during coverage - instrumentation interferes with size limits.
      if (process.env.COVERAGE) {
        this.skip();
      }
    });

    it('reverts', async () => {
      const data = `0x${'00'.repeat(24 * 1024 + 1)}`;
      await expect(factory.deploy(data, false)).to.be.revertedWithCustomError(
        {
          interface: CodeDeployer__factory.createInterface(),
        },
        'CodeDeploymentFailed'
      );
    });
  });

  function itStoresArgumentAsCode(data: string) {
    it('stores its constructor argument as its code', async () => {
      const receipt = await (await factory.deploy(data, false)).wait();
      const event = expectEvent.inReceipt(receipt, 'CodeDeployed');

      expect(await ethers.provider.getCode(event.args.destination)).to.equal(data);
    });
  }

  describe('CodeDeployer protection', () => {
    let deployedContract: string;

    context('protected selfdestruct', () => {
      // INVALID
      // PUSH0
      // SELFDESTRUCT
      // STOP (optional - works without this)
      const code = '0x5fff00';
      const safeCode = '0xfe5fff00';

      sharedBeforeEach('deploy contract', async () => {
        // Pass it the unmodified code
        const receipt = await (await factory.deploy(code, true)).wait();
        const event = expectEvent.inReceipt(receipt, 'CodeDeployed');

        deployedContract = event.args.destination;
      });

      // It should actually store the safecode
      itStoresArgumentAsCode(safeCode);

      it('does not self destruct', async () => {
        const tx = {
          to: deployedContract,
          value: ethers.parseEther('0.001'),
        };

        await expect(admin.sendTransaction(tx)).to.be.reverted;

        // Should still have the safeCode
        expect(await ethers.provider.getCode(deployedContract)).to.equal(safeCode);
      });
    });
  });
});
