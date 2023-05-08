import { ethers } from 'ethers';
import { BigNumberish } from '../../numbers';

export const encodeJoin = (joinAmounts: BigNumberish[]): string =>
  encodeJoinExitMockPool(joinAmounts);

export const encodeExit = (exitAmounts: BigNumberish[]): string =>
  encodeJoinExitMockPool(exitAmounts);

function encodeJoinExitMockPool(amounts: BigNumberish[]): string {
  return ethers.utils.defaultAbiCoder.encode(['uint256[]'], [amounts]);
}
