import { ethers } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { bn, fp } from '@balancer-labs/v3-helpers/src/numbers';
import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import ERC20TokenList from '@balancer-labs/v3-helpers/src/models/tokens/ERC20TokenList';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { StablePool } from '../typechain-types';
import { DAY, advanceTime, currentTimestamp, setNextBlockTimestamp } from '@balancer-labs/v3-helpers/src/time';
import { MAX_UINT256 } from '@balancer-labs/v3-helpers/src/constants';
import * as expectEvent from '@balancer-labs/v3-helpers/src/test/expectEvent';
import { expectEqualWithError } from '@balancer-labs/v3-helpers/src/test/relativeError';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';

describe('StablePoolAmplification', () => {
  const TOKEN_AMOUNT = fp(1000);
  const MIN_AMP = 1n;
  const MAX_AMP = 5000n;
  const AMP_PRECISION = 1000n;
  const INITIAL_AMPLIFICATION_PARAMETER = 200n;

  let vault: IVaultMock;
  let admin: SignerWithAddress;
  let alice: SignerWithAddress;
  let other: SignerWithAddress;

  let tokens: ERC20TokenList;
  let pool: StablePool;

  sharedBeforeEach('setup signers', async () => {
    [, admin, alice, other] = await ethers.getSigners();
  });

  sharedBeforeEach('deploy vault', async () => {
    vault = await TypesConverter.toIVaultMock(await VaultDeployer.deployMock());

    tokens = await ERC20TokenList.create(4, { sorted: true });

    // mint and approve tokens
    await tokens.asyncEach(async (token) => {
      await token.mint(alice, TOKEN_AMOUNT);
      await token.connect(alice).approve(vault, MAX_UINT256);
    });
  });

  async function grantPermission() {
    const startAmpUpdateAction = await actionId(pool, 'startAmplificationParameterUpdate');
    const stopAmpUpdateAction = await actionId(pool, 'stopAmplificationParameterUpdate');

    const authorizerAddress = await vault.getAuthorizer();
    const authorizer = await deployedAt('v3-vault/BasicAuthorizerMock', authorizerAddress);

    await authorizer.grantRole(startAmpUpdateAction, admin.address);
    await authorizer.grantRole(stopAmpUpdateAction, admin.address);
  }

  async function deployPool(amp: bigint) {
    pool = await deploy('StablePool', {
      args: [
        { name: 'Stable Pool', symbol: 'STABLE', amplificationParameter: amp, version: 'Stable Pool v1' },
        await vault.getAddress(),
      ],
    });

    await grantPermission();
  }

  describe('constructor', () => {
    context('when passing a valid initial amplification parameter value', () => {
      sharedBeforeEach('deploy pool', async () => {
        await deployPool(INITIAL_AMPLIFICATION_PARAMETER);
      });

      it('sets the expected amplification parameter', async () => {
        const { value, isUpdating, precision } = await pool.getAmplificationParameter();

        expect(value).to.be.equal(INITIAL_AMPLIFICATION_PARAMETER * AMP_PRECISION);
        expect(isUpdating).to.be.false;
        expect(precision).to.be.equal(AMP_PRECISION);
      });
    });

    context('when passing an initial amplification parameter less than MIN_AMP', () => {
      it('reverts', async () => {
        await expect(deployPool(MIN_AMP - 1n)).to.be.revertedWithCustomError(pool, 'AmplificationFactorTooLow');
      });
    });

    context('when passing an initial amplification parameter greater than MAX_AMP', () => {
      it('reverts', async () => {
        await expect(deployPool(MAX_AMP + 1n)).to.be.revertedWithCustomError(pool, 'AmplificationFactorTooHigh');
      });
    });
  });

  describe('startAmplificationParameterUpdate', () => {
    let caller: SignerWithAddress;

    function itStartsAnAmpUpdateCorrectly() {
      context('when requesting a reasonable change duration', () => {
        const duration = BigInt(DAY * 2);
        let endTime: bigint;

        sharedBeforeEach('set end time', async () => {
          const startTime = (await currentTimestamp()) + 100n;
          await setNextBlockTimestamp(startTime);
          endTime = startTime + duration;
        });

        context('when requesting a valid amp', () => {
          const itUpdatesAmpCorrectly = (newAmp: bigint) => {
            const increasing = INITIAL_AMPLIFICATION_PARAMETER < newAmp;

            context('when there is no ongoing update', () => {
              it('starts changing the amp', async () => {
                await pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime);

                await advanceTime(duration / 3n);

                const { value, isUpdating } = await pool.getAmplificationParameter();
                expect(isUpdating).to.be.true;

                if (increasing) {
                  const diff = (newAmp - INITIAL_AMPLIFICATION_PARAMETER) * AMP_PRECISION;
                  expectEqualWithError(value, INITIAL_AMPLIFICATION_PARAMETER * AMP_PRECISION + diff / 3n, 0.00001);
                } else {
                  const diff = (INITIAL_AMPLIFICATION_PARAMETER - newAmp) * AMP_PRECISION;
                  expectEqualWithError(value, INITIAL_AMPLIFICATION_PARAMETER * AMP_PRECISION - diff / 3n, 0.00001);
                }
              });

              it('stops updating after duration', async () => {
                await pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime);

                await advanceTime(duration + 1n);

                const { value, isUpdating } = await pool.getAmplificationParameter();
                expect(value).to.be.equal(newAmp * AMP_PRECISION);
                expect(isUpdating).to.be.false;
              });

              it('emits an AmpUpdateStarted event', async () => {
                const receipt = await pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime);

                expectEvent.inReceipt(await receipt.wait(), 'AmpUpdateStarted', {
                  startValue: INITIAL_AMPLIFICATION_PARAMETER * AMP_PRECISION,
                  endValue: newAmp * AMP_PRECISION,
                  endTime,
                });
              });

              it('does not emit an AmpUpdateStopped event', async () => {
                const receipt = await pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime);
                expectEvent.notEmitted(await receipt.wait(), 'AmpUpdateStopped');
              });
            });

            context('when there is an ongoing update', () => {
              sharedBeforeEach('start change', async () => {
                await pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime);

                await advanceTime(duration / 3n);
                const beforeStop = await pool.getAmplificationParameter();
                expect(beforeStop.isUpdating).to.be.true;
              });

              it('trying to start another update reverts', async () => {
                await expect(
                  pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime)
                ).to.be.revertedWithCustomError(pool, 'AmpUpdateAlreadyStarted');
              });

              context('after the ongoing update is stopped', () => {
                let ampValueAfterStop: bigint;

                sharedBeforeEach('stop change', async () => {
                  await pool.connect(caller).stopAmplificationParameterUpdate();
                  const ampState = await pool.getAmplificationParameter();
                  ampValueAfterStop = ampState.value;
                });

                it('the new update can be started', async () => {
                  const newEndTime = (await currentTimestamp()) + BigInt(DAY * 2);
                  const startReceipt = await pool.connect(caller).startAmplificationParameterUpdate(newAmp, newEndTime);
                  const now = await currentTimestamp();
                  expectEvent.inReceipt(await startReceipt.wait(), 'AmpUpdateStarted', {
                    endValue: newAmp * AMP_PRECISION,
                    startTime: now,
                    endTime: newEndTime,
                  });

                  await advanceTime(duration / 3n);

                  const afterStart = await pool.getAmplificationParameter();
                  expect(afterStart.isUpdating).to.be.true;
                  expect(afterStart.value).to.be[increasing ? 'gt' : 'lt'](ampValueAfterStop);
                });
              });
            });
          };

          context('when increasing the amp', () => {
            context('when increasing the amp by 2x', () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER * 2n;

              itUpdatesAmpCorrectly(newAmp);
            });
          });

          context('when decreasing the amp', () => {
            context('when decreasing the amp by 2x', () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER / 2n;

              itUpdatesAmpCorrectly(newAmp);
            });
          });
        });

        context('when requesting an invalid amp', () => {
          it('reverts when requesting below the min', async () => {
            const lowAmp = bn(0);
            await expect(
              pool.connect(caller).startAmplificationParameterUpdate(lowAmp, endTime)
            ).to.be.revertedWithCustomError(pool, 'AmplificationFactorTooLow');
          });

          it('reverts when requesting above the max', async () => {
            const highAmp = bn(5001);
            await expect(
              pool.connect(caller).startAmplificationParameterUpdate(highAmp, endTime)
            ).to.be.revertedWithCustomError(pool, 'AmplificationFactorTooHigh');
          });

          describe('rate limits', () => {
            let startTime: bigint;

            beforeEach('set start time', async () => {
              startTime = (await currentTimestamp()) + 100n;
              await setNextBlockTimestamp(startTime);
            });

            it('reverts when increasing the amp by more than 2x in a single day', async () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER * 2n + 1n;
              const endTime = startTime + BigInt(DAY);

              await expect(
                pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime)
              ).to.be.revertedWithCustomError(pool, 'AmpUpdateRateTooFast');
            });

            it('reverts when increasing the amp by more than 2x daily over multiple days', async () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER * 5n + 1n;
              const endTime = startTime + BigInt(DAY * 2);

              await expect(
                pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime)
              ).to.be.revertedWithCustomError(pool, 'AmpUpdateRateTooFast');
            });

            it('reverts when decreasing the amp by more than 2x in a single day', async () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER / 2n - 1n;
              const endTime = startTime + BigInt(DAY);

              await expect(
                pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime)
              ).to.be.revertedWithCustomError(pool, 'AmpUpdateRateTooFast');
            });

            it('reverts when decreasing the amp by more than 2x daily over multiple days', async () => {
              const newAmp = INITIAL_AMPLIFICATION_PARAMETER / 5n + 1n;
              const endTime = startTime + BigInt(DAY * 2);

              await expect(
                pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime)
              ).to.be.revertedWithCustomError(pool, 'AmpUpdateRateTooFast');
            });
          });
        });
      });

      context('when requesting a short duration change', () => {
        let endTime;

        it('reverts', async () => {
          endTime = (await currentTimestamp()) + BigInt(DAY - 1);
          await expect(
            pool.connect(caller).startAmplificationParameterUpdate(INITIAL_AMPLIFICATION_PARAMETER, endTime)
          ).to.be.revertedWithCustomError(pool, 'AmpUpdateDurationTooShort');
        });
      });
    }

    function itReverts() {
      it('reverts', async () => {
        await expect(
          pool.connect(other).startAmplificationParameterUpdate(INITIAL_AMPLIFICATION_PARAMETER, DAY)
        ).to.be.revertedWithCustomError(vault, 'SenderNotAllowed');
      });
    }

    context('with permission', () => {
      sharedBeforeEach('deploy pool', async () => {
        await deployPool(INITIAL_AMPLIFICATION_PARAMETER);
        caller = admin;
      });

      context('when the sender is allowed', () => {
        itStartsAnAmpUpdateCorrectly();
      });

      context('when the sender is not allowed', () => {
        itReverts();
      });
    });
  });

  describe('stopAmplificationParameterUpdate', () => {
    let caller: SignerWithAddress;

    function itStopsAnAmpUpdateCorrectly() {
      context('when there is an ongoing update', () => {
        sharedBeforeEach('start change', async () => {
          const newAmp = INITIAL_AMPLIFICATION_PARAMETER * 2n;
          const duration = BigInt(DAY * 2);

          const startTime = (await currentTimestamp()) + 100n;
          await setNextBlockTimestamp(startTime);
          const endTime = startTime + duration;

          await pool.connect(caller).startAmplificationParameterUpdate(newAmp, endTime);

          await advanceTime(duration / 3n);
          const beforeStop = await pool.getAmplificationParameter();
          expect(beforeStop.isUpdating).to.be.true;
        });

        it('stops the amp factor from updating', async () => {
          const beforeStop = await pool.getAmplificationParameter();

          await pool.connect(caller).stopAmplificationParameterUpdate();

          const afterStop = await pool.getAmplificationParameter();
          expectEqualWithError(afterStop.value, beforeStop.value, 0.001);
          expect(afterStop.isUpdating).to.be.false;

          await advanceTime(30 * DAY);

          const muchLaterAfterStop = await pool.getAmplificationParameter();
          expect(muchLaterAfterStop.value).to.be.equal(afterStop.value);
          expect(muchLaterAfterStop.isUpdating).to.be.false;
        });

        it('emits an AmpUpdateStopped event', async () => {
          const receipt = await pool.connect(caller).stopAmplificationParameterUpdate();
          expectEvent.inReceipt(await receipt.wait(), 'AmpUpdateStopped');
        });

        it('does not emit an AmpUpdateStarted event', async () => {
          const receipt = await pool.connect(caller).stopAmplificationParameterUpdate();
          expectEvent.notEmitted(await receipt.wait(), 'AmpUpdateStarted');
        });
      });

      context('when there is no ongoing update', () => {
        it('reverts', async () => {
          await expect(pool.connect(caller).stopAmplificationParameterUpdate()).to.be.revertedWithCustomError(
            pool,
            'AmpUpdateNotStarted'
          );
        });
      });
    }

    function itReverts() {
      it('reverts', async () => {
        await expect(pool.connect(other).stopAmplificationParameterUpdate()).to.be.revertedWithCustomError(
          vault,
          'SenderNotAllowed'
        );
      });
    }

    context('with permission', () => {
      sharedBeforeEach('deploy pool', async () => {
        await deployPool(INITIAL_AMPLIFICATION_PARAMETER);
        caller = admin;
      });

      context('when the sender is allowed', () => {
        itStopsAnAmpUpdateCorrectly();
      });

      context('when the sender is not allowed', () => {
        itReverts();
      });
    });
  });
});
