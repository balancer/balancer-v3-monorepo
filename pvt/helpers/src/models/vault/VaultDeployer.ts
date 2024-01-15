import { ethers } from 'hardhat';
import { BaseContract } from 'ethers';

import * as contract from '../../contract';
import { VaultDeploymentInputParams, VaultDeploymentParams } from './types';

import TypesConverter from '../types/TypesConverter';
import { Vault, VaultExtension } from '@balancer-labs/v3-vault/typechain-types';
import { VaultMock } from '@balancer-labs/v3-vault/typechain-types';
import { BasicAuthorizerMock } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

export async function deploy(params: VaultDeploymentInputParams = {}): Promise<Vault> {
  const deployment = await TypesConverter.toVaultDeployment(params);

  const basicAuthorizer = await deployBasicAuthorizer(deployment.admin);
  return await deployReal(deployment, basicAuthorizer);
}

export async function deployMock(params: VaultDeploymentInputParams = {}): Promise<VaultMock> {
  const deployment = await TypesConverter.toVaultDeployment(params);

  const basicAuthorizer = await deployBasicAuthorizer(deployment.admin);
  return await deployMocked(deployment, basicAuthorizer);
}

async function deployReal(deployment: VaultDeploymentParams, authorizer: BaseContract): Promise<Vault> {
  const { admin, pauseWindowDuration, bufferPeriodDuration } = deployment;

  const futureVaultAddress = await getVaultAddress(admin);

  const vaultExtension: VaultExtension = await contract.deploy('v3-vault/VaultExtension', {
    args: [futureVaultAddress],
    from: admin,
  });

  const args = [vaultExtension, authorizer, pauseWindowDuration, bufferPeriodDuration];
  return await contract.deploy('v3-vault/Vault', {
    args,
    from: admin,
  });
}

async function deployMocked(deployment: VaultDeploymentParams, authorizer: BaseContract): Promise<VaultMock> {
  const { admin, pauseWindowDuration, bufferPeriodDuration } = deployment;

  const futureVaultAddress = await getVaultAddress(admin);

  const vaultExtension: VaultExtension = await contract.deploy('v3-vault/VaultExtensionMock', {
    args: [futureVaultAddress],
    from: admin,
  });

  const args = [vaultExtension, authorizer, pauseWindowDuration, bufferPeriodDuration];
  return await contract.deploy('v3-vault/VaultMock', {
    args,
    from: admin,
  });
}

/// Returns the Vault address to be deployed, assuming the VaultExtension is deployed by the same account beforehand.
async function getVaultAddress(from: SignerWithAddress): Promise<string> {
  const nonce = await from.getNonce();
  const futureAddress = ethers.getCreateAddress({
    from: from.address,
    nonce: nonce + 1,
  });
  return futureAddress;
}

async function deployBasicAuthorizer(admin: SignerWithAddress): Promise<BasicAuthorizerMock> {
  return contract.deploy('v3-solidity-utils/BasicAuthorizerMock', { args: [], from: admin });
}
