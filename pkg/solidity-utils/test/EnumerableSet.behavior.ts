import { MAX_UINT256 } from '@balancer-labs/v3-helpers/src/constants';
import { expect } from 'chai';
import { Contract } from 'ethers';

export function shouldBehaveLikeSet(store: { set: Contract }, members: Array<string>): void {
  const [addressA, addressB, addressC] = members;

  async function expectMembersMatch(set: Contract, members: Array<string>) {
    await Promise.all(members.map(async (member) => expect(await set.contains(member)).to.equal(true)));

    expect(await set.length()).to.equal(members.length.toString());

    await Promise.all(
      [...Array(members.length).keys()].map(async (index) => {
        const addressAt = await set.at(index);

        expect(addressAt).to.equal(members[index]);
      })
    );
  }

  it('starts empty', async () => {
    expect(await store.set.contains(addressA)).to.equal(false);

    await expectMembersMatch(store.set, []);
  });

  describe('add', () => {
    it('returns true when adding a new member', async () => {
      expect(await store.set.add.staticCall(addressA)).to.be.true;
    });

    it('adds an address', async () => {
      await store.set.add(addressA);

      await expectMembersMatch(store.set, [addressA]);
    });

    it('adds several addresses', async () => {
      await store.set.add(addressA);
      await store.set.add(addressB);

      await expectMembersMatch(store.set, [addressA, addressB]);
      expect(await store.set.contains(addressC)).to.equal(false);
    });

    it('returns false when adding members already in the set', async () => {
      await store.set.add(addressA);

      expect(await store.set.add.staticCall(addressA)).to.be.false;

      await expectMembersMatch(store.set, [addressA]);
    });
  });

  describe('at', () => {
    it('returns the value for an address', async () => {
      await store.set.add(addressA);

      expect(await store.set.at(0)).to.equal(addressA);
    });

    it('reverts with a custom message if the index is invalid', async () => {
      await expect(store.set.at(100)).to.be.revertedWithCustomError(store.set, 'IndexOutOfBounds');
    });
  });

  describe('indexOf', () => {
    it('returns the index of an added key', async () => {
      await store.set.add(addressA);
      await store.set.add(addressB);

      expect(await store.set.indexOf(addressA)).to.equal(0);
      expect(await store.set.indexOf(addressB)).to.equal(1);
    });

    it('adding and removing keys can change the index', async () => {
      await store.set.add(addressA);
      await store.set.add(addressB);

      await store.set.remove(addressA);

      // B is now the only element; its index must be 0
      expect(await store.set.indexOf(addressB)).to.equal(0);
    });

    it('reverts if the key is not in the map', async () => {
      await expect(store.set.indexOf(addressA)).to.be.revertedWithCustomError(store.set, 'ElementNotFound');
    });
  });

  describe('unchecked_indexOf', () => {
    it('returns the index of an added key', async () => {
      await store.set.add(addressA);
      await store.set.add(addressB);

      expect(await store.set.unchecked_indexOf(addressA)).to.equal(0);
      expect(await store.set.unchecked_indexOf(addressB)).to.equal(1);
    });

    it('adding and removing keys can change the index', async () => {
      await store.set.add(addressA);
      await store.set.add(addressB);

      await store.set.remove(addressA);

      // B is now the only element; its index must be 0
      expect(await store.set.unchecked_indexOf(addressB)).to.equal(0);
    });

    it('returns -1 if the key is not in the map', async () => {
      expect(await store.set.unchecked_indexOf(addressA)).to.be.equal(MAX_UINT256);
    });
  });

  describe('remove', () => {
    it('returns true when removing members', async () => {
      await store.set.add(addressA);

      expect(await store.set.remove.staticCall(addressA)).to.be.true;
    });

    it('removes added members', async () => {
      await store.set.add(addressA);
      await store.set.remove(addressA);

      expect(await store.set.contains(addressA)).to.equal(false);
      await expectMembersMatch(store.set, []);
    });

    it('returns false when removing members that used to be in the set', async () => {
      await store.set.add(addressA);
      await store.set.remove(addressA);

      expect(await store.set.remove.staticCall(addressA)).to.be.false;
    });

    it('returns false when removing members that were never in the set', async () => {
      expect(await store.set.contains(addressA)).to.equal(false);
    });

    it('adds and removes multiple members', async () => {
      // []

      await store.set.add(addressA);
      await store.set.add(addressC);

      // [A, C]

      await store.set.remove(addressA);
      await store.set.remove(addressB);

      // [C]

      await store.set.add(addressB);

      // [C, B]

      await store.set.add(addressA);
      await store.set.remove(addressC);

      // [B, A]

      await store.set.add(addressA);
      await store.set.add(addressB);

      // [B, A]

      await store.set.add(addressC);
      await store.set.remove(addressA);

      // [B, C]

      await store.set.add(addressA);
      await store.set.remove(addressB);

      // [C, A]

      await expectMembersMatch(store.set, [addressC, addressA]);

      expect(await store.set.contains(addressB)).to.equal(false);
    });
  });
}
