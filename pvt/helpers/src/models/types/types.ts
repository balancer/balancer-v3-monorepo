import { Contract } from 'ethers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';

export type NAry<T> = T | Array<T>;

export type Account = string | SignerWithAddress | Contract | { address: string };

export type TxParams = {
  from?: SignerWithAddress;
};
