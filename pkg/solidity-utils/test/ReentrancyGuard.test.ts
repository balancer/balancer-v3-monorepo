import { expect } from 'chai';
import { Contract } from 'ethers';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe('ReentrancyGuard', () => {
  let reentrancyMock: Contract;

  sharedBeforeEach(async function () {
    reentrancyMock = await deploy('ReentrancyMock');
    expect(await reentrancyMock.counter()).to.equal(0);
  });

  it('nonReentrant function can be called', async function () {
    expect(await reentrancyMock.counter()).to.equal(0);
    await reentrancyMock.callback();

    expect(await reentrancyMock.counter()).to.equal(1);
  });

  it('does not allow remote callback', async function () {
    const attacker: Contract = await deploy('ReentrancyAttack');

    await expect(reentrancyMock.countAndCall(await attacker.getAddress())).to.be.revertedWith(
      'ReentrancyAttack: failed call'
    );
  });

  it('_reentrancyGuardEntered should be true when guarded', async function () {
    await expect(reentrancyMock.guardedCheckEntered()).not.to.be.reverted;
  });

  it('_reentrancyGuardEntered should be false when unguarded', async function () {
    await expect(reentrancyMock.unguardedCheckNotEntered()).not.to.be.reverted;
  });

  // The following are more side-effects than intended behavior:
  // I put them here as documentation, and to monitor any changes
  // in the side-effects.
  it('does not allow local recursion', async function () {
    await expect(reentrancyMock.countLocalRecursive(10)).to.be.revertedWithCustomError(
      reentrancyMock,
      'ReentrancyGuardReentrantCall'
    );
  });

  it('does not allow indirect local recursion', async function () {
    await expect(reentrancyMock.countThisRecursive(10)).to.be.revertedWith('ReentrancyMock: failed call');
  });
});
