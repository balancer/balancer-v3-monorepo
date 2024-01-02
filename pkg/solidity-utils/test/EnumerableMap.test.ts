import { Contract } from 'ethers';
import { expect } from 'chai';
import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { zip } from 'lodash';

describe('EnumerableMap', () => {
  function shouldBehaveLikeMap(mapType: string, keys: Array<string | bigint>, values: Array<string | bigint>): void {
    const [keyA, keyB, keyC] = keys;
    const [valueA, valueB, valueC] = values;

    async function expectMembersMatch(map: Contract, keys: Array<string | bigint>, values: Array<string | bigint>) {
      expect(keys.length).to.equal(values.length);

      await Promise.all(keys.map(async (key) => expect(await map.contains(key)).to.equal(true)));

      expect(await map.length()).to.equal(keys.length);

      expect(await Promise.all(keys.map((key) => map.get(key)))).to.deep.equal(values);

      // To compare key-value pairs, we zip keys and values, and convert BNs to
      // strings to workaround Chai limitations when dealing with nested arrays
      expect(
        await Promise.all(
          [...Array(keys.length).keys()].map(async (index) => {
            const entryAt = await map.at(index);
            const entryAtUnchecked = await map.unchecked_at(index);
            const valueAtUnchecked = await map.unchecked_valueAt(index);

            expect(entryAt.key).to.equal(entryAtUnchecked.key);
            expect(entryAt.value).to.equal(entryAtUnchecked.value);
            expect(entryAt.value).to.equal(valueAtUnchecked);

            return [entryAt.key.toString(), entryAt.value];
          })
        )
      ).to.have.same.deep.members(
        zip(
          keys.map((k) => k),
          values
        )
      );
    }

    let map: Contract;

    sharedBeforeEach('deploy Map', async () => {
      map = await deploy(`Enumerable${mapType}MapMock`);
    });

    it('starts empty', async () => {
      expect(await map.contains(keyA)).to.equal(false);

      await expectMembersMatch(map, [], []);
    });

    describe('set', () => {
      it('returns true when adding a key', async () => {
        expect(await map.set.staticCall(keyA, valueA)).to.be.true;
      });

      it('adds a key', async () => {
        await map.set(keyA, valueA);

        await expectMembersMatch(map, [keyA], [valueA]);
      });

      it('adds several keys', async () => {
        await map.set(keyA, valueA);
        await map.set(keyB, valueB);

        await expectMembersMatch(map, [keyA, keyB], [valueA, valueB]);
        expect(await map.contains(keyC)).to.equal(false);
      });

      it('returns false when adding keys already in the set', async () => {
        await map.set(keyA, valueA);

        expect(await map.set.staticCall(keyA, valueA)).to.be.false;
      });

      it('updates values for keys already in the set', async () => {
        await map.set(keyA, valueA);
        await map.set(keyA, valueB);

        await expectMembersMatch(map, [keyA], [valueB]);
      });
    });

    describe('get', () => {
      it('returns the value for a key', async () => {
        await map.set(keyA, valueA);

        expect(await map.get(keyA)).to.equal(valueA);
      });

      it('reverts with a custom message if the key is not in the map', async () => {
        await expect(map.get(keyA)).to.be.revertedWithCustomError(map, 'KeyNotFound');
      });
    });

    describe('at', () => {
      it('returns the value for a key', async () => {
        await map.set(keyA, valueA);

        expect((await map.at(0)).key).to.equal(keyA);
        expect((await map.at(0)).value).to.equal(valueA);
      });

      it('reverts with a custom message if the index is invalid', async () => {
        await expect(map.at(100)).to.be.revertedWithCustomError(map, 'IndexOutOfBounds');
      });
    });

    describe('indexOf', () => {
      it('returns the index of an added key', async () => {
        await map.set(keyA, valueA);
        await map.set(keyB, valueB);

        expect(await map.indexOf(keyA)).to.equal(0);
        expect(await map.indexOf(keyB)).to.equal(1);
      });

      it('adding and removing keys can change the index', async () => {
        await map.set(keyA, valueA);
        await map.set(keyB, valueB);

        await map.remove(keyA);

        // B is now the only element; its index must be 0
        expect(await map.indexOf(keyB)).to.equal(0);
      });

      it('reverts if the key is not in the map', async () => {
        await expect(map.indexOf(keyA)).to.be.revertedWithCustomError(map, 'KeyNotFound');
      });
    });

    describe('unchecked_indexOf', () => {
      it('returns the index of an added key, plus one', async () => {
        await map.set(keyA, valueA);
        await map.set(keyB, valueB);

        expect(await map.unchecked_indexOf(keyA)).to.equal(0 + 1);
        expect(await map.unchecked_indexOf(keyB)).to.equal(1 + 1);
      });

      it('adding and removing keys can change the index', async () => {
        await map.set(keyA, valueA);
        await map.set(keyB, valueB);

        await map.remove(keyA);

        // B is now the only element; its index must be 0
        expect(await map.unchecked_indexOf(keyB)).to.equal(0 + 1);
      });

      it('returns a zero index if the key is not in the map', async () => {
        expect(await map.unchecked_indexOf(keyA)).to.be.equal(0);
      });
    });

    describe('unchecked_setAt', () => {
      it('updates a value', async () => {
        await map.set(keyA, valueA);

        const indexA = (await map.unchecked_indexOf(keyA)) - 1n;
        await map.unchecked_setAt(indexA, valueB);

        await expectMembersMatch(map, [keyA], [valueB]);
      });

      it('updates several values', async () => {
        await map.set(keyA, valueA);
        await map.set(keyB, valueB);

        const indexA = (await map.unchecked_indexOf(keyA)) - 1n;
        const indexB = (await map.unchecked_indexOf(keyB)) - 1n;

        await map.unchecked_setAt(indexA, valueC);
        await map.unchecked_setAt(indexB, valueA);

        await expectMembersMatch(map, [keyA, keyB], [valueC, valueA]);
      });

      it('does not revert when setting indexes outside of the map', async () => {
        const length = await map.length();

        await expect(await map.unchecked_setAt(length, valueC)).not.to.be.reverted;
      });
    });

    describe('unchecked_at', () => {
      it('returns an entry at an index', async () => {
        await map.set(keyA, valueA);

        const indexA = (await map.unchecked_indexOf(keyA)) - 1n;
        const entry = await map.unchecked_at(indexA);

        expect(entry.key).to.equal(keyA);
        expect(entry.value).to.equal(valueA);
      });

      it('does not revert when accessing indexes outside of the map', async () => {
        const length = await map.length();
        await map.unchecked_at(length);
      });
    });

    describe('unchecked_valueAt', () => {
      it('returns a value at an index', async () => {
        await map.set(keyA, valueA);

        const indexA = (await map.unchecked_indexOf(keyA)) - 1n;
        const value = await map.unchecked_valueAt(indexA);

        expect(value).to.equal(valueA);
      });

      it('does not revert when accessing indexes outside of the map', async () => {
        const length = await map.length();

        // The normal await expect(fn) pattern doesn't work here, because it's a view function (with no receipt)
        // that returns a bytes32, which hardhat interprets as a "TransactionResponse" and tries to parse as a
        // receipt. It fails with "receipt should not be null."
        // Good enough to simply call the function, as in the 'unchecked_at' test above.
        // await expect(map.unchecked_valueAt(length)).not.to.be.reverted;
        await map.unchecked_valueAt(length);
      });
    });

    describe('remove', () => {
      it('returns true when removing keys in the set', async () => {
        await map.set(keyA, valueA);

        expect(await map.remove.staticCall(keyA)).to.be.true;
      });

      it('removes added keys', async () => {
        await map.set(keyA, valueA);
        await map.remove(keyA);

        expect(await map.contains(keyA)).to.equal(false);
        await expectMembersMatch(map, [], []);
      });

      it('returns false when removing keys not in the set', async () => {
        await map.set(keyA, valueA);
        await map.remove(keyA);

        expect(await map.remove.staticCall(keyA)).to.be.false;
      });

      it('returns false when removing keys not in the set', async () => {
        expect(await map.contains(keyA)).to.equal(false);
      });

      it('adds and removes multiple keys', async () => {
        // []

        await map.set(keyA, valueA);
        await map.set(keyC, valueC);

        // [A, C]

        await map.remove(keyA);
        await map.remove(keyB);

        // [C]

        await map.set(keyB, valueB);

        // [C, B]

        await map.set(keyA, valueA);
        await map.remove(keyC);

        // [A, B]

        await map.set(keyA, valueA);
        await map.set(keyB, valueB);

        // [A, B]

        await map.set(keyC, valueC);
        await map.remove(keyA);

        // [B, C]

        await map.set(keyA, valueA);
        await map.remove(keyB);

        // [A, C]

        await expectMembersMatch(map, [keyA, keyC], [valueA, valueC]);

        expect(await map.contains(keyB)).to.equal(false);
      });
    });
  }

  describe('EnumerableMap types', () => {
    describe('EnumerableIERC20ToUint256Map', () => {
      const keys = [
        '0x8B40ECf815AC8d53aB4AD2a00248DE77296344Db',
        '0x638141Eb8905D9A55D81610f45bC2B47120059e7',
        '0x7571A57e94F046725612f786Aa9bf44ce6b56894',
      ];

      const values = [42n, 1337n, 9999n];

      shouldBehaveLikeMap('IERC20ToUint256', keys, values);
    });

    describe('EnumerableIERC20ToBytes32Map', () => {
      const keys = [
        '0x8B40ECf815AC8d53aB4AD2a00248DE77296344Db',
        '0x638141Eb8905D9A55D81610f45bC2B47120059e7',
        '0x7571A57e94F046725612f786Aa9bf44ce6b56894',
      ];

      const values = [
        '0x41b1a0649752af1b28b3dc29a1556eee781e4a4c3a1f7f53f90fa834de098c4d',
        '0x435cd288e3694b535549c3af56ad805c149f92961bf84a1c647f7d86fc2431b4',
        '0xf2d05ec5c5729fb559780c70a93ca7b4ee2ca37f64e62fa31046b324f60d9447',
      ];

      shouldBehaveLikeMap('IERC20ToBytes32', keys, values);
    });
  });
});
