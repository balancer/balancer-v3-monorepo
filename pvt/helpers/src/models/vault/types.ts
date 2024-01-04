import { BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';
import { PoolRegistrationLib, Vault } from '@balancer-labs/v3-vault/typechain-types';
import { VaultMock } from '@balancer-labs/v3-vault/dist/typechain-types';

export type VaultDeploymentInputParams = {
  mocked?: boolean;
  admin?: SignerWithAddress;
  pauseWindowDuration?: BigNumberish;
  bufferPeriodDuration?: BigNumberish;
  from?: SignerWithAddress;
};

export type VaultDeploymentParams = {
  mocked: boolean;
  pauseWindowDuration: BigNumberish;
  bufferPeriodDuration: BigNumberish;
  admin?: SignerWithAddress;
  from?: SignerWithAddress;
};

export type VaultDeployment = {
  vault: Vault | VaultMock;
  poolRegistrationLib: PoolRegistrationLib;
};
