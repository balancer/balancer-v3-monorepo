import { BigNumberish } from 'ethers';
import { bn } from '../numbers';

export function calculateSqrtQ0(
  currentTime: number,
  startSqrtQ0Fp: BigNumberish,
  endSqrtQ0Fp: BigNumberish,
  startTime: number,
  endTime: number
): bigint {
  if (currentTime > endTime) {
    return bn(endSqrtQ0Fp);
  }

  const numerator = bn(endTime - currentTime) * bn(startSqrtQ0Fp) + bn(currentTime - startTime) * bn(endSqrtQ0Fp);
  const denominator = bn(endTime - startTime);

  return numerator / denominator;
}
