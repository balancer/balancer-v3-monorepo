import { ethers } from 'hardhat';
import { expect } from 'chai';
import { PoolMock } from '@balancer-labs/v3-vault/typechain-types/contracts/test/PoolMock';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { sharedBeforeEach } from '@balancer-labs/v3-common/sharedBeforeEach';
import { MAX_UINT256, ZERO_ADDRESS } from '@balancer-labs/v3-helpers/src/constants';
import { fp } from '@balancer-labs/v3-helpers/src/numbers';
import { impersonate } from '@balancer-labs/v3-helpers/src/signers';
import { setupEnvironment } from './poolSetup';
import '@balancer-labs/v3-common/setupTests';
import { MONTH } from '@balancer-labs/v3-helpers/src/time';
import { IVaultMock } from '@balancer-labs/v3-interfaces/typechain-types';
import { deploy, getArtifact } from '@balancer-labs/v3-helpers/src/contract';
import { NullAuthorizer, VaultExtension, VaultFactory } from '../typechain-types';
import { ProtocolFeeController } from '@balancer-labs/v3-pool-weighted/typechain-types';

describe('BalancerPoolToken', function () {
  const PAUSE_WINDOW_DURATION = MONTH * 9;

  let vault: IVaultMock;
  let poolA: PoolMock;
  let poolB: PoolMock;

  let user: SignerWithAddress;
  let other: SignerWithAddress;
  let relayer: SignerWithAddress;

  before('setup signers', async () => {
    [, user, other, relayer] = await ethers.getSigners();
  });

  describe('VaultFactory', async () => {
    it('deploys factory', async () => {
      const pauseWindowDuration = 3 * MONTH * 12;
      const bufferWindowDuration = MONTH;
      const minTradeAmount = 1e6;
      const minWrapAmount = 1e4;

      const authorizer = (await deploy('NullAuthorizer')) as NullAuthorizer;
      const vaultAdminBytecode = getArtifact('VaultAdmin').bytecode;
      const vaultExtensionBytecode = getArtifact('VaultExtension').bytecode;
      const vaultBytecode = getArtifact('Vault').bytecode;
      console.log('vault bytecode: ', vaultBytecode);

      const salt = '0x000000000000000000000000000000000000000000000000000000000000BEEF';

      const factory = (await deploy('VaultFactory', {
        args: [
          authorizer,
          pauseWindowDuration,
          bufferWindowDuration,
          minTradeAmount,
          minWrapAmount,
          ethers.keccak256(vaultBytecode),
          ethers.keccak256(vaultExtensionBytecode),
          ethers.keccak256(vaultAdminBytecode),
        ],
      })) as unknown as VaultFactory;

      const vaultAddress = await factory.getDeploymentAddress(salt);

      const protocolFeeController = (await deploy('ProtocolFeeController', {
        args: [vaultAddress],
      })) as unknown as ProtocolFeeController;
      const vaultAdmin = await deploy('VaultAdmin', {
        args: [vaultAddress, pauseWindowDuration, bufferWindowDuration, minTradeAmount, minWrapAmount],
      });

      const vaultExtension = (await deploy('VaultExtension', {
        args: [vaultAddress, vaultAdmin],
      })) as unknown as VaultExtension;

      console.log('deploying proxy');
      await factory.deployProxy(salt);

      console.log('protocol fee controller vault: ', await protocolFeeController.vault());
      console.log('vault extension vault: ', await vaultExtension.vault());

      // const bytecodeWithArgs = ethers.toUtf8Bytes(
      //   ethers.solidityPacked(
      //     ['bytes', 'bytes'],
      //     [
      //       vaultBytecode,
      //       ethers.toUtf8Bytes(
      //         ethers.AbiCoder.defaultAbiCoder().encode(
      //           ['address', 'address', 'address'],
      //           [
      //             await vaultExtension.getAddress(),
      //             await authorizer.getAddress(),
      //             await protocolFeeController.getAddress(),
      //           ]
      //         )
      //       ),
      //     ]
      //   )
      // );
      console.log('About to deploy vault at ', vaultAddress);
      const tx = await factory.createStage3(
        salt,
        vaultBytecode,
        await vaultExtension.getAddress(),
        await protocolFeeController.getAddress()
      );
      const receipt = await tx.wait();
      console.log('vault deployed; gas used: ', receipt?.gasUsed);
    });
  });
});
