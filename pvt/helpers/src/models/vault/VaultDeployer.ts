import { ethers } from 'hardhat';
import { BaseContract } from 'ethers';

import * as contract from '../../contract';
import { VaultDeployment, VaultDeploymentInputParams, VaultDeploymentParams } from './types';

import TypesConverter from '../types/TypesConverter';
import { PoolRegistrationLib, Vault } from '@balancer-labs/v3-vault/typechain-types';
import { VaultMock } from '@balancer-labs/v3-vault/typechain-types';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

export async function deploy(params: VaultDeploymentInputParams = {}): Promise<VaultDeployment> {
  const deployment = TypesConverter.toVaultDeployment(params);

  let { admin } = deployment;

  const { from, mocked } = deployment;
  if (!admin) admin = from || (await ethers.getSigners())[0];
  const basicAuthorizer = await _deployBasicAuthorizer(admin);
  const vaultDeployment = await (mocked ? _deployMocked : _deployReal)(deployment, basicAuthorizer);

  return vaultDeployment;
}

async function _deployReal(deployment: VaultDeploymentParams, authorizer: BaseContract): Promise<VaultDeployment> {
  const { from, pauseWindowDuration, bufferPeriodDuration } = deployment;
  const poolRegistrationLib: PoolRegistrationLib = await contract.deploy('PoolRegistrationLib');

  const args = [await authorizer.getAddress(), pauseWindowDuration, bufferPeriodDuration];
  const vault: Vault = await contract.deploy('v3-vault/Vault', {
    args,
    from,
    libraries: { PoolRegistrationLib: await poolRegistrationLib.getAddress() },
  });

  return {
    vault,
    poolRegistrationLib,
  };
}

async function _deployMocked(deployment: VaultDeploymentParams, authorizer: BaseContract): Promise<VaultDeployment> {
  const { from, pauseWindowDuration, bufferPeriodDuration } = deployment;
  const poolRegistrationLib: PoolRegistrationLib = await contract.deploy('PoolRegistrationLib');

  const args = [await authorizer.getAddress(), pauseWindowDuration, bufferPeriodDuration];
  const vault: VaultMock = await contract.deploy('v3-vault/VaultMock', {
    args,
    from,
    libraries: { PoolRegistrationLib: await poolRegistrationLib.getAddress() },
  });

  return {
    vault,
    poolRegistrationLib,
  };
}

async function _deployBasicAuthorizer(admin: SignerWithAddress): Promise<BasicAuthorizerMock> {
  return contract.deploy('v3-solidity-utils/BasicAuthorizerMock', { args: [], from: admin });
}
