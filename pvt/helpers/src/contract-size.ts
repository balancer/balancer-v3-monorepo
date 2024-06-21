import fs from 'fs/promises';
import path from 'path';

const SNAPS_DIR = '.contract-sizes';

export async function saveSizeSnap(basePath: string, snap: string, deployedCodeSize: number, initCodeSize: number) {
  // see EIPs 170 and 3860 for more information
  // https://eips.ethereum.org/EIPS/eip-170
  // https://eips.ethereum.org/EIPS/eip-3860
  const DEPLOYED_SIZE_LIMIT = 24576;
  const INIT_SIZE_LIMIT = 49152;

  const UNITS = { B: 1, kB: 1000, KiB: 1024 };

  const formatSize = function (size: number, unit: string) {
    const divisor = UNITS[unit];
    return (size / divisor).toFixed(3);
  };

  let fmtDeploySize = formatSize(deployedCodeSize, 'KiB');
  if (deployedCodeSize > DEPLOYED_SIZE_LIMIT) {
    fmtDeploySize += '*';
  }
  let fmtInitSize = formatSize(initCodeSize, 'KiB');
  if (initCodeSize > INIT_SIZE_LIMIT) {
    fmtInitSize += '*';
  }

  try {
    const snapPath = path.resolve(basePath, SNAPS_DIR);
    await fs.writeFile(path.join(snapPath, snap), `Bytecode\t${fmtDeploySize}\nInitCode\t${fmtInitSize}`);
  } catch (error) {
    throw new Error(`Error writing to snap ${snap}: ${error}`);
  }
}
