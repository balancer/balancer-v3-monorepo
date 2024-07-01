import { BaseContract } from 'ethers';
import TypesConverter from '../types/TypesConverter';

export async function actionId(instance: BaseContract, method: string): Promise<string> {
  let selector;
  try {
    selector = instance.getFunction(method).fragment.selector;
  } catch (error) {
    const instanceAddress = await instance.getAddress();
    throw Error(`Contract ${instanceAddress} does not have the method "${method}"`);
  }

  const authenticationInterface = await TypesConverter.toIAuthentication(instance);
  return authenticationInterface.getActionId(selector);
}
