import { Contract } from 'ethers';
import { Interface } from 'ethers/lib/utils';

export const actionId = (
  instance: Contract,
  method: string,
  contractInterface?: Interface,
  chainId?: number
): Promise<string> => {
  const selector = (contractInterface ?? instance.interface).getFunction(method).selector;

  return instance.getActionId(chainId ?? 1, selector);
};
