import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import '@typechain/hardhat';

import 'hardhat-ignore-warnings';
import 'hardhat-gas-reporter';

import { hardhatBaseConfig } from '@balancer-labs/v3-common';

import * as tdly from '@tenderly/hardhat-tenderly';
tdly.setup({ automaticVerifications: false });

export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    sepolia: {
      url: 'SEPOLIA_RPC_URL',
      accounts: ['SEPOLIA_PRIVATE_KEY'],
    },
  },
  solidity: {
    compilers: hardhatBaseConfig.compilers,
  },
  warnings: hardhatBaseConfig.warnings,
  tenderly: {
    project: 'v3',
    username: 'balancer',
    privateVerification: true,
  },
};
