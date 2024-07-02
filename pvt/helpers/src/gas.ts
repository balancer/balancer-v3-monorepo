import { ContractTransactionReceipt } from 'ethers';
import fs from 'fs/promises';
import { printGas } from './numbers';
import path from 'path';

const SNAPS_DIR = '.hardhat-snapshots';

export async function saveSnap(basePath: string, snap: string, receipt: ContractTransactionReceipt | null) {
  if (receipt === null) {
    throw new Error('Save snap: null receipt');
  }

  if (process.env.COVERAGE) {
    // When coverage reports are running Via-IR flag is disabled, so gas measurement is not reliable
    return;
  }

  const gasUsed = printGas(receipt.gasUsed);

  try {
    const snapPath = path.resolve(basePath, SNAPS_DIR);
    await fs.writeFile(path.join(snapPath, snap), gasUsed);
  } catch (error) {
    throw new Error(`Error writing to snap ${snap}: ${error}`);
  }
}
