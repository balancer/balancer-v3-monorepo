import { AddressLike, BigNumberish } from 'ethers';

import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';

import { NAry } from '../types/types';

export type RawTokensDeployment = number | NAry<RawTokenDeployment>;

export type TokensDeploymentOptions = {
  sorted?: boolean;
  varyDecimals?: boolean;
  from?: SignerWithAddress;
};

export type RawTokenDeployment =
  | string
  | {
      name?: string;
      symbol?: string;
      decimals?: number;
      from?: SignerWithAddress;
    };

export type TokenDeployment = {
  name: string;
  symbol: string;
  decimals: number;
  from?: SignerWithAddress;
};

export type RawTokenMint = NAry<{
  to: NAry<AddressLike>;
  from?: SignerWithAddress;
  amount: BigNumberish;
}>;

export type TokenMint = {
  to: AddressLike;
  from?: SignerWithAddress;
  amount: BigNumberish;
};

export type RawTokenApproval = NAry<{
  to: NAry<AddressLike>;
  from: NAry<SignerWithAddress>;
  amount: BigNumberish;
}>;

export type TokenApproval = {
  to: AddressLike;
  from: SignerWithAddress;
  amount: BigNumberish;
};
