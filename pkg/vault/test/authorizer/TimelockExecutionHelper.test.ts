import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';

import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { TimelockExecutionHelper } from '../../typechain-types';

describe('TimelockExecutionHelper', () => {
  let executionHelper: TimelockExecutionHelper, token: Contract;
  let authorizer: SignerWithAddress, other: SignerWithAddress;

  before('setup signers', async () => {
    [, authorizer, other] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy contracts', async () => {
    token = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Token', 'TKN', 18] });
    executionHelper = await deploy('TimelockExecutionHelper', { from: authorizer });
  });

  describe('execute', () => {
    context('when the sender is the authorizer', () => {
      it('forwards the given call', async () => {
        const previousAmount = await token.balanceOf(other.address);

        const mintAmount = fp(1);
        await executionHelper
          .connect(authorizer)
          .execute(token, token.interface.encodeFunctionData('mint', [other.address, mintAmount]));

        expect(await token.balanceOf(other.address)).to.be.equal(previousAmount + mintAmount);
      });

      it('reverts if the call is reentrant', async () => {
        await expect(
          executionHelper
            .connect(authorizer)
            .execute(executionHelper, executionHelper.interface.encodeFunctionData('execute', [ZERO_ADDRESS, '0x']))
        ).to.be.revertedWithCustomError(executionHelper, 'ReentrancyGuardReentrantCall');
      });
    });

    context('when the sender is not the authorizer', () => {
      it('reverts', async () => {
        await expect(executionHelper.connect(other).execute(token, '0x')).to.be.revertedWith(
          'SENDER_IS_NOT_AUTHORIZER'
        );
      });
    });
  });
});
