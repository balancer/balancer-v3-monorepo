import { Contract } from 'ethers';
import { Interface } from 'ethers/lib/utils';

export const actionId = (
  instance: Contract,
  method: string,
  contractInterface?: Interface,
  chainId?: number
): Promise<string> => {
  const selector = (contractInterface ?? instance.interface).getSighash(method);

  return instance.getActionId(chainId ?? 1, selector);
};
