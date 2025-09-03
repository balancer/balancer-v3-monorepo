import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';

import * as VaultDeployer from '@balancer-labs/v3-helpers/src/models/vault/VaultDeployer';
import { actionId } from '@balancer-labs/v3-helpers/src/models/misc/actions';
import { advanceTime, DAY, WEEK } from '@balancer-labs/v3-helpers/src/time';
import { deploy, deployedAt } from '@balancer-labs/v3-helpers/src/contract';
import { ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import {
  BasicAuthorizerMock,
  BasicAuthorizerMock__factory,
  MockAuthenticatedContract,
} from '@balancer-labs/v3-vault/typechain-types';
import TypesConverter from '@balancer-labs/v3-helpers/src/models/types/TypesConverter';
import { IVault } from '@balancer-labs/v3-interfaces/typechain-types';
import { TimelockAuthorizer } from '../typechain-types';

describe('TimelockAuthorizerMigrator', () => {
  let root: SignerWithAddress;
  let user1: SignerWithAddress, user2: SignerWithAddress, user3: SignerWithAddress;
  let granter1: SignerWithAddress, granter2: SignerWithAddress, granter3: SignerWithAddress;
  let vault: Contract, migrator: Contract;
  let iVault: IVault;
  let newAuthorizer: TimelockAuthorizer;
  let oldAuthorizer: BasicAuthorizerMock;

  before('set up signers', async () => {
    [, user1, user2, user3, granter1, granter2, granter3, root] = await ethers.getSigners();
  });

  interface RoleData {
    grantee: string;
    role: string;
    target: string;
  }

  interface DelayData {
    actionId: string;
    newDelay: BigNumberish;
  }

  let rolesData: RoleData[];
  let grantersData: RoleData[];
  let revokersData: RoleData[];
  let executeDelaysData: DelayData[];
  let grantDelaysData: DelayData[];

  const CHANGE_ROOT_DELAY = WEEK * 4;

  const ROLE_1 = '0x0000000000000000000000000000000000000000000000000000000000000001';
  const ROLE_2 = '0x0000000000000000000000000000000000000000000000000000000000000002';
  const ROLE_3 = '0x0000000000000000000000000000000000000000000000000000000000000003';

  sharedBeforeEach('set up vault', async () => {
    vault = await VaultDeployer.deploy();
    iVault = await TypesConverter.toIVault(vault);

    oldAuthorizer = BasicAuthorizerMock__factory.connect(await iVault.getAuthorizer(), iVault.runner);
  });

  sharedBeforeEach('set up permissions', async () => {
    const target = (await deploy('v3-vault/MockAuthenticatedContract', {
      args: [vault],
    })) as unknown as MockAuthenticatedContract;
    rolesData = [
      { grantee: user1.address, role: ROLE_1, target: await target.getAddress() },
      { grantee: user2.address, role: ROLE_2, target: await target.getAddress() },
      { grantee: user3.address, role: ROLE_3, target: ZERO_ADDRESS },
    ];
    grantersData = [
      { grantee: granter1.address, role: ROLE_1, target: await target.getAddress() },
      { grantee: granter2.address, role: ROLE_2, target: ZERO_ADDRESS },
      { grantee: granter3.address, role: ROLE_3, target: await target.getAddress() },
    ];
    revokersData = [
      { grantee: user1.address, role: ROLE_1, target: await target.getAddress() },
      { grantee: granter1.address, role: ROLE_2, target: await target.getAddress() },
      { grantee: user3.address, role: ROLE_3, target: ZERO_ADDRESS },
    ];
    executeDelaysData = [
      // We must set this delay first to satisfy the `DELAY_EXCEEDS_SET_AUTHORIZER` check.
      { actionId: await actionId(iVault, 'setAuthorizer'), newDelay: 30 * DAY },
      { actionId: ROLE_1, newDelay: 14 * DAY },
      { actionId: ROLE_2, newDelay: 7 * DAY },
    ];
    grantDelaysData = [
      { actionId: ROLE_2, newDelay: 30 * DAY },
      { actionId: ROLE_3, newDelay: 30 * DAY },
    ];
  });

  sharedBeforeEach('grant roles on old Authorizer', async () => {
    await oldAuthorizer.grantRole(ROLE_1, user1.address);
    await oldAuthorizer.grantRole(ROLE_2, user2.address);
    await oldAuthorizer.grantRole(ROLE_3, user3.address);
  });

  sharedBeforeEach('deploy migrator', async () => {
    const args = [
      root.address,
      oldAuthorizer,
      vault,
      CHANGE_ROOT_DELAY,
      rolesData,
      grantersData,
      revokersData,
      executeDelaysData,
      grantDelaysData,
    ];
    migrator = await deploy('TimelockAuthorizerMigrator', { args });
    newAuthorizer = (await deployedAt(
      'TimelockAuthorizer',
      await migrator.newAuthorizer()
    )) as unknown as TimelockAuthorizer;
    const setAuthorizerActionId = await actionId(iVault, 'setAuthorizer');
    await oldAuthorizer.grantRole(setAuthorizerActionId, migrator);
  });

  context('constructor', () => {
    context('when attempting to migrate a role which does not exist on previous Authorizer', () => {
      let tempAuthorizer: Contract;

      sharedBeforeEach('set up vault', async () => {
        tempAuthorizer = await deploy('v3-vault/BasicAuthorizerMock');
      });

      it('reverts', async () => {
        const args = [
          root.address,
          tempAuthorizer,
          vault,
          CHANGE_ROOT_DELAY,
          rolesData,
          grantersData,
          revokersData,
          executeDelaysData,
          grantDelaysData,
        ];
        await expect(deploy('TimelockAuthorizerMigrator', { args })).to.be.revertedWith('UNEXPECTED_ROLE');
      });
    });

    it('migrates all roles properly', async () => {
      for (const roleData of rolesData) {
        expect(await newAuthorizer.hasPermission(roleData.role, roleData.grantee, roleData.target)).to.be.true;
      }
    });

    it('sets up granters properly', async () => {
      for (const granterData of grantersData) {
        expect(await newAuthorizer.isGranter(granterData.role, granterData.grantee, granterData.target)).to.be.true;
      }
    });

    it('sets up revokers properly', async () => {
      for (const revokerData of revokersData) {
        expect(await newAuthorizer.isRevoker(revokerData.grantee, revokerData.target)).to.be.true;
      }
    });

    it('does not set the new authorizer immediately', async () => {
      expect(await iVault.getAuthorizer()).to.be.equal(oldAuthorizer);
    });

    it('sets the migrator as the current root', async () => {
      expect(await newAuthorizer.isRoot(migrator)).to.be.true;
    });

    it('sets root as the pending root', async () => {
      expect(await newAuthorizer.getPendingRoot()).to.equal(root.address);
    });
  });

  context('executeDelays', () => {
    context("when MINIMUM_CHANGE_DELAY_EXECUTION_DELAY hasn't passed", () => {
      it('reverts', async () => {
        await expect(migrator.executeDelays()).to.be.revertedWith('EXECUTION_NOT_YET_EXECUTABLE');
      });
    });

    context('when MINIMUM_CHANGE_DELAY_EXECUTION_DELAY has passed', () => {
      sharedBeforeEach('advance time', async () => {
        const MINIMUM_CHANGE_DELAY_EXECUTION_DELAY = await newAuthorizer.MINIMUM_CHANGE_DELAY_EXECUTION_DELAY();
        await advanceTime(MINIMUM_CHANGE_DELAY_EXECUTION_DELAY);
      });

      it('sets up delays properly', async () => {
        await migrator.executeDelays();

        for (const delayData of executeDelaysData) {
          expect(await newAuthorizer.getActionIdDelay(delayData.actionId)).to.be.eq(delayData.newDelay);
        }
      });

      it('sets up granter delays properly', async () => {
        await migrator.executeDelays();

        for (const delayData of grantDelaysData) {
          expect(await newAuthorizer.getActionIdGrantDelay(delayData.actionId)).to.be.eq(delayData.newDelay);
        }
      });
    });
  });

  context('finalizeMigration', () => {
    sharedBeforeEach('advance time', async () => {
      const MINIMUM_CHANGE_DELAY_EXECUTION_DELAY = await newAuthorizer.MINIMUM_CHANGE_DELAY_EXECUTION_DELAY();
      await advanceTime(MINIMUM_CHANGE_DELAY_EXECUTION_DELAY);
      await migrator.executeDelays();
    });

    context('when new root has not claimed ownership over TimelockAuthorizer', () => {
      it('reverts', async () => {
        await expect(migrator.finalizeMigration()).to.be.revertedWith('ROOT_NOT_CLAIMED_YET');
      });
    });

    context('when new root has claimed ownership over TimelockAuthorizer', () => {
      sharedBeforeEach('claim root', async () => {
        await newAuthorizer.connect(root).claimRoot();
      });

      it('sets the new Authorizer on the Vault', async () => {
        await migrator.finalizeMigration();

        expect(await iVault.getAuthorizer()).to.be.equal(newAuthorizer);
      });
    });
  });
});
