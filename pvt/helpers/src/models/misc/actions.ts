import { Contract } from 'ethers';
import { Interface } from 'ethers/lib/utils';

export const actionId = (instance: Contract, method: string, contractInterface?: Interface): Promise<string> => {
  const selector = (contractInterface ?? instance.interface).getFunction(method).selector;

  return instance.getActionId(selector);
};
