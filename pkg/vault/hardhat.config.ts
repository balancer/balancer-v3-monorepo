import { HardhatUserConfig } from 'hardhat/types/config';
import { name } from './package.json';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';

import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-ethers';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';
import 'hardhat-resolc';

import { warnings } from '@balancer-labs/v3-common/hardhat-base-config';

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
  resolc: {
    compilerSource: 'npm',
    settings: {},
  },
  warnings,
};

export default config;
