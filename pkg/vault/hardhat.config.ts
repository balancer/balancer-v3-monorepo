import { HardhatUserConfig } from 'hardhat/types/config';
import { name } from './package.json';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';

import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-ethers';
import '@typechain/hardhat';

import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';
import '@parity/hardhat-polkadot-resolc';

import { warnings } from '@balancer-labs/v3-common/hardhat-base-config';
import { ResolcConfig } from 'hardhat-resolc/dist/types';

const resolc: ResolcConfig = {
  version: '0.8.27',
  compilerSource: 'npm',
  settings: {
    overwrite: true,
    optimizer: {
      enabled: true,
      parameters: 'z',
      fallbackOz: true,
    },
  },
};

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      polkavm: true,
    },
  },
  solidity: {
    compilers: [...hardhatBaseConfig.compilers],
    overrides: { ...hardhatBaseConfig.overrides(name) },
  },
  resolc,
  warnings,
};

export default config;
