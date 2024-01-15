import { BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

export type VaultDeploymentInputParams = {
  admin?: SignerWithAddress;
  pauseWindowDuration?: BigNumberish;
  bufferPeriodDuration?: BigNumberish;
};

export type VaultDeploymentParams = {
  admin: SignerWithAddress;
  pauseWindowDuration: BigNumberish;
  bufferPeriodDuration: BigNumberish;
};
