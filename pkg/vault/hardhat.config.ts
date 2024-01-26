import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';
import 'hardhat-contract-sizer';

import { name } from './package.json';
import { hardhatBaseConfig } from '@balancer-labs/v3-common';

import * as tdly from '@tenderly/hardhat-tenderly';
tdly.setup({ automaticVerifications: false });

export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    sepolia: {
      url: '<RPC_URL_SEPOLIA>',
      accounts: ['PRIVATE_KEY_SEPOLIA'], // not sure if this one is needed
    },
  },
  solidity: {
    compilers: hardhatBaseConfig.compilers,
    overrides: { ...hardhatBaseConfig.overrides(name) },
  },
  warnings: hardhatBaseConfig.warnings,
  tenderly: {
    project: 'v2',
    username: 'balancer',
    privateVerification: true,
  },
};
