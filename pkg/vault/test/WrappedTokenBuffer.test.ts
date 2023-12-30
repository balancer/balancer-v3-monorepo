import { ethers } from 'hardhat';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { VaultMock } from '../typechain-types/contracts/test/VaultMock';
import { ERC20TestToken } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/ERC20TestToken';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types/contracts/test/BasicAuthorizerMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { WrappedTokenMock } from '../typechain-types/contracts/test/WrappedTokenMock';
import { FP_ONE, bn } from '@balancer-labs/v3-helpers/src/numbers';

describe('Vault - Wrapped Token Buffers', function () {
  const PAUSE_WINDOW_DURATION = MONTH * 3;
  const BUFFER_PERIOD_DURATION = MONTH;

  let vault: VaultMock;
  let authorizer: BasicAuthorizerMock;
  let underlyingToken: ERC20TestToken;
  let wrappedToken: WrappedTokenMock;

  let alice: SignerWithAddress;

  before('setup signers', async () => {
    [, alice] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault', async function () {
    authorizer = await deploy('v3-solidity-utils/BasicAuthorizerMock');
    vault = await deploy('VaultMock', {
      args: [authorizer.getAddress(), PAUSE_WINDOW_DURATION, BUFFER_PERIOD_DURATION],
    });

    underlyingToken = await deploy('v3-solidity-utils/ERC20TestToken', { args: ['Standard', 'BASE', 6] });
    wrappedToken = await deploy('WrappedTokenMock', { args: [underlyingToken, 'ERC4626', 'WRAPPED', 8] });
  });

  describe('buffer registration', () => {
    context('without permission', () => {
      it('cannot register a buffer without permission', async () => {
        await expect(vault.registerBuffer(wrappedToken)).to.be.revertedWithCustomError(vault, 'SenderNotAllowed');
      });

      it('cannot get rate for unregistered buffer', async () => {
        await expect(vault.getWrappedTokenBufferRate(wrappedToken)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferNotRegistered'
        );
      });
    });

    context('with permission', () => {
      sharedBeforeEach('grant permission', async () => {
        const registerBufferAction = await actionId(vault, 'registerBuffer');

        await authorizer.grantRole(registerBufferAction, alice.address);
      });

      it('can get the rate from a buffer', async () => {
        await vault.connect(alice).registerBuffer(wrappedToken);

        // With everything 0, it just returns 1 * 10^(decimal difference)
        const expectedRate = FP_ONE * bn(10 ** (8 - 6));

        const rate = await vault.getWrappedTokenBufferRate(wrappedToken);
        expect(rate).to.equal(expectedRate);
      });

      it('buffer registration emits an event', async () => {
        expect(await vault.connect(alice).registerBuffer(wrappedToken))
          .to.emit(vault, 'WrappedTokenBufferRegistered')
          .withArgs(underlyingToken, wrappedToken);
      });

      it('cannot register a buffer twice', async () => {
        vault.connect(alice).registerBuffer(wrappedToken);

        await expect(vault.connect(alice).registerBuffer(wrappedToken)).to.be.revertedWithCustomError(
          vault,
          'WrappedTokenBufferAlreadyRegistered'
        );
      });
    });
  });
});
