import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { BigNumberish } from '@balancer-labs/v3-helpers/src/numbers';
import { advanceTime, currentTimestamp, fromNow, MONTH } from '@balancer-labs/v3-helpers/src/time';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe('TemporarilyPausable', function () {
  let instance: Contract;
  let user: SignerWithAddress, other: SignerWithAddress;

  const deployTemporarilyPausable = async ({ pauseWindowDuration = 0, bufferPeriodDuration = 0 }) => {
    instance = await deploy('TemporarilyPausableMock', { args: [pauseWindowDuration, bufferPeriodDuration] });
  };
  before('setup signers', async () => {
    [, user, other] = await ethers.getSigners();
  });

  describe('initialization', () => {
    it('can be initialized with pause window and buffer period duration', async () => {
      const pauseWindowDuration = MONTH;
      const bufferPeriodDuration = MONTH;

      await deployTemporarilyPausable({ pauseWindowDuration, bufferPeriodDuration });

      expect(await instance.paused()).to.equal(false);
      expect(await instance.getPauseWindowEndTime()).to.equal(await fromNow(pauseWindowDuration));
      expect(await instance.getBufferPeriodEndTime()).to.equal(
        (await fromNow(pauseWindowDuration)).add(bufferPeriodDuration)
      );
    });

    it('can be initialized with no pause window or buffer period duration', async () => {
      const pauseWindowDuration = 0;
      const bufferPeriodDuration = 0;

      await deployTemporarilyPausable({ pauseWindowDuration, bufferPeriodDuration });

      expect(await instance.paused()).to.equal(false);
      expect(await instance.getPauseWindowEndTime()).to.equal(await fromNow(0));
      expect(await instance.getBufferPeriodEndTime()).to.equal(await fromNow(0));
    });

    it('cannot be initialized with a pause window greater than the max', async () => {
      const maxPauseWindowDuration = await instance.getMaxPauseWindowDuration();
      const pauseWindowDuration = maxPauseWindowDuration + 1;

      await expect(deployTemporarilyPausable({ pauseWindowDuration })).to.be.revertedWithCustomError(
        instance,
        'MaxPauseWindowDuration'
      );
    });

    it('cannot be initialized with a buffer period greater than the max', async () => {
      const maxBufferPeriodDuration = await instance.getMaxBufferPeriodDuration();
      const pauseWindowDuration = MONTH;
      const bufferPeriodDuration = maxBufferPeriodDuration + 1;

      await expect(
        deployTemporarilyPausable({ pauseWindowDuration, bufferPeriodDuration })
      ).to.be.revertedWithCustomError(instance, 'MaxBufferPeriodDuration');
    });
  });

  describe('pause/unpause', () => {
    const PAUSE_WINDOW_DURATION = MONTH * 3;
    const BUFFER_PERIOD_DURATION = MONTH;

    sharedBeforeEach('deploy', async () => {
      await deployTemporarilyPausable({
        pauseWindowDuration: PAUSE_WINDOW_DURATION,
        bufferPeriodDuration: BUFFER_PERIOD_DURATION,
      });
    });

    context('before the pause window end date has been reached', () => {
      sharedBeforeEach('advance some time', async () => {
        await advanceTime(PAUSE_WINDOW_DURATION / 2);
      });

      it('can be paused', async () => {
        await instance.pause();

        expect(await instance.paused()).to.equal(true);
      });

      it('can be paused and unpaused', async () => {
        await instance.pause();
        expect(await instance.paused()).to.equal(true);

        await advanceTime(PAUSE_WINDOW_DURATION / 4);

        await instance.unpause();
        expect(await instance.paused()).to.equal(false);
      });

      it('emits a Paused event', async () => {
        await expect(await instance.connect(user).pause())
          .to.emit(instance, 'Paused')
          .withArgs(user.address);
      });
    });

    context('after the pause window end date has been reached', () => {
      context('when unpaused', () => {
        sharedBeforeEach('advance time', async () => {
          await advanceTime(PAUSE_WINDOW_DURATION);
        });

        function itIsForeverUnpaused() {
          it('is unpaused', async () => {
            expect(await instance.paused()).to.equal(false);
          });

          it('cannot be paused', async () => {
            await expect(instance.pause()).to.be.revertedWithCustomError(instance, 'PauseWindowExpired');
          });
        }

        context('before the buffer period end date', () => {
          sharedBeforeEach('advance some time', async () => {
            await advanceTime(BUFFER_PERIOD_DURATION / 2);
          });

          itIsForeverUnpaused();
        });

        context('after the buffer period end date', () => {
          sharedBeforeEach('reach the buffer period end date', async () => {
            await advanceTime(BUFFER_PERIOD_DURATION);
          });

          itIsForeverUnpaused();
        });
      });

      context('when paused', () => {
        sharedBeforeEach('pause and advance time', async () => {
          await instance.pause();
          await advanceTime(PAUSE_WINDOW_DURATION);
        });

        context('before the buffer period end date', () => {
          sharedBeforeEach('advance some time', async () => {
            await advanceTime(BUFFER_PERIOD_DURATION / 2);
          });

          it('is paused', async () => {
            expect(await instance.paused()).to.equal(true);
          });

          it('can be unpaused', async () => {
            await instance.unpause();
            expect(await instance.paused()).to.equal(false);
          });

          it('cannot be unpaused and paused', async () => {
            await instance.unpause();
            expect(await instance.paused()).to.equal(false);

            await expect(instance.pause()).to.be.revertedWithCustomError(instance, 'PauseWindowExpired');
          });
        });

        context('after the buffer period end date', () => {
          sharedBeforeEach('reach the buffer period end date', async () => {
            await advanceTime(BUFFER_PERIOD_DURATION);
          });

          it('is unpaused', async () => {
            expect(await instance.paused()).to.equal(false);
          });

          it('cannot be paused', async () => {
            await expect(instance.pause()).to.be.revertedWithCustomError(instance, 'PauseWindowExpired');
          });

          it('cannot be unpaused', async () => {
            await expect(instance.unpause()).to.be.revertedWithCustomError(instance, 'AlreadyUnPaused');
          });
        });
      });
    });
  });
});
