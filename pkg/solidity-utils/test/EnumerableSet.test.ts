import { Contract } from 'ethers';
import { expect } from 'chai';

import { deploy } from '@balancer-labs/v3-helpers/src/contract';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';

describe('EnumerableSet', () => {
  function shouldBehaveLikeSet(setType: string, members: Array<string>): void {
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

    let set: Contract;

    sharedBeforeEach('deploy Set', async () => {
      set = await deploy(`Enumerable${setType}Mock`);
    });

    it('starts empty', async () => {
      expect(await set.contains(addressA)).to.equal(false);

      await expectMembersMatch(set, []);
    });

    describe('add', () => {
      it('returns true when adding a new member', async () => {
        expect(await set.add.staticCall(addressA)).to.be.true;
      });

      it('adds an address', async () => {
        await set.add(addressA);

        await expectMembersMatch(set, [addressA]);
      });

      it('adds several addresses', async () => {
        await set.add(addressA);
        await set.add(addressB);

        await expectMembersMatch(set, [addressA, addressB]);
        expect(await set.contains(addressC)).to.equal(false);
      });

      it('returns false when adding members already in the set', async () => {
        await set.add(addressA);

        expect(await set.add.staticCall(addressA)).to.be.false;

        await expectMembersMatch(set, [addressA]);
      });
    });

    describe('at', () => {
      it('returns the value for an address', async () => {
        await set.add(addressA);

        expect(await set.at(0)).to.equal(addressA);
      });

      it('reverts with a custom message if the index is invalid', async () => {
        await expect(set.at(100)).to.be.revertedWithCustomError(set, 'IndexOutOfBounds');
      });
    });

    describe('indexOf', () => {
      it('returns the index of an added key', async () => {
        await set.add(addressA);
        await set.add(addressB);

        expect(await set.indexOf(addressA)).to.equal(0);
        expect(await set.indexOf(addressB)).to.equal(1);
      });

      it('adding and removing keys can change the index', async () => {
        await set.add(addressA);
        await set.add(addressB);

        await set.remove(addressA);

        // B is now the only element; its index must be 0
        expect(await set.indexOf(addressB)).to.equal(0);
      });

      it('reverts if the key is not in the set', async () => {
        await expect(set.indexOf(addressA)).to.be.revertedWithCustomError(set, 'ElementNotFound');
      });
    });

    describe('unchecked_indexOf', () => {
      it('returns the index of an added key', async () => {
        await set.add(addressA);
        await set.add(addressB);

        expect(await set.unchecked_indexOf(addressA)).to.equal(0);
        expect(await set.unchecked_indexOf(addressB)).to.equal(1);
      });

      it('adding and removing keys can change the index', async () => {
        await set.add(addressA);
        await set.add(addressB);

        await set.remove(addressA);

        // B is now the only element; its index must be 0
        expect(await set.unchecked_indexOf(addressB)).to.equal(0);
      });

      it('returns 0 if the key is not in the set', async () => {
        expect(await set.unchecked_indexOf(addressA)).to.be.equal(0);
      });
    });

    describe('remove', () => {
      it('returns true when removing members', async () => {
        await set.add(addressA);

        expect(await set.remove.staticCall(addressA)).to.be.true;
      });

      it('removes added members', async () => {
        await set.add(addressA);
        await set.remove(addressA);

        expect(await set.contains(addressA)).to.equal(false);
        await expectMembersMatch(set, []);
      });

      it('returns false when removing members that used to be in the set', async () => {
        await set.add(addressA);
        await set.remove(addressA);

        expect(await set.remove.staticCall(addressA)).to.be.false;
      });

      it('returns false when removing members that were never in the set', async () => {
        expect(await set.contains(addressA)).to.equal(false);
      });

      it('adds and removes multiple members', async () => {
        // []

        await set.add(addressA);
        await set.add(addressC);

        // [A, C]

        await set.remove(addressA);
        await set.remove(addressB);

        // [C]

        await set.add(addressB);

        // [C, B]

        await set.add(addressA);
        await set.remove(addressC);

        // [B, A]

        await set.add(addressA);
        await set.add(addressB);

        // [B, A]

        await set.add(addressC);
        await set.remove(addressA);

        // [B, C]

        await set.add(addressA);
        await set.remove(addressB);

        // [C, A]

        await expectMembersMatch(set, [addressC, addressA]);

        expect(await set.contains(addressB)).to.equal(false);
      });
    });
  }

  describe('EnumerableAddressSet', () => {
    const members = [
      '0x8B40ECf815AC8d53aB4AD2a00248DE77296344Db',
      '0x638141Eb8905D9A55D81610f45bC2B47120059e7',
      '0x7571A57e94F046725612f786Aa9bf44ce6b56894',
    ];

    shouldBehaveLikeSet('AddressSet', members);
  });
});
