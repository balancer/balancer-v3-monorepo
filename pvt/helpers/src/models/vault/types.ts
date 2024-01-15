import { BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

export type VaultDeploymentInputParams = {
  mocked?: boolean;
  admin?: SignerWithAddress;
  pauseWindowDuration?: BigNumberish;
  bufferPeriodDuration?: BigNumberish;
};

export type VaultDeploymentParams = {
  mocked: boolean;
  pauseWindowDuration: BigNumberish;
  bufferPeriodDuration: BigNumberish;
  admin?: SignerWithAddress;
};
