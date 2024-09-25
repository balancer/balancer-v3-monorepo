import { expect } from 'chai';
import { Contract, zeroPadValue, toBeHex } from 'ethers';

import { bn, negate } from '@balancer-labs/v3-helpers/src/numbers';
import { random } from 'lodash';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { ONE, ZERO, ONES_BYTES32, ZERO_BYTES32 } from '@balancer-labs/v3-helpers/src/constants';

describe('WordCodec', () => {
  let lib: Contract;

  before('deploy lib', async () => {
    lib = await deploy('WordCodecMock');
  });

  function getMaxUnsigned(bits: number): bigint {
    return (ONE << BigInt(bits)) - ONE;
  }

  function getMaxSigned(bits: number): bigint {
    return (ONE << BigInt(bits - 1)) - ONE;
  }

  function getMinSigned(bits: number): bigint {
    return (ONE << BigInt(bits - 1)) * BigInt(-ONE);
  }

  describe('encode', () => {
    describe('unsigned', () => {
      it('reverts with zero bit length', async () => {
        await expect(lib.encodeUint(0, 0, 0)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with 256 bit length', async () => {
        await expect(lib.encodeUint(0, 0, 256)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with large offset', async () => {
        await expect(lib.encodeUint(0, 256, 0)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      async function assertUnsignedEncoding(value: bigint, offset: number, bits: number) {
        const result = await lib.encodeUint(value, offset, bits);

        // We must be able to restore the original value.
        expect(await lib.decodeUint(result, offset, bits)).to.equal(value);
        // All other bits should be clear
        expect(negate(((ONE << BigInt(bits)) - ONE) << BigInt(offset)) & BigInt(result)).to.equal(0);
      }

      // We want to be able to use 2 bit values, so we can only go up to offset 254. We only cover part of the offset
      // range to keep test duration reasonable.
      for (const offset of [0, 50, 150, 254]) {
        const MAX_BITS = Math.min(256 - offset, 255);

        context(`with offset ${offset}`, () => {
          it('encodes small values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertUnsignedEncoding(ONE, offset, bits);
            }
          });

          it('encodes max values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertUnsignedEncoding(getMaxUnsigned(bits), offset, bits);
            }
          });

          it('reverts with large values', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await expect(
                assertUnsignedEncoding(getMaxUnsigned(bits) + ONE, offset, bits)
              ).to.be.revertedWithCustomError(lib, 'CodecOverflow');
            }
          });

          it('reverts with large bitsize', async () => {
            await expect(assertUnsignedEncoding(ZERO, offset, MAX_BITS + 1)).to.be.revertedWithCustomError(
              lib,
              'OutOfBounds'
            );
          });
        });
      }
    });

    describe('signed', () => {
      it('reverts with zero bit length', async () => {
        await expect(lib.encodeInt(0, 0, 0)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with 256 bit length', async () => {
        await expect(lib.encodeInt(0, 0, 256)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with large offset', async () => {
        await expect(lib.encodeInt(0, 256, 0)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      async function assertSignedEncoding(value: bigint, offset: number, bits: number) {
        const result = await lib.encodeInt(value, offset, bits);

        // We must be able to restore the original value.
        expect(await lib.decodeInt(result, offset, bits)).to.equal(value);
        // All other bits should be clear.
        expect(negate(((ONE << BigInt(bits)) - ONE) << BigInt(offset)) & BigInt(result)).to.equal(0);
      }

      // We want to be able to use 2 bit values, so we can only go up to offset 254. We only cover part of the offset
      // range to keep test duration reasonable.
      for (const offset of [0, 50, 150, 254]) {
        const MAX_BITS = Math.min(256 - offset, 255);

        context(`with offset ${offset}`, () => {
          it('encodes small positive values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedEncoding(ONE, offset, bits);
            }
          });

          it('encodes small negative values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedEncoding(BigInt(-ONE), offset, bits);
            }
          });

          it('encodes max values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedEncoding(getMaxSigned(bits), offset, bits);
            }
          });

          it('encodes min values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedEncoding(getMinSigned(bits), offset, bits);
            }
          });

          it('reverts with large positive values', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await expect(assertSignedEncoding(getMaxSigned(bits) + ONE, offset, bits)).to.be.revertedWithCustomError(
                lib,
                'CodecOverflow'
              );
            }
          });

          it('reverts with large negative values', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await expect(assertSignedEncoding(getMinSigned(bits) - ONE, offset, bits)).to.be.revertedWithCustomError(
                lib,
                'CodecOverflow'
              );
            }
          });

          it('reverts with large bitsize', async () => {
            await expect(assertSignedEncoding(ZERO, offset, MAX_BITS + 1)).to.be.revertedWithCustomError(
              lib,
              'OutOfBounds'
            );
          });
        });
      }
    });
  });

  describe('insert', () => {
    const word = zeroPadValue(toBeHex(bn(random(2 ** 255))), 32);
    describe('unsigned', () => {
      it('reverts with zero bit length', async () => {
        await expect(lib.insertUint(word, 0, 0, 0)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with 256 bit length', async () => {
        await expect(lib.insertUint(word, 0, 0, 256)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with large offset', async () => {
        await expect(lib.insertUint(word, 256, 0, 256)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      async function assertUnsignedInsertion(value: bigint, offset: number, bits: number) {
        const result = await lib.insertUint(word, value, offset, bits);

        // We must be able to restore the original value.
        expect(await lib.decodeUint(result, offset, bits)).to.equal(value);
        // All other bits should match the original word.
        const mask = negate(((ONE << BigInt(bits)) - ONE) << BigInt(offset));
        const clearedResult = BigInt(mask) & BigInt(result);
        const clearedWord = BigInt(mask) & BigInt(word);
        expect(clearedResult).to.equal(clearedWord);
      }

      // We want to be able to use 2 bit values, so we can only go up to offset 254. We only cover part of the offset
      // range to keep test duration reasonable.
      for (const offset of [0, 50, 150, 254]) {
        const MAX_BITS = Math.min(256 - offset, 255);

        context(`with offset ${offset}`, () => {
          it('inserts small values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertUnsignedInsertion(1, offset, bits);
            }
          });

          it('inserts max values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertUnsignedInsertion(getMaxUnsigned(bits), offset, bits);
            }
          });

          it('reverts with large values', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await expect(
                assertUnsignedInsertion(getMaxUnsigned(bits) + ONE, offset, bits)
              ).to.be.revertedWithCustomError(lib, 'CodecOverflow');
            }
          });

          it('reverts with large bitsize', async () => {
            await expect(assertUnsignedInsertion(ZERO, offset, MAX_BITS + 1)).to.be.revertedWithCustomError(
              lib,
              'OutOfBounds'
            );
          });
        });
      }
    });

    describe('signed', () => {
      it('reverts with zero bit length', async () => {
        await expect(lib.insertInt(word, 0, 0, 0)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with 256 bit length', async () => {
        await expect(lib.insertInt(word, 0, 0, 256)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      it('reverts with large offset', async () => {
        await expect(lib.insertInt(word, 256, 0, 256)).to.be.revertedWithCustomError(lib, 'OutOfBounds');
      });

      async function assertSignedInsertion(value: bigint, offset: number, bits: number) {
        const result = await lib.insertInt(word, value, offset, bits);

        // We must be able to restore the original value.
        expect(await lib.decodeInt(result, offset, bits)).to.equal(value);
        // All other bits should match the original word.
        const mask = negate(((ONE << BigInt(bits)) - ONE) << BigInt(offset));
        const clearedResult = BigInt(mask) & BigInt(result);
        const clearedWord = BigInt(mask) & BigInt(word);
        expect(clearedResult).to.equal(clearedWord);
      }

      // We want to be able to use 2 bit values, so we can only go up to offset 254. We only cover part of the offset
      // range to keep test duration reasonable.
      for (const offset of [0, 50, 150, 254]) {
        const MAX_BITS = Math.min(256 - offset, 255);

        context(`with offset ${offset}`, () => {
          it('inserts small positive values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedInsertion(ONE, offset, bits);
            }
          });

          it('inserts small negative values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedInsertion(BigInt(-1), offset, bits);
            }
          });

          it('inserts max values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedInsertion(getMaxSigned(bits), offset, bits);
            }
          });

          it('inserts min values of all bit sizes', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await assertSignedInsertion(getMinSigned(bits), offset, bits);
            }
          });

          it('reverts with large positive values', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await expect(assertSignedInsertion(getMaxSigned(bits) + ONE, offset, bits)).to.be.revertedWithCustomError(
                lib,
                'CodecOverflow'
              );
            }
          });

          it('reverts with large negative values', async () => {
            for (let bits = 2; bits <= MAX_BITS; bits++) {
              await expect(assertSignedInsertion(getMinSigned(bits) - ONE, offset, bits)).to.be.revertedWithCustomError(
                lib,
                'CodecOverflow'
              );
            }
          });

          it('reverts with large bitsize', async () => {
            await expect(assertSignedInsertion(ZERO, offset, MAX_BITS + 1)).to.be.revertedWithCustomError(
              lib,
              'OutOfBounds'
            );
          });
        });
      }
    });

    describe('bool', () => {
      async function assertBoolInsertion(value: boolean, offset: number) {
        const result = await lib.insertBool(word, value, offset);

        // We must be able to restore the original value.
        expect(await lib.decodeBool(result, offset)).to.equal(value);
        // All other bits should match the original word.
        const mask = negate(ONE << BigInt(offset));
        const clearedResult = BigInt(mask) & BigInt(result);
        const clearedWord = BigInt(mask) & BigInt(word);
        expect(clearedResult).to.equal(clearedWord);
      }

      for (const offset of [0, 50, 150, 254]) {
        context(`with offset ${offset}`, () => {
          it('inserts true', async () => {
            await assertBoolInsertion(true, offset);
          });

          it('inserts false', async () => {
            await assertBoolInsertion(false, offset);
          });
        });
      }
    });
  });

  describe('helpers', () => {
    it('clears word at position', async () => {
      // Starting with all 1's, inserting a 128-bit value of 0 should be the same as clearing 128 bits.
      expect(await lib.clearWordAtPosition(ONES_BYTES32, 128, 128)).to.equal(
        await lib.insertUint(ONES_BYTES32, 0, 128, 128)
      );
      // Should fail when the values are different.
      expect(await lib.clearWordAtPosition(ONES_BYTES32, 128, 128)).to.not.equal(
        await lib.insertUint(ONES_BYTES32, 0, 128, 64)
      );
    });

    it('ensures surrounding state unchanged', async () => {
      // Should be true if you pass in the same value.
      expect(await lib.isOtherStateUnchanged(ONES_BYTES32, ONES_BYTES32, 0, 255)).to.be.true;

      // Should be false if you pass in different values.
      expect(await lib.isOtherStateUnchanged(ONES_BYTES32, ZERO_BYTES32, 0, 255)).to.be.false;

      // Realistic example. Insert a value, *other* bits should be unchanged.
      const changedValue = await lib.insertUint(ONES_BYTES32, 0, 192, 32);
      expect(await lib.isOtherStateUnchanged(ONES_BYTES32, changedValue, 192, 32)).to.be.true;
    });
  });
});
