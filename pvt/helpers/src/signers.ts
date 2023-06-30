import { ethers } from 'hardhat';
import { impersonateAccount, setBalance as setAccountBalance } from '@nomicfoundation/hardhat-network-helpers';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/dist/src/signer-with-address';
import { fp } from './numbers';

export async function getSigners(): Promise<SignerWithAddress[]> {
  const { ethers } = await import('hardhat');
  return ethers.getSigners();
}

export async function getSigner(index = 0): Promise<SignerWithAddress> {
  return (await getSigners())[index];
}

export async function impersonate(address: string, balance = fp(100)): Promise<SignerWithAddress> {
  await impersonateAccount(address);
  await setBalance(address, balance);

  return ethers.provider.getSigner(address);
}

export async function setBalance(address: string, balance: bigint): Promise<void> {
  await setAccountBalance(address, balance);
}
