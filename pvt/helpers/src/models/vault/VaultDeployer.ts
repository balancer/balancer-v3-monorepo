import { ethers } from 'hardhat';
import { BaseContract } from 'ethers';

import * as contract from '../../contract';
import { VaultDeploymentInputParams, VaultDeploymentParams } from './types';

import TypesConverter from '../types/TypesConverter';
import {
  ProtocolFeeController,
  Vault,
  VaultAdmin,
  VaultAdminMock,
  VaultExtension,
  VaultExtensionMock,
} from '@balancer-labs/v3-vault/typechain-types';
import { VaultMock, BasicAuthorizerMock } from '@balancer-labs/v3-vault/typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

const _MINIMUM_TRADE_AMOUNT = 1e6;
const _MINIMUM_WRAP_AMOUNT = 1e3;

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

  const vaultAdmin: VaultAdmin = await contract.deploy('v3-vault/VaultAdmin', {
    args: [futureVaultAddress, pauseWindowDuration, bufferPeriodDuration, _MINIMUM_TRADE_AMOUNT, _MINIMUM_WRAP_AMOUNT],
    from: admin,
  });

  const vaultExtension: VaultExtension = await contract.deploy('v3-vault/VaultExtension', {
    args: [futureVaultAddress, vaultAdmin],
    from: admin,
  });

  const protocolFeeController: ProtocolFeeController = await contract.deploy('v3-vault/ProtocolFeeController', {
    args: [futureVaultAddress],
    from: admin,
  });

  return await contract.deploy('v3-vault/Vault', {
    args: [vaultExtension, authorizer, protocolFeeController],
    from: admin,
  });
}

async function deployMocked(deployment: VaultDeploymentParams, authorizer: BaseContract): Promise<VaultMock> {
  const { admin, pauseWindowDuration, bufferPeriodDuration } = deployment;

  const futureVaultAddress = await getVaultAddress(admin);

  const vaultAdmin: VaultAdminMock = await contract.deploy('v3-vault/VaultAdminMock', {
    args: [futureVaultAddress, pauseWindowDuration, bufferPeriodDuration, 0, 0],
    from: admin,
  });

  const vaultExtension: VaultExtensionMock = await contract.deploy('v3-vault/VaultExtensionMock', {
    args: [futureVaultAddress, vaultAdmin],
    from: admin,
  });

  const protocolFeeController: ProtocolFeeController = await contract.deploy('v3-vault/ProtocolFeeController', {
    args: [futureVaultAddress],
    from: admin,
  });

  return await contract.deploy('v3-vault/VaultMock', {
    args: [vaultExtension, authorizer, protocolFeeController],
    from: admin,
  });
}

/// Returns the Vault address to be deployed, assuming the VaultExtension is deployed by the same account beforehand.
async function getVaultAddress(from: SignerWithAddress): Promise<string> {
  const nonce = await from.getNonce();
  const futureAddress = ethers.getCreateAddress({
    from: from.address,
    nonce: nonce + 3,
  });
  return futureAddress;
}

async function deployBasicAuthorizer(admin: SignerWithAddress): Promise<BasicAuthorizerMock> {
  return contract.deploy('v3-vault/BasicAuthorizerMock', { args: [], from: admin });
}
