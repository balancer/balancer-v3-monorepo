import { BigNumberish } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

import { WETHTestToken } from '@balancer-labs/v3-solidity-utils/typechain-types';
import { IPermit2 } from '@balancer-labs/v3-vault/typechain-types';

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
